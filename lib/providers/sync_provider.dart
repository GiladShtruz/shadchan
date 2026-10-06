import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_engine.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/account_sync_remote.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
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
    if (_uid == user.uid && _engine != null) {
      await _engine!.resume();
      return;
    }
    await stop();
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
    if (await ledger.bindTo(uid)) {
      if (previous != null && previous != uid) {
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
    final AccountSyncEngine engine = AccountSyncEngine(
      ledger: ledger,
      remote: FirestoreAccountSyncRemote(uid),
      boxes: <SyncCollection, Box<dynamic>>{
        for (final SyncCollection collection in SyncCollection.values)
          if (Hive.isBoxOpen(collection.box))
            collection: Hive.box<dynamic>(collection.box),
      },
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
    await engine.start();
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

  Future<void> _clearSyncedBoxes() async {
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
    await _engine!.resume();
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
    unawaited(_engine?.stop());
    super.dispose();
  }
}
