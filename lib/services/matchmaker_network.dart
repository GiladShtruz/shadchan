import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/matchmaker_connections.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';

/// The network of the matchmakers this one is connected with, live: the
/// cards they share, and the ideas offered between them.
///
/// **It follows the connections.** One listener per approved connection on
/// `sharedCards/{theirUid}/cards`; the moment a connection goes, so do its
/// listener and its cards — they are gone from the pool before the server
/// even answers. The rules refuse the read too, so a stale listener could
/// not keep them.
///
/// Static and notifier-based like [MatchmakerConnections], started once
/// Firebase and a durable account are up and stopped before a sign-out.
abstract final class MatchmakerNetwork {
  /// Every card shared with this matchmaker, from every connection.
  static final ValueNotifier<List<SharedCard>> cards =
      ValueNotifier<List<SharedCard>>(const <SharedCard>[]);

  /// Cards sent to this matchmaker one by one, in a chat — not in the pool.
  static final ValueNotifier<List<SharedCard>> sentToMe =
      ValueNotifier<List<SharedCard>>(const <SharedCard>[]);

  /// Every idea offered to or by this matchmaker.
  static final ValueNotifier<List<IdeaProposal>> proposals =
      ValueNotifier<List<IdeaProposal>>(const <IdeaProposal>[]);

  /// Whether the cards were read at least once — before that, an empty pool
  /// means "not known yet".
  static final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  static String? _uid;
  static String? get uid => _uid;
  static bool _starting = false;
  static final Map<
    String,
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  >
  _cardSubs =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  static final Map<String, List<SharedCard>> _byOwner =
      <String, List<SharedCard>>{};
  static final Map<
    String,
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  >
  _sentSubs =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  static final Map<String, List<SharedCard>> _sentByOwner =
      <String, List<SharedCard>>{};
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _proposalSub;

  /// The approved connections' uids, by their names as this side knows them.
  static Map<String, String> get connectedNames {
    final String? me = _uid ?? MatchmakerConnections.uid;
    if (me == null) return const <String, String>{};
    return <String, String>{
      for (final MatchmakerConnection c
          in MatchmakerConnections.connections.value)
        if (c.isConnected) c.otherOf(me): (c.names[c.otherOf(me)] ?? '').trim(),
    };
  }

  static Future<void> start() async {
    if (_uid != null || _starting || !FirebaseBootstrap.isReady) return;
    _starting = true;
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      _uid = uid;
      await MatchmakerConnections.start();
      MatchmakerConnections.connections.addListener(_syncListeners);
      _syncListeners();
      _proposalSub = FirebaseFirestore.instance
          .collection('ideaProposals')
          .where('uids', arrayContains: uid)
          .snapshots()
          .listen((QuerySnapshot<Map<String, dynamic>> snap) {
            if (_uid != uid) return;
            final List<IdeaProposal> list =
                <IdeaProposal>[
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                      in snap.docs)
                    ?IdeaProposal.fromMap(d.id, d.data()),
                ]..sort(
                  (IdeaProposal a, IdeaProposal b) =>
                      (b.createdAt ?? DateTime(2000)).compareTo(
                        a.createdAt ?? DateTime(2000),
                      ),
                );
            proposals.value = list;
          }, onError: _log);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _starting = false;
    }
  }

  static Future<void> stop() async {
    MatchmakerConnections.connections.removeListener(_syncListeners);
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _cardSubs.values) {
      await s.cancel();
    }
    _cardSubs.clear();
    _byOwner.clear();
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _sentSubs.values) {
      await s.cancel();
    }
    _sentSubs.clear();
    _sentByOwner.clear();
    sentToMe.value = const <SharedCard>[];
    await _proposalSub?.cancel();
    _proposalSub = null;
    _uid = null;
    cards.value = const <SharedCard>[];
    proposals.value = const <IdeaProposal>[];
    loaded.value = false;
    _photos.clear();
  }

  static void _syncListeners() {
    final String? me = _uid;
    if (me == null) return;
    final Set<String> connected = connectedNames.keys.toSet();
    for (final String gone
        in _cardSubs.keys
            .where((String u) => !connected.contains(u))
            .toList()) {
      unawaited(_cardSubs.remove(gone)?.cancel());
      _byOwner.remove(gone);
    }
    for (final String gone
        in _sentSubs.keys
            .where((String u) => !connected.contains(u))
            .toList()) {
      unawaited(_sentSubs.remove(gone)?.cancel());
      _sentByOwner.remove(gone);
    }
    for (final String other in connected) {
      if (_sentSubs.containsKey(other)) continue;
      _sentSubs[other] = FirebaseFirestore.instance
          .collection('sentCards')
          .doc(other)
          .collection('to')
          .doc(me)
          .collection('cards')
          .snapshots()
          .listen(
            (QuerySnapshot<Map<String, dynamic>> snap) {
              _sentByOwner[other] = <SharedCard>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                    in snap.docs)
                  ?SharedCard.fromMap(d.data()),
              ];
              _publish();
            },
            onError: (Object error) {
              _sentByOwner.remove(other);
              _publish();
            },
          );
    }
    for (final String other in connected) {
      if (_cardSubs.containsKey(other)) continue;
      _cardSubs[other] = FirebaseFirestore.instance
          .collection('sharedCards')
          .doc(other)
          .collection('cards')
          .snapshots()
          .listen(
            (QuerySnapshot<Map<String, dynamic>> snap) {
              _byOwner[other] = <SharedCard>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                    in snap.docs)
                  ?SharedCard.fromMap(d.data()),
              ];
              _publish();
            },
            onError: (Object error) {
              // A connection that just ended: the rules said no.
              _byOwner.remove(other);
              _publish();
            },
          );
    }
    if (connected.isEmpty) loaded.value = true;
    _publish();
  }

  static void _publish() {
    final Set<String> connected = connectedNames.keys.toSet();
    cards.value = <SharedCard>[
      for (final MapEntry<String, List<SharedCard>> e in _byOwner.entries)
        if (connected.contains(e.key)) ...e.value,
    ];
    sentToMe.value = <SharedCard>[
      for (final MapEntry<String, List<SharedCard>> e in _sentByOwner.entries)
        if (connected.contains(e.key)) ...e.value,
    ];
    if (_byOwner.keys.toSet().containsAll(connected)) loaded.value = true;
  }

  /// How many cards [ownerUid] shares with this matchmaker.
  static int sharedBy(String ownerUid) =>
      cards.value.where((SharedCard c) => c.ownerUid == ownerUid).length;

  /// The shared card [personId] of [ownerUid], if it is in the pool now —
  /// or was sent to this matchmaker in a chat.
  static SharedCard? cardOf(String ownerUid, String personId) {
    for (final SharedCard c in cards.value) {
      if (c.ownerUid == ownerUid && c.personId == personId) return c;
    }
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

  /// Sends [person]'s card to one connected matchmaker — from a chat, even
  /// when it is not in the shared pool. View only, the same fields as a
  /// shared card; only [toUid] reads it, while the two stay connected.
  static Future<bool> sendCard({
    required Person person,
    required String toUid,
    required String myName,
  }) async {
    final String? me = _uid ?? await PersonalCardService.durableUid();
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
      if (p.toUid == _uid && p.status == IdeaProposalStatus.pending) p,
  ];

  // --- Photos --------------------------------------------------------------

  static final Map<String, Future<File?>> _photos = <String, Future<File?>>{};

  /// A photo of a shared card, fetched once through the `sharedCardPhoto`
  /// callable and kept in the app's own cache folder. Never a download URL.
  static Future<File?> photo(String ownerUid, String path) {
    return _photos.putIfAbsent(
      '$ownerUid|$path',
      () => _fetchPhoto(ownerUid, path),
    );
  }

  static Future<File?> _fetchPhoto(String ownerUid, String path) async {
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory dir = Directory('${base.path}/network_photos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final String safe = path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final File file = File('${dir.path}/$safe');
      if (await file.exists() && await file.length() > 0) return file;
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
    final String? me = _uid;
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

  /// The side asked says yes or no. A "no" opens nothing.
  static Future<bool> answer(IdeaProposal p, {required bool approve}) async {
    if (_uid != p.toUid || p.status != IdeaProposalStatus.pending) return false;
    try {
      await FirebaseFirestore.instance
          .collection('ideaProposals')
          .doc(p.id)
          .update(<String, Object?>{
            'status': approve ? 'approved' : 'declined',
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
    if (_uid != p.fromUid || p.status != IdeaProposalStatus.pending)
      return false;
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

  /// Where this side's half of an approved idea stands, for the other side.
  static Future<void> reportSide(String proposalId, String statusName) async {
    final String? me = _uid;
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
    MatchmakerNetwork.cards.value = cards;
    sentToMe.value = sent;
    MatchmakerNetwork.proposals.value = proposals;
    loaded.value = true;
  }
}
