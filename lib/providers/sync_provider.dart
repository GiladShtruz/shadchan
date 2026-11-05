import 'dart:convert';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadchan/services/couple_workspace_service.dart';
import 'package:shadchan/services/couple_sync_remote.dart';
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/account_health_service.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_engine.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/account_sync_remote.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/migration_snapshot.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/voice_note_store.dart';

/// The account's database, as the rest of the app sees it.
///
/// Owns the [AccountSyncEngine] for whoever is signed in: started when a
/// durable account appears, stopped when it goes. Screens only ever ask it two
/// things — has this device read its account yet, and is anything wrong — and
/// the sign-out and deletion flows ask it to stop before the local copy is
/// cleared.
class SyncProvider extends ChangeNotifier {
  /// [enabled] is false only in tests: a widget test that pumped `App` would
  /// otherwise reach `FirebaseBootstrap.ensureReady`, which never completes
  /// inside `testWidgets`' fake-async zone. See the twin seam on
  /// `AccountProvider`.
  SyncProvider(Box<dynamic> settings, {bool enabled = true})
    : _settings = settings,
      _enabled = enabled {
    if (_enabled) {
      FirebaseBootstrap.readyListenable.addListener(_onFirebaseReady);
      _onFirebaseReady();
    }
  }

  final Box<dynamic> _settings;
  final bool _enabled;

  /// Told what the account changed on this device, so the providers holding
  /// those records can redraw. Set once by `CloudSyncScheduler`.
  void Function(AccountSyncChanges changes)? onRemoteApplied;

  /// Given the profile document an older version wrote, the first time this
  /// device meets an account that has one and no synced profile.
  Future<void> Function(Map<String, Object?> profile)? onLegacyProfile;

  StreamSubscription<User?>? _authChanges;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _membershipChanges;
  String? _workspaceRevision;
  AccountSyncEngine? _engine;
  String? _uid;
  Future<void>? _starting;
  int _generation = 0;

  /// Whether this device has once read the whole of the account it is signed
  /// in to. Until it has, a new phone shows a loading screen rather than an
  /// empty database and a request to introduce yourself.
  bool get initialPullDone => AccountSyncLedger.initialPullDoneHere;

  bool get isRunning => _engine != null;

  /// Whether a pass is under way, for a spinner.
  bool get isSyncing => _starting != null;

  Object? get lastError => _engine?.lastError;

  /// Starts (or retries) the sync for whoever is signed in, and completes once
  /// the account has been read — or the attempt failed.
  ///
  /// Calls are queued one behind the other: the sign-in screen, the auth
  /// listener and the app's own first frame can all ask at once, and two
  /// engines on one database would each think the other's writes were news.
  Future<void> start() {
    final Future<void> next = _startChain
        .then((_) => _start())
        .catchError(
          (Object error) => debugPrint('ACCOUNT_SYNC start failed: $error'),
        );
    _startChain = next;
    return next;
  }

  Future<void> _startChain = Future<void>.value();

  Future<void> _start() async {
    if (!_enabled) {
      return;
    }
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      await stop();
      return;
    }
    _membershipChanges ??= FirebaseFirestore.instance
        .doc('memberships/${user.uid}')
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.metadata.isFromCache) {
            final next = snapshot.data();
            if (next?['state'] !=
                    CoupleWorkspaceService.membership.value?['state'] ||
                next?['revision'] !=
                    CoupleWorkspaceService.membership.value?['revision']) {
              unawaited(start());
            }
          }
        });
    final membership = await CoupleWorkspaceService.refresh();
    final revision =
        '${user.uid}:${membership?['databaseUid'] ?? user.uid}:${membership?['revision'] ?? 'personal'}';
    if (!CoupleWorkspaceService.ready) {
      await stop();
      return;
    }
    if (_uid == user.uid && _engine != null && _workspaceRevision == revision) {
      await _engine!.resume();
      return;
    }
    await stop();
    _workspaceRevision = revision;
    final Future<void> starting = _startFor(user.uid);
    _starting = starting;
    notifyListeners();
    try {
      await starting;
    } finally {
      if (identical(_starting, starting)) {
        _starting = null;
      }
      notifyListeners();
    }
  }

  Future<void> _startFor(String uid) async {
    // A stop that arrives while this is still getting ready — a sign-out a
    // second after signing in — must win: an engine created after it would
    // read the cleared boxes as the matchmaker deleting everything.
    final int generation = _generation;
    final Box<dynamic> box = Hive.isBoxOpen(AccountSyncLedger.boxName)
        ? Hive.box<dynamic>(AccountSyncLedger.boxName)
        : await Hive.openBox<dynamic>(AccountSyncLedger.boxName);
    final AccountSyncLedger ledger = AccountSyncLedger(box);
    final String? previous = ledger.uid;
    final binding = CoupleWorkspaceService.isCouple
        ? '$uid@${CoupleWorkspaceService.databaseUid}:${CoupleWorkspaceService.membership.value?['revision']}'
        : uid;
    if (previous != null &&
        previous != binding &&
        previous.split('@').first == uid) {
      await _preservePendingEdits(ledger, previous, uid);
    }
    if (await ledger.bindTo(binding)) {
      if (previous != null && previous != binding) {
        // This device was last in step with a different account and was not
        // cleared on the way out. Its records belong to that account (whose
        // copy is in the cloud), and must not be merged into this one.
        await _clearSyncedBoxes();
      }
      await _adoptOldBackupLedger(ledger, uid);
    }

    final Directory photos = await PhotoPickerService.ensurePhotosDirectory();
    final Directory voice = await VoiceNoteStore.directory();
    if (generation != _generation) {
      return;
    }
    final Map<SyncCollection, Box<dynamic>> boxes =
        <SyncCollection, Box<dynamic>>{
          for (final SyncCollection collection in SyncCollection.values)
            if (Hive.isBoxOpen(collection.box))
              collection: Hive.box<dynamic>(collection.box),
        };
    await _beginMigration(ledger, uid, boxes);
    if (generation != _generation) {
      return;
    }
    final AccountSyncEngine engine = AccountSyncEngine(
      ledger: ledger,
      remote: CoupleWorkspaceService.databaseUid == null
          ? FirestoreAccountSyncRemote(uid)
          : CoupleSyncRemote(uid, CoupleWorkspaceService.databaseUid!),
      boxes: boxes,
      photosDirectory: photos.path,
      voiceDirectory: voice.path,
      onRemoteApplied: (AccountSyncChanges changes) {
        onRemoteApplied?.call(changes);
        notifyListeners();
      },
      onLegacyProfile: (Map<String, Object?> profile) async =>
          onLegacyProfile?.call(profile),
    );
    _engine = engine;
    _uid = uid;
    _ledger = ledger;
    _boxes = boxes;
    await engine.start();
    unawaited(_afterPull(engine, ledger, uid));
    await _membershipChanges?.cancel();
    _membershipChanges = FirebaseFirestore.instance
        .doc('memberships/$uid')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.metadata.isFromCache) return;
          final data = snapshot.data();
          final next =
              '$uid:${data?['databaseUid'] ?? uid}:${data?['revision'] ?? 'personal'}';
          if (next != _workspaceRevision ||
              (data != null && data['state'] != 'active')) {
            unawaited(start());
          }
        });
  }

  // --- Migration, verification and the account's health --------------------

  AccountSyncLedger? _ledger;
  Map<SyncCollection, Box<dynamic>> _boxes = <SyncCollection, Box<dynamic>>{};
  bool _verifying = false;

  /// The first time this device meets [uid]'s account, whatever the device
  /// already holds is about to be merged into it. A copy is put aside first.
  Future<void> _beginMigration(
    AccountSyncLedger ledger,
    String uid,
    Map<SyncCollection, Box<dynamic>> boxes,
  ) async {
    await MigrationSnapshot.expire();
    if (ledger.initialPullDone || ledger.migration['startedAt'] != null) {
      return;
    }
    final bool hasRecords = MigrationSnapshot.hasRecords(boxes);
    final bool snapshot =
        hasRecords && await MigrationSnapshot.take(uid, boxes) != null;
    await ledger.setMigration(<String, Object?>{
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'hadLocalData': hasRecords,
      'snapshot': snapshot,
    });
    await ledger.addLog(
      hasRecords
          ? 'migration started, snapshot ${snapshot ? 'kept' : 'FAILED'}'
          : 'first read on this device, nothing local',
    );
  }

  /// Once the account has been read: count it against this device, let the
  /// snapshot go when everything is there, and tell support how it went.
  Future<void> _afterPull(
    AccountSyncEngine engine,
    AccountSyncLedger ledger,
    String uid,
  ) async {
    if (!engine.isPulled) {
      await _report(force: true);
      return;
    }
    await _verify(engine, ledger, uid);
  }

  Future<void> _verify(
    AccountSyncEngine engine,
    AccountSyncLedger ledger,
    String uid,
  ) async {
    if (_verifying) {
      return;
    }
    final bool wasVerified = ledger.migrationVerified;
    if (wasVerified) {
      await _report();
      return;
    }
    _verifying = true;
    try {
      final SyncVerification? result = await engine.verify();
      if (result != null && result.ok) {
        await MigrationSnapshot.release(uid);
      }
      if (!identical(engine, _engine)) {
        return;
      }
      await _report(force: result != null);
      notifyListeners();
    } on Object catch (error) {
      debugPrint('ACCOUNT_SYNC verification failed: $error');
    } finally {
      _verifying = false;
    }
  }

  Future<void> _report({bool force = false}) async {
    final AccountSyncLedger? ledger = _ledger;
    if (ledger == null) {
      return;
    }
    await AccountHealthService.report(
      ledger: ledger,
      counts: localCounts,
      running: _engine != null,
      lastError: _engine?.lastError,
      force: force,
    );
  }

  /// How many records this device holds, per collection.
  Map<SyncCollection, int> get localCounts => <SyncCollection, int>{
    for (final MapEntry<SyncCollection, Box<dynamic>> e in _boxes.entries)
      e.key: e.key == SyncCollection.settings
          ? e.value.keys
                .whereType<String>()
                .where(AccountSyncCodec.isSyncedSetting)
                .length
          : e.value.length,
  };

  /// Whether this device's move into the account was counted and found whole.
  bool get migrationVerified => _ledger?.migrationVerified ?? false;

  /// The last moment this device heard from or wrote to the account.
  DateTime? get lastSyncAt {
    final Map<String, Object?> stats = _ledger?.stats ?? <String, Object?>{};
    DateTime? latest;
    for (final String key in <String>[
      'lastFullReadAt',
      'lastSentAt',
      'lastReceivedAt',
    ]) {
      final Object? value = stats[key];
      final DateTime? at = value is String ? DateTime.tryParse(value) : null;
      if (at != null && (latest == null || at.isAfter(latest))) {
        latest = at;
      }
    }
    return latest?.toLocal();
  }

  /// The photo half of the old one-way backup's ledger, carried over so the
  /// photos it already uploaded are not uploaded again.
  Future<void> _adoptOldBackupLedger(
    AccountSyncLedger ledger,
    String uid,
  ) async {
    if (_settings.get('cloudSyncUid') != uid) {
      return;
    }
    final Object? old = _settings.get('cloudSyncFingerprints');
    if (old is! Map) {
      return;
    }
    for (final MapEntry<dynamic, dynamic> entry in old.entries) {
      if (entry.key is String &&
          (entry.key as String).startsWith('photos/') &&
          entry.value is String) {
        await ledger.setFile(entry.key as String, entry.value as String);
      }
    }
  }

  Future<void> _preservePendingEdits(
    AccountSyncLedger ledger,
    String binding,
    String uid,
  ) async {
    final pending = ledger.dirtyPaths.toSet();
    final rootUid = binding.contains('@')
        ? binding.split('@')[1].split(':')[0]
        : uid;
    for (final collection in SyncCollection.values.where(
      (c) => c != SyncCollection.settings,
    )) {
      try {
        final cached = await FirebaseFirestore.instance
            .collection('users/$rootUid/${collection.remote}')
            .get(const GetOptions(source: Source.cache));
        for (final doc in cached.docs.where(
          (d) => d.metadata.hasPendingWrites,
        )) {
          pending.add('${collection.remote}/${doc.id}');
        }
      } catch (_) {
        /* Hive's dirty ledger remains available without a Firestore cache. */
      }
    }
    if (pending.isEmpty) return;
    final snapshot = <String, Object?>{
      'version': 2,
      'exportDate': DateTime.now().toIso8601String(),
    };
    for (final collection in SyncCollection.values.where(
      (c) => c != SyncCollection.settings,
    )) {
      if (!Hive.isBoxOpen(collection.box)) continue;
      final box = Hive.box<dynamic>(collection.box);
      snapshot[collection.remote] = [
        for (final id in box.keys.whereType<String>())
          if (pending.contains('${collection.remote}/$id'))
            switch (collection) {
              SyncCollection.people => AccountSyncCodec.personToRemote(
                box.get(id) as Person,
              ),
              SyncCollection.personNotes => AccountSyncCodec.personNoteToRemote(
                box.get(id) as PersonNote,
              ),
              SyncCollection.personEvents =>
                AccountSyncCodec.personEventToRemote(
                  box.get(id) as PersonEvent,
                ),
              SyncCollection.matches => AccountSyncCodec.matchToRemote(
                box.get(id) as MatchIdea,
              ),
              SyncCollection.matchNotes => AccountSyncCodec.matchNoteToRemote(
                box.get(id) as MatchNote,
              ),
              SyncCollection.matchStatusEvents =>
                AccountSyncCodec.matchStatusEventToRemote(
                  box.get(id) as MatchStatusEvent,
                ),
              SyncCollection.settings => <String, Object?>{},
            },
      ];
    }
    final recovery = await Hive.openBox<dynamic>('workspace_recovery');
    await recovery.put(
      '$uid:${DateTime.now().toIso8601String()}',
      jsonEncode(snapshot),
    );
  }

  Future<void> _clearSyncedBoxes() async {
    await _settings.deleteAll(
      _settings.keys
          .whereType<String>()
          .where(CoupleWorkspaceService.sharedSetting)
          .toList(),
    );
    for (final SyncCollection collection in SyncCollection.values) {
      if (collection == SyncCollection.settings ||
          !Hive.isBoxOpen(collection.box)) {
        continue;
      }
      await Hive.box<dynamic>(collection.box).clear();
    }
  }

  /// Stops the sync and waits for whatever was in flight. Everything after
  /// this — clearing the device on sign-out above all — reaches nobody.
  Future<void> stop() async {
    _generation++;
    final AccountSyncEngine? engine = _engine;
    _engine = null;
    _uid = null;
    _ledger = null;
    _boxes = <SyncCollection, Box<dynamic>>{};
    if (engine != null) {
      await engine.stop();
      notifyListeners();
    }
  }

  /// The app came back to the foreground.
  Future<void> resume() async {
    if (_engine == null) {
      await start();
      return;
    }
    final AccountSyncEngine engine = _engine!;
    await engine.resume();
    final AccountSyncLedger? ledger = _ledger;
    final String? uid = _uid;
    if (ledger != null && uid != null && engine.isPulled) {
      unawaited(_verify(engine, ledger, uid));
    }
  }

  /// Sends whatever is waiting, now. Answers whether the sync is running at
  /// all; the writes themselves complete in the background, offline included.
  Future<bool> syncNow() async {
    if (!_enabled) {
      return false;
    }
    if (_engine == null) {
      await start();
    }
    final AccountSyncEngine? engine = _engine;
    if (engine == null) {
      return false;
    }
    await engine.flush();
    return engine.isPulled;
  }

  void _onFirebaseReady() {
    if (!FirebaseBootstrap.isReady || _authChanges != null) {
      return;
    }
    _authChanges = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) {
      if (user == null) {
        // Mid-transition; the settled signed-out state is anonymous.
        return;
      }
      if (user.isAnonymous) {
        unawaited(stop());
      } else if (user.uid != _uid) {
        unawaited(start());
      }
    });
  }

  /// Stops and drops this device's ledger. Called on sign-out, before the
  /// local copy is cleared.
  Future<void> forget() async {
    await _membershipChanges?.cancel();
    _membershipChanges = null;
    CoupleWorkspaceService.clear();
    await stop();
    await AccountSyncLedger.maybeInstance?.clear();
    await _settings.deleteAll(<String>[
      'cloudSyncFingerprints',
      'cloudSyncLastSyncedAt',
      'cloudSyncUid',
    ]);
    notifyListeners();
  }

  @override
  void dispose() {
    FirebaseBootstrap.readyListenable.removeListener(_onFirebaseReady);
    _authChanges?.cancel();
    _membershipChanges?.cancel();
    unawaited(_engine?.stop());
    super.dispose();
  }
}
