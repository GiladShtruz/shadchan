import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/screen_perf.dart';

/// One page of cards shared with this matchmaker.
class NetworkPage {
  const NetworkPage(this.cards, this.cursor, {required this.hasMore});
  final List<SharedCard> cards;

  /// Where the next page starts (opaque to callers).
  final Object? cursor;
  final bool hasMore;
}

/// Reading what other matchmakers share with this one, ideas offered between
/// them, and the photos of both — **only when it is asked for**.
///
/// **No listener per matchmaker and no database downloaded whole** (the
/// pre-2026-11-20 version kept one live listener on every connected
/// matchmaker's whole shared database, for the life of the app). Cards are
/// read page by page ([pageSize]) by the screen that shows them, from the one
/// collection that names their readers; a single card is read once when a
/// chat or an idea needs it. What was read this session is remembered in
/// [cards] so a card drawn twice is not read twice, and forgotten on sign-out.
///
/// Ideas offered between matchmakers ([proposals]) are read on start and on
/// resume, and live only while a screen that shows them holds [watchProposals].
abstract final class MatchmakerNetwork {
  /// How many cards one read brings.
  static const int pageSize = 30;

  /// Every shared card read this session (pages, searches, single reads),
  /// by key — a cache, never "the whole pool".
  static final ValueNotifier<List<SharedCard>> cards =
      ValueNotifier<List<SharedCard>>(const <SharedCard>[]);
  static final Map<String, SharedCard> _byKey = <String, SharedCard>{};

  /// Cards sent to this matchmaker one by one, in a chat — read when that
  /// chat is opened.
  static final ValueNotifier<List<SharedCard>> sentToMe =
      ValueNotifier<List<SharedCard>>(const <SharedCard>[]);
  static final Map<String, List<SharedCard>> _sentByOwner =
      <String, List<SharedCard>>{};

  /// Every idea offered to or by this matchmaker.
  static final ValueNotifier<List<IdeaProposal>> proposals =
      ValueNotifier<List<IdeaProposal>>(const <IdeaProposal>[]);

  /// Kept for screens that waited on the old pool; always true once started.
  static final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  static String? _uid;
  static String? get uid => _uid ?? MatchmakerShares.uid;

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _proposalSub;
  static int _proposalWatchers = 0;
  static DateTime? _proposalsReadAt;

  /// Firestore listeners held here right now (for the performance log).
  static int get listenerCount => _proposalSub == null ? 0 : 1;

  /// The matchmakers this one shares with either way, by name.
  static Map<String, String> get connectedNames =>
      MatchmakerShares.connectedNames;

  static Future<void>? _startFuture;

  /// Starts once; a second caller waits for the same start instead of
  /// returning early (a screen asking for a live listener before the account
  /// was known would otherwise get none).
  static Future<void> start() {
    if (_uid != null || !FirebaseBootstrap.isReady) return Future<void>.value();
    return _startFuture ??= _start().whenComplete(() => _startFuture = null);
  }

  static Future<void> _start() async {
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      _uid = uid;
      ScreenPerf.cardsInMemory = () => _byKey.length;
      await MatchmakerShares.start();
      await refreshProposals(force: true);
      loaded.value = true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    }
  }

  /// App resume: the share rows and the ideas, once each, never the cards.
  static Future<void> resume() async {
    if (_uid == null) return;
    await MatchmakerShares.refresh();
    await refreshProposals();
  }

  static Future<void> stop() async {
    await _proposalSub?.cancel();
    _proposalSub = null;
    _proposalWatchers = 0;
    _proposalsReadAt = null;
    _uid = null;
    _byKey.clear();
    _sentByOwner.clear();
    cards.value = const <SharedCard>[];
    sentToMe.value = const <SharedCard>[];
    proposals.value = const <IdeaProposal>[];
    loaded.value = false;
    _photos.clear();
    _photoFiles.clear();
    _missing.clear();
    await MatchmakerShares.stop();
  }

  // --- Ideas offered between matchmakers ------------------------------------

  static Query<Map<String, dynamic>> _proposalQuery(String me) =>
      FirebaseFirestore.instance
          .collection('ideaProposals')
          .where('uids', arrayContains: me);

  /// One read of the ideas, unless a screen holds them live already.
  static Future<void> refreshProposals({bool force = false}) async {
    final String? me = _uid;
    if (me == null || _proposalSub != null) return;
    final DateTime now = DateTime.now();
    if (!force &&
        _proposalsReadAt != null &&
        now.difference(_proposalsReadAt!) < const Duration(seconds: 20)) {
      return;
    }
    _proposalsReadAt = now;
    try {
      ScreenPerf.noteQuery();
      _applyProposals(await _proposalQuery(me).get());
    } catch (error) {
      _log(error);
    }
  }

  /// Live ideas while a chat or a network screen is open. Returns the release.
  static VoidCallback watchProposals() {
    _proposalWatchers++;
    final String? me = _uid;
    if (_proposalSub == null && me != null) {
      ScreenPerf.noteQuery();
      _proposalSub = _proposalQuery(me).snapshots().listen((
        QuerySnapshot<Map<String, dynamic>> snap,
      ) {
        if (_uid == me) _applyProposals(snap);
      }, onError: _log);
    }
    bool released = false;
    return () {
      if (released) return;
      released = true;
      _proposalWatchers = (_proposalWatchers - 1).clamp(0, 1 << 20);
      if (_proposalWatchers == 0) {
        unawaited(_proposalSub?.cancel());
        _proposalSub = null;
      }
    };
  }

  static String _proposalPrint = '';

  static void _applyProposals(QuerySnapshot<Map<String, dynamic>> snap) {
    final String print = snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              '${d.id}:${d.data()['status']}:${d.data()['sides']}',
        )
        .join(';');
    if (print == _proposalPrint) return;
    _proposalPrint = print;
    proposals.value =
        <IdeaProposal>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
            ?IdeaProposal.fromMap(d.id, d.data()),
        ]..sort(
          (IdeaProposal a, IdeaProposal b) => (b.createdAt ?? DateTime(2000))
              .compareTo(a.createdAt ?? DateTime(2000)),
        );
  }

  // --- Cards, read on demand -----------------------------------------------

  static void _remember(Iterable<SharedCard> list) {
    bool changed = false;
    for (final SharedCard c in list) {
      _byKey[c.key] = c;
      _missing.remove(c.key);
      changed = true;
    }
    if (changed) cards.value = _byKey.values.toList(growable: false);
  }

  /// One page of the cards shared with this matchmaker, newest first —
  /// everybody's, or one matchmaker's ([ownerUid]); or, with [nameQuery],
  /// the cards whose name starts with it. The search runs on the server.
  static Future<NetworkPage> page({
    String? ownerUid,
    String? nameQuery,
    Object? cursor,
    int limit = pageSize,
  }) async {
    final String? me = uid;
    if (me == null || !FirebaseBootstrap.isReady) {
      return const NetworkPage(<SharedCard>[], null, hasMore: false);
    }
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection(SharedCardCodec.collection)
        .where('readers', arrayContains: me);
    if (ownerUid != null) q = q.where('ownerUid', isEqualTo: ownerUid);
    final String key = SharedCardCodec.nameKey(nameQuery ?? '');
    if (key.isNotEmpty) {
      q = q
          .where('nameKey', isGreaterThanOrEqualTo: key)
          .where('nameKey', isLessThan: '$key\uf8ff')
          .orderBy('nameKey');
    } else {
      q = q.orderBy('updatedAt', descending: true);
    }
    if (cursor is DocumentSnapshot) q = q.startAfterDocument(cursor);
    ScreenPerf.noteQuery();
    final QuerySnapshot<Map<String, dynamic>> snap = await q.limit(limit).get();
    final List<SharedCard> list = <SharedCard>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
        ?SharedCard.fromMap(d.data()),
    ];
    _remember(list);
    return NetworkPage(
      list,
      snap.docs.isEmpty ? null : snap.docs.last,
      hasMore: snap.docs.length >= limit,
    );
  }

  /// Keys known to be unreadable this session (access removed, or gone).
  static final Set<String> _missing = <String>{};
  static final Map<String, Future<SharedCard?>> _reading =
      <String, Future<SharedCard?>>{};

  /// One card, read once and remembered — for a chat object or an idea.
  /// Null when it is not (or no longer) shared with this matchmaker.
  static Future<SharedCard?> fetchCard(
    String ownerUid,
    String personId, {
    bool refresh = false,
  }) {
    final String key = SharedCard.keyOf(ownerUid, personId);
    if (!FirebaseBootstrap.isReady) return Future<SharedCard?>.value();
    if (!refresh) {
      final SharedCard? known = cardOf(ownerUid, personId);
      if (known != null) return Future<SharedCard?>.value(known);
      if (_missing.contains(key)) return Future<SharedCard?>.value();
    }
    return _reading.putIfAbsent(key, () async {
      try {
        ScreenPerf.noteQuery();
        final DocumentSnapshot<Map<String, dynamic>> doc =
            await FirebaseFirestore.instance
                .collection(SharedCardCodec.collection)
                .doc(SharedCardCodec.docId(ownerUid, personId))
                .get();
        final SharedCard? card = doc.exists
            ? SharedCard.fromMap(doc.data()!)
            : null;
        if (card == null) {
          _forget(key);
        } else {
          _remember(<SharedCard>[card]);
        }
        return card;
      } catch (_) {
        // Permission denied: the owner no longer shares it with us.
        _forget(key);
        return null;
      } finally {
        unawaited(Future<void>(() => _reading.remove(key)));
      }
    });
  }

  static void _forget(String key) {
    _missing.add(key);
    if (_byKey.remove(key) != null) {
      cards.value = _byKey.values.toList(growable: false);
    }
  }

  /// Whether this card is known to be unreadable now (a shared idea's card
  /// whose owner took it out of the share).
  static bool isGone(String ownerUid, String personId) =>
      _missing.contains(SharedCard.keyOf(ownerUid, personId));

  /// The cards [ownerUid] sent to this matchmaker in their chat — read when
  /// that chat opens.
  static Future<void> loadSentFrom(String ownerUid) async {
    final String? me = uid;
    if (me == null || !FirebaseBootstrap.isReady) return;
    try {
      ScreenPerf.noteQuery();
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('sentCards')
          .doc(ownerUid)
          .collection('to')
          .doc(me)
          .collection('cards')
          .get();
      _sentByOwner[ownerUid] = <SharedCard>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
          ?SharedCard.fromMap(d.data()),
      ];
    } catch (_) {
      _sentByOwner.remove(ownerUid);
    }
    sentToMe.value = <SharedCard>[
      for (final List<SharedCard> l in _sentByOwner.values) ...l,
    ];
  }

  /// How many cards [ownerUid] shares with this matchmaker.
  static int sharedBy(String ownerUid) =>
      MatchmakerShares.sharedWithMeCount(ownerUid);

  /// The shared card [personId] of [ownerUid], if it was read this session —
  /// or was sent to this matchmaker in a chat.
  static SharedCard? cardOf(String ownerUid, String personId) {
    final SharedCard? known = _byKey[SharedCard.keyOf(ownerUid, personId)];
    if (known != null) return known;
    for (final SharedCard c in sentToMe.value) {
      if (c.ownerUid == ownerUid && c.personId == personId) return c;
    }
    return null;
  }

  /// Uploads [person]'s shareable photos under this matchmaker's
  /// `sharedCards/` folder and returns their Storage paths.
  static Future<List<String>> _uploadPhotos(String me, Person person) async {
    final List<String> paths = <String>[];
    for (final String local in CardPhotoPrivacy.shareable(person)) {
      if (paths.length >= SharedCardCodec.maxPhotos) break;
      final String name = PhotoPickerService.basenameOf(local);
      final File file = await PhotoPickerService.fileFor(name);
      if (!await file.exists()) continue;
      final String remote = SharedCardCodec.photoPath(me, person.id, name);
      final Reference ref = FirebaseStorage.instance.ref(remote);
      try {
        await ref.getMetadata();
      } catch (_) {
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      }
      paths.add(remote);
    }
    return paths;
  }

  /// Sends [person]'s card to one matchmaker — from a chat, on purpose, by
  /// the matchmaker who holds it. View only, the same fields as a shared
  /// card; only [toUid] reads it. A matchmaker who only *sees* a card can
  /// never send it on: it is not in their database to send.
  static Future<bool> sendCard({
    required Person person,
    required String toUid,
    required String myName,
  }) async {
    final String? me = uid ?? await PersonalCardService.durableUid();
    if (me == null || toUid == me) return false;
    try {
      final List<String> paths = await _uploadPhotos(me, person);
      if (paths.isEmpty) return false;
      await FirebaseFirestore.instance
          .collection('sentCards')
          .doc(me)
          .collection('to')
          .doc(toUid)
          .collection('cards')
          .doc(person.id)
          .set(
            SharedCardCodec.toRemote(
              person,
              ownerUid: me,
              ownerName: myName,
              photoPaths: paths,
            ),
          );
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  static IdeaProposal? proposal(String id) {
    for (final IdeaProposal p in proposals.value) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Ideas offered to this matchmaker and not answered yet.
  static List<IdeaProposal> get incomingPending => <IdeaProposal>[
    for (final IdeaProposal p in proposals.value)
      if (p.toUid == uid && p.status == IdeaProposalStatus.pending) p,
  ];

  // --- Photos --------------------------------------------------------------

  static final Map<String, Future<File?>> _photos = <String, Future<File?>>{};

  /// A photo of a shared card, fetched once through the `sharedCardPhoto`
  /// callable and kept in the app's own cache folder. Never a download URL.
  static Future<File?> photo(String ownerUid, String path) {
    final String key = '$ownerUid|$path';
    return _photos.putIfAbsent(key, () async {
      final File? file = await _fetchPhoto(ownerUid, path);
      if (file != null) _photoFiles[key] = file;
      return file;
    });
  }

  /// Photos already on the device, by key — so a list drawn again shows the
  /// face at once instead of the default avatar for a frame (a flicker on
  /// every scroll of a long list).
  static final Map<String, File> _photoFiles = <String, File>{};

  /// The photo when it has already been fetched, else null.
  static File? photoNow(String ownerUid, String path) =>
      _photoFiles['$ownerUid|$path'];

  static Future<File?> _fetchPhoto(String ownerUid, String path) async {
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory dir = Directory('${base.path}/network_photos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final String safe = path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final File file = File('${dir.path}/$safe');
      if (await file.exists() && await file.length() > 0) return file;
      ScreenPerf.notePhoto();
      final HttpsCallableResult<dynamic> result =
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable(
                'sharedCardPhoto',
                options: HttpsCallableOptions(
                  timeout: const Duration(seconds: 60),
                ),
              )
              .call(<String, Object?>{'ownerUid': ownerUid, 'path': path});
      final Object? data = result.data;
      final Object? encoded = data is Map ? data['data'] : null;
      if (encoded is! String || encoded.isEmpty) return null;
      await file.writeAsBytes(base64Decode(encoded), flush: true);
      return file;
    } catch (error) {
      _photos.remove('$ownerUid|$path');
      _log(error);
      return null;
    }
  }

  // --- Ideas between matchmakers ---------------------------------------------

  /// Offers [candidate] from this matchmaker's database for [target]. The
  /// candidate's card travels as a snapshot — the same fields a shared card
  /// carries, never a phone or a note — with its photos.
  static Future<String?> propose({
    required SharedCard target,
    required Person candidate,
    required String myName,
    String note = '',
  }) async {
    final String? me = uid;
    if (me == null) return null;
    try {
      final List<String> paths = await _uploadPhotos(me, candidate);
      final Map<String, Object?> candidateMap = <String, Object?>{
        ...SharedCardCodec.values(candidate, ownerUid: me, ownerName: myName),
        'photoPaths': paths,
      };
      final Map<String, Object?> targetMap = <String, Object?>{
        ...SharedCardCodec.values(
          target.person,
          ownerUid: target.ownerUid,
          ownerName: target.ownerName,
        ),
        'personId': target.personId,
        'identity': target.identity,
        'cardOwnerUid': target.cardOwnerUid,
        'photoPaths': target.photoPaths,
      };
      final String trimmed = note.trim();
      final DocumentReference<Map<String, dynamic>> doc = FirebaseFirestore
          .instance
          .collection('ideaProposals')
          .doc();
      await doc.set(<String, Object?>{
        'fromUid': me,
        'toUid': target.ownerUid,
        'uids': <String>[me, target.ownerUid],
        'fromName': _short(myName),
        'toName': _short(target.ownerName),
        'status': 'pending',
        'target': targetMap,
        'candidate': candidateMap,
        'note': trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed,
        'sides': <String, Object?>{},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return null;
    }
  }

  /// The side asked says yes or no. A "no" stays in the chat's history and
  /// opens nothing; **a "yes" opens the idea at once** (2026-11-21) — an
  /// ordinary idea in both "הרעיונות שלי", starting at "רעיון", one shared
  /// record ([SharedIdeaState]) that both sides move.
  static Future<bool> answer(IdeaProposal p, {required bool approve}) async {
    final String? me = uid;
    if (me == null || me != p.toUid || p.status != IdeaProposalStatus.pending) {
      return false;
    }
    try {
      await FirebaseFirestore.instance
          .collection('ideaProposals')
          .doc(p.id)
          .update(<String, Object?>{
            'status': approve ? 'opened' : 'declined',
            if (approve)
              'idea': const SharedIdeaState(status: MatchStatus.idea).toMap(me),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  /// Either side opens an agreed idea — the moment they really ask the two
  /// friends. Only then does it appear in both "הרעיונות שלי".
  static Future<bool> open(IdeaProposal p) async {
    final String? me = uid;
    if (me == null ||
        !(me == p.fromUid || me == p.toUid) ||
        p.status != IdeaProposalStatus.approved) {
      return false;
    }
    try {
      await FirebaseFirestore.instance
          .collection('ideaProposals')
          .doc(p.id)
          .update(<String, Object?>{
            'status': 'opened',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  /// The side who asked takes it back before an answer.
  static Future<bool> withdraw(IdeaProposal p) async {
    if (uid != p.fromUid || p.status != IdeaProposalStatus.pending) {
      return false;
    }
    try {
      await FirebaseFirestore.instance
          .collection('ideaProposals')
          .doc(p.id)
          .update(<String, Object?>{
            'status': 'withdrawn',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  /// Writes where the one shared idea stands now — status and who was asked
  /// — for the other matchmaker's copy to follow; and this side's status in
  /// `sides`, which the chat's small system lines are written from.
  static Future<void> reportShared(
    String proposalId,
    SharedIdeaState state,
  ) async {
    final String? me = uid;
    if (me == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('ideaProposals')
          .doc(proposalId)
          .update(<String, Object?>{
            'idea': state.toMap(me),
            'sides.$me': <String, Object?>{'status': state.status.name},
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      _log(error);
    }
  }

  /// Whether the ideas are being listened to live right now.
  static bool get proposalsLive => _proposalSub != null;

  /// Where this side's half of an approved idea stands, for the other side.
  static Future<void> reportSide(String proposalId, String statusName) async {
    final String? me = uid;
    if (me == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('ideaProposals')
          .doc(proposalId)
          .update(<String, Object?>{
            'sides.$me': <String, Object?>{'status': statusName},
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      _log(error);
    }
  }

  static String _short(String name) {
    final String t = name.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  static void _log(Object error, [StackTrace? stackTrace]) {
    debugPrint('MatchmakerNetwork: $error');
  }

  /// Test seam: a pool and proposals as if the server had sent them.
  @visibleForTesting
  static void debugSet({
    required String uid,
    List<SharedCard> cards = const <SharedCard>[],
    List<IdeaProposal> proposals = const <IdeaProposal>[],
    List<SharedCard> sent = const <SharedCard>[],
  }) {
    _uid = uid;
    _byKey
      ..clear()
      ..addEntries(
        cards.map((SharedCard c) => MapEntry<String, SharedCard>(c.key, c)),
      );
    MatchmakerNetwork.cards.value = cards;
    sentToMe.value = sent;
    MatchmakerNetwork.proposals.value = proposals;
    loaded.value = true;
  }
}
