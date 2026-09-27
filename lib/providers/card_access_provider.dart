import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/services/card_sync_engine.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:uuid/uuid.dart';

/// How a matchmaker's request for a card ended.
enum CardRequestOutcome {
  sent,

  /// The server refused: the matchmaker is not saved in the owner's contacts
  /// (or is blocked, which is deliberately indistinguishable).
  notAllowed,
  failed,
}

/// Access to personal cards, from both sides, live.
///
/// As a **card owner**: who asked, who may see the card, the matchmakers among
/// the owner's contacts, and status reports waiting for an answer. As a
/// **matchmaker**: where each request stands — and, for every approved one,
/// the owner's card kept in step with the matching record in the database.
///
/// Every decision is the server's: this class only asks, and reads what the
/// rules let it read. Every action returns false on failure and changes
/// nothing locally, so the screen never shows a result that did not happen.
class CardAccessProvider extends ChangeNotifier {
  CardAccessProvider({required PersonRepository people, bool enabled = true})
    : _people = people,
      _enabled = enabled;

  final PersonRepository _people;
  final bool _enabled;

  String? _uid;
  bool _starting = false;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final Map<String, StreamSubscription<Object?>> _cardSubscriptions =
      <String, StreamSubscription<Object?>>{};

  List<CardAccess> _asOwner = <CardAccess>[];
  Map<String, CardAccess> _asMatchmaker = <String, CardAccess>{};
  List<StatusReport> _reports = <StatusReport>[];
  List<CardHelper> _helpers = <CardHelper>[];
  bool _helpersLoaded = false;
  final Set<String> _busy = <String>{};

  /// Directory answers, by phone hash. A card that exists is remembered for
  /// the session; "no card" only for [_negativeLookupFor], because a friend
  /// may write one at any moment — and a stale "no card" is exactly what
  /// offers them an invitation to write a card they already have.
  final Map<String, ({Map<String, dynamic>? entry, DateTime at})> _lookups =
      <String, ({Map<String, dynamic>? entry, DateTime at})>{};
  static const Duration _negativeLookupFor = Duration(minutes: 2);

  /// The owner's card applied one version at a time. Two snapshots of the
  /// same card arriving together must never both decide the friend is not in
  /// the database yet — that is how a duplicate record would be born.
  final Map<String, Future<void>> _applying = <String, Future<void>>{};

  /// Cards whose photos did not all download — tried again on resume, so a
  /// photo refused or cut off once is not missing until the owner next edits.
  final Set<String> _photosIncomplete = <String>{};

  bool get isConnected => _uid != null;
  String? get uid => _uid;

  // --- As the card owner ----------------------------------------------------

  List<CardAccess> get pendingRequests => _asOwner
      .where((CardAccess a) => a.status == CardAccessStatus.pending)
      .toList();

  List<CardAccess> get approved => _asOwner
      .where((CardAccess a) => a.status == CardAccessStatus.approved)
      .toList();

  List<CardAccess> get blocked => _asOwner
      .where((CardAccess a) => a.status == CardAccessStatus.blocked)
      .toList();

  /// Matchmakers among the owner's contacts who do not yet have access, and
  /// whom the owner has not blocked.
  ///
  /// A matchmaker whose request was answered "לא עכשיו" (or whose access was
  /// withdrawn) is back on this list, so access can be given later — even if
  /// the server's list was computed before they joined: their row itself is
  /// proof they are a friend who matchmakes here.
  List<CardHelper> get helpers {
    final Set<String> decided = <String>{
      for (final CardAccess a in _asOwner)
        if (a.status == CardAccessStatus.approved ||
            a.status == CardAccessStatus.blocked ||
            a.status == CardAccessStatus.pending)
          a.matchmakerUid,
    };
    final List<CardHelper> list = _helpers
        .where((CardHelper h) => !decided.contains(h.uid))
        .toList();
    final Set<String> listed = <String>{for (final CardHelper h in list) h.uid};
    for (final CardAccess a in _asOwner) {
      if ((a.status == CardAccessStatus.declined ||
              a.status == CardAccessStatus.revoked) &&
          !listed.contains(a.matchmakerUid)) {
        listed.add(a.matchmakerUid);
        list.add(CardHelper(uid: a.matchmakerUid, name: a.matchmakerName));
      }
    }
    return list;
  }

  /// How the owner knows [matchmakerUid]: the name saved in the owner's own
  /// contacts when the server matched them there, else [fallback] — the
  /// name the matchmaker signed up with.
  String nameInContacts(String matchmakerUid, String fallback) {
    for (final CardHelper h in _helpers) {
      if (h.uid == matchmakerUid) {
        return ContactHashUpload.nameFor(h.phoneHash) ??
            (fallback.trim().isEmpty ? h.name : fallback);
      }
    }
    return fallback;
  }

  bool get helpersLoaded => _helpersLoaded;

  List<StatusReport> get statusReports => _reports;

  // --- As a matchmaker ------------------------------------------------------

  /// This matchmaker's standing with [ownerUid]'s card, if any.
  CardAccess? accessTo(String ownerUid) => _asMatchmaker[ownerUid];

  bool isBusy(String key) => _busy.contains(key);

  // --- Lifecycle ------------------------------------------------------------

  /// Connects if it can — waiting for Firebase first — and says whether it
  /// is connected. For a screen about to ask the server a question: without
  /// a connection every friend would read as "no card".
  Future<bool> ensureConnected() async {
    if (!_enabled) {
      return false;
    }
    if (_uid != null) {
      return true;
    }
    await FirebaseBootstrap.ensureReady();
    await start();
    return _uid != null;
  }

  /// Connects, once Firebase is up and a durable account is signed in.
  Future<void> start() async {
    if (!_enabled || _uid != null || _starting || !FirebaseBootstrap.isReady) {
      return;
    }
    _starting = true;
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) {
        return;
      }
      _uid = uid;
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final CollectionReference<Map<String, dynamic>> access = db.collection(
        PersonalCardService.accessCollection,
      );

      _subscriptions
        ..add(
          access.where('ownerUid', isEqualTo: uid).snapshots().listen((
            QuerySnapshot<Map<String, dynamic>> snap,
          ) {
            _asOwner = <CardAccess>[
              for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                  in snap.docs)
                ?CardAccess.fromMap(doc.data()),
            ];
            notifyListeners();
          }, onError: _log),
        )
        ..add(
          access
              .where('matchmakerUid', isEqualTo: uid)
              .snapshots(includeMetadataChanges: true)
              .listen((QuerySnapshot<Map<String, dynamic>> snap) {
                _asMatchmaker = <String, CardAccess>{
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                      in snap.docs)
                    if (CardAccess.fromMap(doc.data()) case final CardAccess a)
                      a.ownerUid: a,
                };
                notifyListeners();
                unawaited(
                  _reconcile(authoritative: !snap.metadata.isFromCache),
                );
              }, onError: _log),
        )
        ..add(
          db
              .collection('statusReports')
              .where('ownerUid', isEqualTo: uid)
              .where('resolution', isNull: true)
              .snapshots()
              .listen((QuerySnapshot<Map<String, dynamic>> snap) {
                _reports = <StatusReport>[
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                      in snap.docs)
                    StatusReport(
                      id: doc.id,
                      ownerUid: uid,
                      matchmakerUid:
                          (doc.data()['matchmakerUid'] as String?) ?? '',
                      matchmakerName:
                          (doc.data()['matchmakerName'] as String?) ?? '',
                      status: (doc.data()['status'] as String?) ?? '',
                    ),
                ];
                notifyListeners();
              }, onError: _log),
        )
        ..add(
          db
              .collection('users')
              .doc(uid)
              .collection('private')
              .doc('helpers')
              .snapshots()
              .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
                final Object? list = snap.data()?['helpers'];
                _helpers = <CardHelper>[
                  if (list is List)
                    for (final Object? item in list)
                      if (item is Map &&
                          item['uid'] is String &&
                          item['uid'] != uid)
                        CardHelper(
                          uid: item['uid'] as String,
                          name: (item['name'] as String?) ?? '',
                          phoneHash: item['phoneHash'] as String?,
                        ),
                ];
                _helpersLoaded = snap.exists;
                notifyListeners();
              }, onError: _log),
        );
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _starting = false;
    }
  }

  /// Disconnects and forgets, for a sign-out.
  Future<void> stop() async {
    for (final StreamSubscription<Object?> s in _subscriptions) {
      await s.cancel();
    }
    for (final StreamSubscription<Object?> s in _cardSubscriptions.values) {
      await s.cancel();
    }
    _subscriptions.clear();
    _cardSubscriptions.clear();
    _uid = null;
    _asOwner = <CardAccess>[];
    _asMatchmaker = <String, CardAccess>{};
    _reports = <StatusReport>[];
    _helpers = <CardHelper>[];
    _helpersLoaded = false;
    _lookups.clear();
    _applying.clear();
    _photosIncomplete.clear();
    notifyListeners();
  }

  static void _log(Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'CardAccessProvider: $error${stackTrace == null ? '' : '\n$stackTrace'}',
    );
  }

  // --- The matchmaker's side: keeping approved cards in step ----------------

  Future<void> _reconcile({required bool authoritative}) async {
    // Follow every approved card.
    for (final CardAccess access in _asMatchmaker.values) {
      if (access.status == CardAccessStatus.approved &&
          !_cardSubscriptions.containsKey(access.ownerUid)) {
        _followCard(access);
      }
    }
    // Stop following — and unlink — what is no longer approved. Only on an
    // answer from the server: a cached, empty first snapshot must never be
    // mistaken for "every grant was withdrawn".
    if (!authoritative) {
      return;
    }
    for (final String ownerUid in _cardSubscriptions.keys.toList()) {
      if (_asMatchmaker[ownerUid]?.status != CardAccessStatus.approved) {
        await _cardSubscriptions.remove(ownerUid)?.cancel();
        await _unlink(ownerUid);
      }
    }
    for (final Person person in _people.getAll()) {
      final String? owner = person.cardOwnerUid;
      if (owner != null &&
          _asMatchmaker[owner]?.status != CardAccessStatus.approved) {
        await _unlink(owner);
      }
    }
  }

  void _followCard(CardAccess access) {
    final String ownerUid = access.ownerUid;
    _cardSubscriptions[ownerUid] = FirebaseFirestore.instance
        .collection(PersonalCardService.cardsCollection)
        .doc(ownerUid)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snap) {
            final Map<String, dynamic>? data = snap.data();
            if (data == null) {
              return;
            }
            unawaited(_applySerially(access, data));
          },
          onError: (Object error) {
            // A card that was deleted, or access that ended, reads as
            // permission-denied. Either way the sync is over.
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              unawaited(_cardSubscriptions.remove(ownerUid)?.cancel());
              unawaited(_unlink(ownerUid));
            } else {
              _log(error);
            }
          },
        );
  }

  Future<List<String>> _downloadPhotos(
    String ownerUid,
    List<Object?> remotePaths,
  ) async {
    final List<String> local = <String>[];
    for (final Object? remote in remotePaths) {
      if (remote is! String) {
        continue;
      }
      final String name = CardSyncEngine.photoFileName(
        ownerUid,
        remote.split('/').last,
      );
      final File file = await PhotoPickerService.fileFor(name);
      if (!file.existsSync()) {
        try {
          await FirebaseStorage.instance.ref(remote).writeToFile(file);
        } catch (error) {
          _log(error);
          continue;
        }
      }
      local.add(file.path);
    }
    return local;
  }

  static const String _baselinePrefix = 'cardSyncRemote.';

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// What the owner last sent for the friend [personId] — the baseline the
  /// next version is compared with, field by field.
  Map<String, Object?>? _baselineFor(String personId) {
    final Object? raw = _settings?.get('$_baselinePrefix$personId');
    if (raw is! String) {
      return null;
    }
    try {
      final Object? json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  void _setBaseline(String personId, Map<String, Object?>? baseline) {
    final Box<dynamic>? settings = _settings;
    if (settings == null) {
      return;
    }
    if (baseline == null) {
      unawaited(settings.delete('$_baselinePrefix$personId'));
    } else {
      unawaited(
        settings.put('$_baselinePrefix$personId', jsonEncode(baseline)),
      );
    }
  }

  Future<void> _applySerially(CardAccess access, Map<String, dynamic> data) {
    return _serially(access.ownerUid, () => _applyCard(access, data));
  }

  /// Runs [work] after whatever is already queued for [ownerUid] — applying a
  /// version of the card, or ending the link — so an update that was still
  /// downloading photos when access was withdrawn can never land after the
  /// unlink and tie the friend to the card again.
  Future<void> _serially(String ownerUid, Future<void> Function() work) {
    final Future<void> previous = _applying[ownerUid] ?? Future<void>.value();
    final Future<void> next = previous.then((_) => work()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _log(error, stackTrace);
    });
    _applying[ownerUid] = next;
    return next;
  }

  Future<void> _applyCard(CardAccess access, Map<String, dynamic> data) async {
    final String ownerUid = access.ownerUid;
    // Queued before access ended: the card is no longer ours to apply.
    if (_asMatchmaker[ownerUid]?.status != CardAccessStatus.approved) {
      return;
    }
    Person? person = CardSyncEngine.findExisting(
      _people.getAll(),
      ownerUid: ownerUid,
      ownerPhoneHash:
          access.ownerPhoneHash ?? PhoneIdentity.hash(access.ownerPhone),
      firstName: (data['firstName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
    );
    final bool created = person == null;
    final DateTime now = DateTime.now();
    person ??= Person(
      id: const Uuid().v4(),
      firstName: (data['firstName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
      gender: Gender.unknown,
      phone: access.ownerPhone,
      source: 'כרטיס אישי',
      createdAt: now,
      updatedAt: now,
    );
    // The owner's own number goes on the record — it is what opens WhatsApp
    // with them, and what a later import from the contacts recognises them
    // by. A number the matchmaker saved is theirs and stays.
    if ((person.phone ?? '').trim().isEmpty && access.ownerPhone != null) {
      person.phone = access.ownerPhone;
    }

    final bool wasLinked = person.cardOwnerUid == ownerUid;
    if (!wasLinked) {
      // Access is the matchmaker's friend arriving in the database: a record
      // that was kept out of it — a name on an idea, or a draft — joins it.
      //
      // **And it is a friend added, for the activity points.** A brand-new
      // record already is (it is born now); a hidden one was born when its
      // name was first typed, outside the database, and never counted. Dating
      // it from today is what makes `ActivityStats.countedFriends` give the
      // same one point a hand-added friend earns. A friend who was already
      // visible in the database was counted when they were added and earns
      // nothing twice.
      if (person.hidden && !created) {
        person.createdAt = now;
      }
      person
        ..hidden = false
        ..needsReview = false;
    }
    final List<String> oldCardPhotos = person.photosPaths
        .where(CardSyncEngine.isCardPhoto)
        .toList();
    final List<Object?> remotePhotos =
        (data['photoPaths'] as List?) ?? const <Object?>[];
    // What the owner sent last time: only what they changed since is written
    // over the matchmaker's copy. See [CardSyncEngine.apply].
    final Map<String, Object?>? previous = wasLinked
        ? _baselineFor(person.id)
        : null;
    final bool legacyDetached = person.cardSyncDetached && previous == null;
    final bool photosMoved =
        previous == null ||
        jsonEncode(previous['photoPaths']) !=
            jsonEncode(remotePhotos.whereType<String>().toList()) ||
        _photosIncomplete.contains(ownerUid);
    final List<String>? localPhotos = legacyDetached || !photosMoved
        ? null
        : await _downloadPhotos(ownerUid, remotePhotos);
    if (localPhotos != null) {
      if (localPhotos.length < remotePhotos.whereType<String>().length) {
        _photosIncomplete.add(ownerUid);
      } else {
        _photosIncomplete.remove(ownerUid);
      }
    }

    final CardSyncResult result = CardSyncEngine.apply(
      person,
      data,
      ownerUid: ownerUid,
      localPhotoPaths: localPhotos,
      previousRemote: previous,
    );
    if (localPhotos != null) {
      PhotoPickerService.deletePhotoFiles(
        oldCardPhotos.where((String p) => !localPhotos.contains(p)),
      );
    }
    if (result.changed || created) {
      await _people.saveSynced(person);
    }
    _setBaseline(person.id, CardSyncEngine.baselineOf(data));
    if (!wasLinked) {
      await _people.logEvent(
        person.id,
        PersonEventType.cardSynced,
        'הכרטיס מתעדכן עכשיו {ממנו|ממנה} ישירות'.forGender(person.gender),
      );
    }
    for (final String line in result.updates) {
      await _people.logEvent(person.id, PersonEventType.cardSynced, line);
    }
    for (final String line in result.minorUpdates) {
      await _people.logEvent(person.id, PersonEventType.cardSyncedMinor, line);
    }
  }

  Future<void> _unlink(String ownerUid) {
    return _serially(ownerUid, () => _unlinkNow(ownerUid));
  }

  Future<void> _unlinkNow(String ownerUid) async {
    final Person? person = _people.findByCardOwner(ownerUid);
    if (person == null) {
      return;
    }
    final String name = person.firstName.trim();
    final List<String> toDelete = CardSyncEngine.unlink(
      person,
      lastRemote: _baselineFor(person.id),
    );
    _setBaseline(person.id, null);
    await _people.saveSynced(person);
    PhotoPickerService.deletePhotoFiles(toDelete);
    await _people.logEvent(
      person.id,
      PersonEventType.cardSynced,
      'הגישה לכרטיס של $name הסתיימה',
    );
  }

  /// Follows again any approved card whose listener ended — a card that was
  /// deleted and then restored, with its grants kept. Called on app resume.
  Future<void> resume() async {
    await _reconcile(authoritative: false);
    for (final String ownerUid in _photosIncomplete.toList()) {
      await resync(ownerUid);
    }
  }

  /// The owner restored their card and kept its grants: every approved row is
  /// written again, which wakes each matchmaker's app to read the card anew.
  Future<bool> reawakenApproved() {
    return _run('reawaken', () async {
      for (final CardAccess row in approved) {
        await _accessDoc(row.ownerUid, row.matchmakerUid).set(
          _accessData(
            ownerUid: row.ownerUid,
            matchmakerUid: row.matchmakerUid,
            status: CardAccessStatus.approved,
            requestedBy: row.requestedBy,
            ownerName: row.ownerName,
            matchmakerName: row.matchmakerName,
            ownerPhoneHash: row.ownerPhoneHash,
            ownerPhone: row.ownerPhone,
          ),
        );
      }
    });
  }

  /// The owner restored their card without its grants: everybody who had
  /// access has it no longer.
  Future<bool> revokeAllApproved() {
    return _run('revokeAll', () async {
      for (final CardAccess row in approved) {
        await _accessDoc(row.ownerUid, row.matchmakerUid).set(
          _accessData(
            ownerUid: row.ownerUid,
            matchmakerUid: row.matchmakerUid,
            status: CardAccessStatus.revoked,
            requestedBy: row.requestedBy,
            ownerName: row.ownerName,
            matchmakerName: row.matchmakerName,
            ownerPhoneHash: row.ownerPhoneHash,
            ownerPhone: row.ownerPhone,
          ),
        );
      }
    });
  }

  /// Reads the owner's card again and applies it — after the matchmaker went
  /// back to automatic updates on a record they had detached.
  Future<void> resync(String ownerUid) async {
    final CardAccess? access = _asMatchmaker[ownerUid];
    if (access == null || access.status != CardAccessStatus.approved) {
      return;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection(PersonalCardService.cardsCollection)
              .doc(ownerUid)
              .get();
      final Map<String, dynamic>? data = snap.data();
      if (data != null) {
        await _applySerially(access, data);
      }
    } catch (error) {
      _log(error);
    }
  }

  // --- Actions --------------------------------------------------------------

  Future<bool> _run(String key, Future<void> Function() action) async {
    if (_busy.contains(key) || _uid == null) {
      return false;
    }
    _busy.add(key);
    notifyListeners();
    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  DocumentReference<Map<String, dynamic>> _accessDoc(
    String ownerUid,
    String matchmakerUid,
  ) => FirebaseFirestore.instance
      .collection(PersonalCardService.accessCollection)
      .doc(PersonalCardService.accessId(ownerUid, matchmakerUid));

  Map<String, Object?> _accessData({
    required String ownerUid,
    required String matchmakerUid,
    required CardAccessStatus status,
    required String requestedBy,
    required String ownerName,
    required String matchmakerName,
    String? ownerPhoneHash,
    String? ownerPhone,
  }) => <String, Object?>{
    'ownerUid': ownerUid,
    'matchmakerUid': matchmakerUid,
    'status': status.name,
    'requestedBy': requestedBy,
    'ownerName': ownerName,
    'matchmakerName': matchmakerName,
    'ownerPhoneHash': ownerPhoneHash,
    'ownerPhone': ownerPhone,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// The owner answers or changes an existing row: approve, "not now",
  /// block, or withdraw access.
  Future<bool> setStatus(
    CardAccess access,
    CardAccessStatus status, {
    String? ownerName,
    String? ownerPhoneHash,
    String? ownerPhone,
  }) {
    return _run('access:${access.id}', () async {
      await _accessDoc(access.ownerUid, access.matchmakerUid).set(
        _accessData(
          ownerUid: access.ownerUid,
          matchmakerUid: access.matchmakerUid,
          status: status,
          requestedBy: access.requestedBy,
          ownerName: ownerName ?? access.ownerName,
          matchmakerName: access.matchmakerName,
          ownerPhoneHash: ownerPhoneHash ?? access.ownerPhoneHash,
          ownerPhone: ownerPhone ?? access.ownerPhone,
        ),
      );
    });
  }

  /// The owner gives a matchmaker access unasked — effective at once.
  Future<bool> grant(
    CardHelper helper, {
    required String ownerName,
    String? ownerPhoneHash,
    String? ownerPhone,
  }) {
    final String? uid = _uid;
    return _run('helper:${helper.uid}', () async {
      await _accessDoc(uid!, helper.uid).set(
        _accessData(
          ownerUid: uid,
          matchmakerUid: helper.uid,
          status: CardAccessStatus.approved,
          requestedBy: 'owner',
          ownerName: ownerName,
          matchmakerName: helper.name,
          ownerPhoneHash: ownerPhoneHash,
          ownerPhone: ownerPhone,
        ),
      );
    });
  }

  /// The owner lifts a block. The row goes; the matchmaker may ask again.
  Future<bool> unblock(CardAccess access) {
    return _run('access:${access.id}', () async {
      await _accessDoc(access.ownerUid, access.matchmakerUid).delete();
    });
  }

  /// Who owns [phoneHash] in the directory, remembered for the session.
  Future<Map<String, dynamic>?> lookup(String phoneHash) async {
    final ({Map<String, dynamic>? entry, DateTime at})? known =
        _lookups[phoneHash];
    if (known != null &&
        (known.entry?['hasCard'] == true ||
            DateTime.now().difference(known.at) < _negativeLookupFor)) {
      return known.entry;
    }
    final Map<String, dynamic>? entry = await PersonalCardService.lookup(
      phoneHash,
    );
    _lookups[phoneHash] = (entry: entry, at: DateTime.now());
    return entry;
  }

  /// Forgets what the directory said about [phoneHash] — a notice just said
  /// that friend wrote a card.
  void forgetLookup(String phoneHash) => _lookups.remove(phoneHash);

  /// A matchmaker asks [ownerUid] for access to their card.
  Future<CardRequestOutcome> request({
    required String ownerUid,
    required String ownerName,
    required String ownerPhoneHash,
    required String matchmakerName,
  }) async {
    final String? uid = _uid;
    final String key = 'request:$ownerUid';
    if (uid == null || _busy.contains(key)) {
      return CardRequestOutcome.failed;
    }
    _busy.add(key);
    notifyListeners();
    try {
      await _accessDoc(ownerUid, uid).set(
        _accessData(
          ownerUid: ownerUid,
          matchmakerUid: uid,
          status: CardAccessStatus.pending,
          requestedBy: 'matchmaker',
          ownerName: ownerName,
          matchmakerName: matchmakerName,
          ownerPhoneHash: ownerPhoneHash,
        ),
      );
      return CardRequestOutcome.sent;
    } on FirebaseException catch (error) {
      _log(error);
      return error.code == 'permission-denied'
          ? CardRequestOutcome.notAllowed
          : CardRequestOutcome.failed;
    } catch (error) {
      _log(error);
      return CardRequestOutcome.failed;
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// The matchmaker changed the status of somebody whose card they follow:
  /// the owner is asked whether it is true. The local status stands either
  /// way.
  Future<void> reportStatus(
    Person person,
    ProfileStatus status, {
    required String matchmakerName,
  }) async {
    final String? uid = _uid;
    final String? owner = person.cardOwnerUid;
    if (uid == null ||
        owner == null ||
        _asMatchmaker[owner]?.status != CardAccessStatus.approved) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('statusReports')
          .add(<String, Object?>{
            'ownerUid': owner,
            'matchmakerUid': uid,
            'matchmakerName': matchmakerName,
            'status': status.name,
            'resolution': null,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      _log(error);
    }
  }

  /// The owner answers a status report. Confirming makes it their status,
  /// for everybody.
  Future<bool> answerReport(
    StatusReport report, {
    required bool confirmed,
    required PersonalCardProvider cards,
  }) {
    return _run('report:${report.id}', () async {
      await FirebaseFirestore.instance
          .collection('statusReports')
          .doc(report.id)
          .update(<String, Object?>{
            'resolution': confirmed ? 'confirmed' : 'rejected',
          });
      if (confirmed) {
        for (final ProfileStatus status in ProfileStatus.values) {
          if (status.name == report.status) {
            await cards.setStatus(status);
          }
        }
      }
    });
  }
}
