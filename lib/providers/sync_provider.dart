import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/cloud_sync_service.dart';
import 'package:shadchan/services/sync_state_store.dart';

/// The cloud backup, as the rest of the app sees it.
///
/// Holds only what a screen has to be able to draw — whether a sync is
/// running, when the last one finished, and how the last one ended — and
/// forwards everything else to [CloudSyncService].
class SyncProvider extends ChangeNotifier {
  /// [enabled] is false only in tests. `CloudSyncScheduler` fires a sync from
  /// the app's own builder, so every widget test that pumps `App` would reach
  /// `FirebaseBootstrap.ensureReady` — which never completes inside
  /// `testWidgets`' fake-async zone and fails the test with a pending timer.
  /// Disabled, every call answers [CloudSyncResult.skipped] without touching
  /// Firebase, which is what an unconnected app does anyway. See the twin
  /// seam on `AccountProvider`.
  SyncProvider(Box<dynamic> settings, {bool enabled = true})
    : _state = SyncStateStore(settings),
      _enabled = enabled;

  final SyncStateStore _state;
  final bool _enabled;

  bool _isSyncing = false;
  bool _isRestoring = false;
  bool _isDeleting = false;
  CloudSyncResult? _lastResult;

  bool get isSyncing => _isSyncing;

  bool get isRestoring => _isRestoring;

  /// Whether an erasure is in flight, so the tile can disable itself rather
  /// than let a second tap start a second pass over the same tree.
  bool get isDeleting => _isDeleting;

  /// When the last successful sync committed, or null if there has never been
  /// one on this device under this account.
  DateTime? get lastSyncedAt => _state.lastSyncedAt;

  /// How the last attempt ended, or null before the first one.
  CloudSyncResult? get lastResult => _lastResult;

  /// Runs a backup. Safe to call from anywhere at any time: it never throws,
  /// and overlapping calls share the one pass [CloudSyncService] is running.
  Future<CloudSyncResult> sync({
    required PersonRepository personRepo,
    required MatchRepository matchRepo,
    required UserProfileProvider profile,
  }) async {
    if (_isSyncing || !_enabled) {
      return CloudSyncResult.skipped;
    }
    _isSyncing = true;
    notifyListeners();
    try {
      final CloudSyncResult result = await CloudSyncService.syncNow(
        personRepo: personRepo,
        matchRepo: matchRepo,
        profile: profile,
        state: _state,
      );
      _lastResult = result;
      return result;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<CloudRestoreOutcome> restore({
    required PersonRepository personRepo,
    required MatchRepository matchRepo,
    required UserProfileProvider profile,
  }) async {
    if (_isRestoring || !_enabled) {
      return const CloudRestoreOutcome.failure(CloudSyncResult.skipped);
    }
    _isRestoring = true;
    notifyListeners();
    try {
      final CloudRestoreOutcome outcome = await CloudSyncService.restore(
        personRepo: personRepo,
        matchRepo: matchRepo,
        profile: profile,
      );
      // Everything that just landed locally is already in the cloud, but the
      // ledger does not know that — it was written on the *other* device. It
      // is cleared so the next sync rebuilds it from what is actually here,
      // which is one full upload and no wrong answers.
      if (outcome.status == CloudSyncResult.success) {
        await _state.clear();
      }
      _lastResult = outcome.status;
      return outcome;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Erases the cloud backup — every record, the profile and every photo —
  /// leaving the database on this phone untouched.
  ///
  /// The ledger is cleared whatever the outcome. It is a record of what is
  /// believed to be in the cloud, and after this it is wrong either way: on
  /// success nothing is up there any more, and on a partial failure it no
  /// longer describes what survived. Clearing it costs one full re-upload if
  /// the matchmaker stays signed in, and prevents the far worse alternative —
  /// a ledger that says a deleted record is still backed up, so the next sync
  /// never sends it and the backup silently has a hole in it.
  Future<bool> deleteBackup() async {
    if (_isDeleting || !_enabled) {
      return false;
    }
    _isDeleting = true;
    notifyListeners();
    try {
      final bool deleted = await CloudSyncService.deleteBackup();
      await _state.clear();
      _lastResult = null;
      return deleted;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  /// Drops the ledger. Called on sign-out: the next account has its own
  /// Firestore tree, and a ledger describing someone else's is worse than none.
  Future<void> forget() async {
    await _state.clear();
    _lastResult = null;
    notifyListeners();
  }
}
