import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/enums.dart';

/// The tie between two partners — `partnerships/{a}_{b}`, uids sorted.
class Partnership {
  const Partnership({
    required this.id,
    required this.uids,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.names,
    this.updatedAt,
  });

  final String id;
  final List<String> uids;
  final String fromUid;
  final String toUid;

  /// `pending` (invited, waiting for the other's yes), `active` or `ended`.
  final String status;
  final Map<String, String> names;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  String otherOf(String me) =>
      uids.firstWhere((String u) => u != me, orElse: () => '');

  String nameOf(String uid) => (names[uid] ?? '').trim();

  static String idFor(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  static Partnership? fromMap(String id, Map<String, dynamic> data) {
    final Object? uids = data['uids'];
    final Object? from = data['fromUid'];
    final Object? to = data['toUid'];
    final Object? status = data['status'];
    if (uids is! List ||
        from is! String ||
        to is! String ||
        status is! String) {
      return null;
    }
    final Object? names = data['names'];
    final Object? at = data['updatedAt'];
    return Partnership(
      id: id,
      uids: <String>[
        for (final Object? u in uids)
          if (u is String) u,
      ],
      fromUid: from,
      toUid: to,
      status: status,
      names: <String, String>{
        if (names is Map)
          for (final MapEntry<dynamic, dynamic> e in names.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      updatedAt: at is Timestamp ? at.toDate() : null,
    );
  }

  /// The one tie shown for an account: an active one first, then an
  /// invitation (the newest), never one that ended.
  static Partnership? currentOf(Iterable<Partnership> all) {
    Partnership? best;
    for (final Partnership p in all) {
      if (p.status == 'ended') continue;
      if (best == null) {
        best = p;
        continue;
      }
      if (p.isActive && !best.isActive) {
        best = p;
      } else if (p.isActive == best.isActive &&
          (p.updatedAt ?? DateTime(2000)).isAfter(
            best.updatedAt ?? DateTime(2000),
          )) {
        best = p;
      }
    }
    return best;
  }
}

/// **The couple space** (2026-11-20): two personal accounts, two personal
/// databases, and one tie between them.
///
/// It replaces the old couple database, which merged two databases into one
/// shared account — and stalled, and lost card permissions on the way. Here
/// nothing is merged, moved or copied:
///
///  - each partner keeps their own account, their own database, their own
///    phone's contacts and full ownership of the friends they added;
///  - while the tie is active each publishes their database to
///    `partnerCards/{uid}/cards` — the card fields, photos, tags and "מה
///    מחפש", never a phone, a note, history or a reminder — and the other
///    reads it, view only. A friend hidden from every other matchmaker is
///    still visible to the partner;
///  - an idea between a friend of each opens at once on both phones (an
///    `ideaProposals` row written approved), each partner responsible for
///    their own friend, both seeing where it stands;
///  - one continuing chat (`kind: partners`);
///  - ending the tie closes every read at once; each database stays exactly
///    as it was, and ideas already opened stay with both as history.
///
/// A single who takes access away from a matchmaker takes it away from the
/// partner too: the matchmaker's copy loses the card, and the next publish
/// carries that.
abstract final class PartnerSpace {
  static final ValueNotifier<Partnership?> current =
      ValueNotifier<Partnership?>(null);

  /// The partner's database, live, while the tie is active.
  static final ValueNotifier<List<SharedCard>> partnerCards =
      ValueNotifier<List<SharedCard>>(const <SharedCard>[]);

  /// Whether the partner's database has been heard from the server yet.
  static final ValueNotifier<bool> partnerCardsLoaded = ValueNotifier<bool>(
    false,
  );

  /// The most photos of one friend that travel to the partner.
  static const int maxPhotos = 3;

  static String? _uid;
  static String? get uid => _uid;
  static bool _starting = false;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cardsSub;
  static String? _cardsOf;

  static bool get isActive => current.value?.isActive ?? false;

  /// The partner's uid, while the tie is active.
  static String? get partnerUid {
    final Partnership? p = current.value;
    final String? me = _uid;
    if (p == null || !p.isActive || me == null) return null;
    final String other = p.otherOf(me);
    return other.isEmpty ? null : other;
  }

  static String get partnerName {
    final Partnership? p = current.value;
    final String? me = _uid;
    if (p == null || me == null) return '';
    return p.nameOf(p.otherOf(me));
  }

  static String get partnerFirstName {
    final String n = partnerName;
    return n.isEmpty ? 'בן/בת הזוג' : n.split(RegExp(r'\s+')).first;
  }

  static bool isPartner(String uid) => uid.isNotEmpty && partnerUid == uid;

  static Future<void> start() async {
    if (_uid != null || _starting || !FirebaseBootstrap.isReady) return;
    _starting = true;
    try {
      final String? me = await PersonalCardService.durableUid();
      if (me == null) return;
      _uid = me;
      _pairSub = FirebaseFirestore.instance
          .collection('partnerships')
          .where('uids', arrayContains: me)
          .snapshots()
          .listen((QuerySnapshot<Map<String, dynamic>> snap) {
            if (_uid != me) return;
            current.value = Partnership.currentOf(<Partnership>[
              for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                  in snap.docs)
                ?Partnership.fromMap(d.id, d.data()),
            ]);
            _followPartner();
          }, onError: _log);
    } catch (error) {
      _log(error);
    } finally {
      _starting = false;
    }
  }

  static Future<void> stop() async {
    await _pairSub?.cancel();
    await _cardsSub?.cancel();
    _pairSub = null;
    _cardsSub = null;
    _cardsOf = null;
    _uid = null;
    _lastPrint = null;
    current.value = null;
    partnerCards.value = const <SharedCard>[];
    partnerCardsLoaded.value = false;
  }

  /// Listens to the partner's database while the tie is active — and stops
  /// the moment it is not.
  static void _followPartner() {
    final String? partner = partnerUid;
    if (partner == _cardsOf) return;
    unawaited(_cardsSub?.cancel());
    _cardsSub = null;
    _cardsOf = partner;
    partnerCards.value = const <SharedCard>[];
    partnerCardsLoaded.value = false;
    if (partner == null) return;
    _cardsSub = FirebaseFirestore.instance
        .collection('partnerCards')
        .doc(partner)
        .collection('cards')
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snap) {
          if (_cardsOf != partner) return;
          final List<SharedCard> cards =
              <SharedCard>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                    in snap.docs)
                  ?SharedCard.fromMap(d.data()),
              ]..sort(
                (SharedCard a, SharedCard b) =>
                    a.person.fullName.compareTo(b.person.fullName),
              );
          partnerCards.value = cards;
          if (!snap.metadata.isFromCache) partnerCardsLoaded.value = true;
        }, onError: _log);
  }

  // --- The tie --------------------------------------------------------------

  /// Invites [otherUid] — the partner says yes on their own phone.
  static Future<bool> invite({
    required String otherUid,
    required String myName,
    required String theirName,
  }) async {
    final String? me = _uid ?? await PersonalCardService.durableUid();
    if (me == null || otherUid.isEmpty || otherUid == me) return false;
    if (isActive) return false;
    final DocumentReference<Map<String, dynamic>> doc = FirebaseFirestore
        .instance
        .collection('partnerships')
        .doc(Partnership.idFor(me, otherUid));
    final Map<String, String> names = <String, String>{
      me: _short(myName),
      otherUid: _short(theirName),
    };
    try {
      bool exists = false;
      try {
        exists = (await doc.get()).exists;
      } catch (_) {
        // Unreadable: it does not exist yet.
      }
      if (exists) {
        await doc.update(<String, Object?>{
          'fromUid': me,
          'toUid': otherUid,
          'status': 'pending',
          'names': names,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await doc.set(<String, Object?>{
          'uids': <String>[me, otherUid]..sort(),
          'fromUid': me,
          'toUid': otherUid,
          'status': 'pending',
          'names': names,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return true;
    } catch (error) {
      _log(error);
      return false;
    }
  }

  /// The partner invited says yes — the tie is active from now on.
  static Future<bool> accept(Partnership p) =>
      _update(p, <String, Object?>{'status': 'active'});

  /// Ends the tie — or withdraws / declines an invitation. Nothing is deleted
  /// from either database; what each published for the other is taken down.
  static Future<bool> end(Partnership p) async {
    final bool ok = await _update(p, <String, Object?>{
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });
    if (ok) {
      _lastPrint = null;
      unawaited(_takeDownMine());
    }
    return ok;
  }

  static Future<bool> _update(Partnership p, Map<String, Object?> data) async {
    try {
      await FirebaseFirestore.instance
          .collection('partnerships')
          .doc(p.id)
          .update(<String, Object?>{
            ...data,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return true;
    } catch (error) {
      _log(error);
      return false;
    }
  }

  // --- Publishing this database to the partner ------------------------------

  /// Who of [people] the partner sees: everybody in the database — complete
  /// card or not — except records that are not part of it (hidden ones, a
  /// partner's friend kept for a shared idea, drafts waiting for review) and
  /// friends who married (no longer someone to think about).
  static List<Person> publishable(Iterable<Person> people) => <Person>[
    for (final Person p in people)
      if (!p.hidden &&
          !p.needsReview &&
          p.profileStatus != ProfileStatus.mazelTov &&
          !SharedIdeas.isPartnersPerson(p.id))
        p,
  ];

  static String photoPath(String ownerUid, String personId, String basename) =>
      'partnerCards/$ownerUid/$personId/$basename';

  static bool _running = false;
  static bool _again = false;

  /// What was last published in full, so an unchanged database costs no
  /// server read at all — the publish runs on every change of the database,
  /// and most of them do not touch anything the partner sees.
  static String? _lastPrint;

  /// Brings `partnerCards/{uid}/cards` to exactly [publishable], writing only
  /// what changed. Quiet on any failure — the next change tries again.
  static Future<void> publish({
    required Iterable<Person> people,
    required String ownerName,
  }) async {
    if (!FirebaseBootstrap.isReady || !isActive) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _publishOnce(people.toList(), ownerName);
      } while (_again && isActive);
    } catch (error) {
      _log(error);
    } finally {
      _running = false;
    }
  }

  static Future<void> _publishOnce(
    List<Person> people,
    String ownerName,
  ) async {
    final String? me = _uid;
    if (me == null) return;
    final List<Person> shown = publishable(people);
    // Hashed on a background isolate: the whole database, encoded on the UI
    // thread, was a visible freeze (and the full text was kept in memory).
    final String print = await SyncStateStore.fingerprintInBackground(
      <String, Object?>{
        'partner': partnerUid ?? '',
        'cards': <Object?>[
          for (final Person p in shown)
            <Object?>[
              p.id,
              SharedCardCodec.values(p, ownerUid: me, ownerName: ownerName),
              CardPhotoPrivacy.shareable(
                p,
              ).take(maxPhotos).map(PhotoPickerService.basenameOf).toList(),
            ],
        ],
      },
    );
    if (print == _lastPrint) return;
    final CollectionReference<Map<String, dynamic>> col = FirebaseFirestore
        .instance
        .collection('partnerCards')
        .doc(me)
        .collection('cards');
    final QuerySnapshot<Map<String, dynamic>> remote = await col.get(
      const GetOptions(source: Source.server),
    );
    final Map<String, Map<String, dynamic>> held =
        <String, Map<String, dynamic>>{
          for (final QueryDocumentSnapshot<Map<String, dynamic>> d
              in remote.docs)
            d.id: d.data(),
        };
    final Map<String, Person> desired = <String, Person>{
      for (final Person p in shown) p.id: p,
    };
    for (final String id in held.keys) {
      if (!desired.containsKey(id)) {
        await col.doc(id).delete();
        await _deletePhotos(me, id, keep: const <String>{});
      }
    }
    for (final Person person in desired.values) {
      if (!isActive) return;
      final List<File> files = <File>[];
      for (final String path in CardPhotoPrivacy.shareable(person)) {
        if (files.length >= maxPhotos) break;
        final File file = await PhotoPickerService.fileFor(
          PhotoPickerService.basenameOf(path),
        );
        if (await file.exists()) files.add(file);
      }
      final List<String> paths = <String>[
        for (final File f in files)
          photoPath(me, person.id, PhotoPickerService.basenameOf(f.path)),
      ];
      final Map<String, Object?> values = SharedCardCodec.values(
        person,
        ownerUid: me,
        ownerName: ownerName,
      );
      final Map<String, dynamic>? before = held[person.id];
      final List<Object?> heldPaths =
          (before?['photoPaths'] as List?) ?? const <Object?>[];
      if (before != null &&
          _sameValues(values, before) &&
          listEquals(heldPaths, paths)) {
        continue;
      }
      for (int i = 0; i < files.length; i++) {
        if (heldPaths.contains(paths[i])) continue;
        await FirebaseStorage.instance
            .ref(paths[i])
            .putFile(files[i], SettableMetadata(contentType: 'image/jpeg'));
      }
      await col.doc(person.id).set(<String, Object?>{
        ...values,
        'photoPaths': paths,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (before != null) {
        await _deletePhotos(me, person.id, keep: paths.toSet());
      }
    }
    _lastPrint = print;
  }

  static bool _sameValues(
    Map<String, Object?> values,
    Map<String, dynamic> held,
  ) {
    for (final MapEntry<String, Object?> e in values.entries) {
      if (jsonEncode(e.value) != jsonEncode(held[e.key])) return false;
    }
    return true;
  }

  static Future<void> _deletePhotos(
    String me,
    String personId, {
    required Set<String> keep,
  }) async {
    try {
      final ListResult list = await FirebaseStorage.instance
          .ref('partnerCards/$me/$personId')
          .listAll();
      for (final Reference ref in list.items) {
        if (!keep.contains(ref.fullPath)) await ref.delete();
      }
    } catch (error) {
      _log(error);
    }
  }

  /// Everything this account published for a partner, gone — on an end.
  static Future<void> _takeDownMine() async {
    final String? me = _uid;
    if (me == null) return;
    try {
      final CollectionReference<Map<String, dynamic>> col = FirebaseFirestore
          .instance
          .collection('partnerCards')
          .doc(me)
          .collection('cards');
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d
          in (await col.get()).docs) {
        await d.reference.delete();
        await _deletePhotos(me, d.id, keep: const <String>{});
      }
    } catch (error) {
      _log(error);
    }
  }

  // --- Ideas between the two databases --------------------------------------

  /// Opens an idea between [mine] (this database) and [target] (the
  /// partner's) — at once, on both phones, with no request for approval.
  /// Returns the proposal id, or null.
  static Future<String?> openIdea({
    required Person mine,
    required SharedCard target,
    required String myName,
  }) async {
    final String? me = _uid;
    final String? partner = partnerUid;
    if (me == null || partner == null || target.ownerUid != partner) {
      return null;
    }
    try {
      // The candidate's photos are the ones already published to the partner.
      final List<String> paths = <String>[
        for (final String path in CardPhotoPrivacy.shareable(
          mine,
        ).take(maxPhotos))
          photoPath(me, mine.id, PhotoPickerService.basenameOf(path)),
      ];
      final DocumentReference<Map<String, dynamic>> doc = FirebaseFirestore
          .instance
          .collection('ideaProposals')
          .doc();
      await doc.set(<String, Object?>{
        'fromUid': me,
        'toUid': partner,
        'uids': <String>[me, partner],
        'fromName': _short(myName),
        'toName': _short(target.ownerName),
        // Between partners an idea opens at once — no question asked.
        'status': 'opened',
        'target': <String, Object?>{
          ...SharedCardCodec.values(
            target.person,
            ownerUid: target.ownerUid,
            ownerName: target.ownerName,
          ),
          'personId': target.personId,
          'identity': target.identity,
          'cardOwnerUid': target.cardOwnerUid,
          'photoPaths': target.photoPaths,
        },
        'candidate': <String, Object?>{
          ...SharedCardCodec.values(mine, ownerUid: me, ownerName: myName),
          'photoPaths': paths,
        },
        'note': '',
        'sides': <String, Object?>{},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (error) {
      _log(error);
      return null;
    }
  }

  static String _short(String name) {
    final String t = name.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  static void _log(Object error) => debugPrint('PartnerSpace: $error');

  /// Test seam.
  @visibleForTesting
  static void debugSet({
    required String uid,
    Partnership? partnership,
    List<SharedCard> cards = const <SharedCard>[],
  }) {
    _uid = uid;
    current.value = partnership;
    partnerCards.value = cards;
    partnerCardsLoaded.value = true;
  }
}
