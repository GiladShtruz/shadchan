import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/couple_workspace_service.dart';

/// Where a couple's half-finished connection stands, as this phone sees it.
enum CoupleRecoveryState {
  /// Nothing to recover.
  idle,

  /// Asking the server to finish the merge.
  resuming,

  /// The merge finished; the shared database is loading.
  completed,

  /// The merge could not finish and was undone: both accounts are back on
  /// their own databases.
  rolledBack,

  /// The last attempt failed (no connection, the merge still running on the
  /// server); another is scheduled.
  failed,
}

/// **A couple's connection is never left half-way.** The merge runs for
/// minutes on the server, and a phone can lose its connection, be closed, or
/// the function itself be stopped at its time limit in the middle of it —
/// leaving both accounts "merging", every edit refused, with nobody to finish
/// it.
///
/// Whenever the sync finds this account's membership still `merging`, this
/// asks the server to finish it (`resumeCoupleMigration`). The server either
/// completes it, or — when it cannot, or has failed too often — undoes it from
/// the archives it took before writing anything, and both accounts go back to
/// their own databases. Nothing is created, reset or emptied on the phone
/// meanwhile. Tried once at a time, again after a pause when it failed, and
/// every step goes into the account's sync log for support.
abstract final class CoupleRecovery {
  static final ValueNotifier<CoupleRecoveryState> state =
      ValueNotifier<CoupleRecoveryState>(CoupleRecoveryState.idle);

  /// The last failure, as a code for the screen and for support.
  static String? lastCode;

  static Future<void>? _running;
  static DateTime? _notBefore;

  /// The server's own lease on a merge lasts ten minutes; a resume refused
  /// because one is still running is tried again after a few.
  static const Duration busyPause = Duration(minutes: 3);
  static const Duration failurePause = Duration(minutes: 2);

  /// Called with the membership the sync just read.
  static Future<void> check(
    Map<String, dynamic>? membership, {
    bool force = false,
  }) {
    final Object? phase = membership?['state'];
    if (phase != 'merging' && phase != 'splitting') {
      if (state.value == CoupleRecoveryState.resuming) {
        state.value = CoupleRecoveryState.idle;
      }
      return Future<void>.value();
    }
    final Future<void>? running = _running;
    if (running != null) return running;
    final DateTime? notBefore = _notBefore;
    if (!force && notBefore != null && DateTime.now().isBefore(notBefore)) {
      return Future<void>.value();
    }
    final Future<void> next =
        (phase == 'splitting'
                ? _finishSplit('${membership?['operation'] ?? ''}')
                : _resume('${membership?['operation'] ?? ''}'))
            .whenComplete(() => _running = null);
    _running = next;
    return next;
  }

  static Future<void> _resume(String operation) async {
    state.value = CoupleRecoveryState.resuming;
    await log('recovery: resuming ${_short(operation)}');
    try {
      final Map<String, dynamic> result = await CoupleWorkspaceService.call(
        'resumeCoupleMigration',
      );
      _notBefore = null;
      lastCode = null;
      if (result['rolledBack'] == true) {
        state.value = CoupleRecoveryState.rolledBack;
        await log('recovery: rolled back, both on their own databases');
      } else {
        state.value = CoupleRecoveryState.completed;
        await log('recovery: completed');
      }
    } on FirebaseFunctionsException catch (error) {
      lastCode = 'functions/${error.code}';
      final Object? details = error.details;
      if (details is Map && details['rolledBack'] == true) {
        _notBefore = null;
        state.value = CoupleRecoveryState.rolledBack;
        await log(
          'recovery: merge failed at ${details['failedAt']}, rolled back',
        );
      } else if (error.code == 'failed-precondition') {
        // Nothing to finish any more (the other phone did it).
        _notBefore = null;
        state.value = CoupleRecoveryState.idle;
        await log('recovery: nothing to resume');
      } else {
        _notBefore = DateTime.now().add(
          error.code == 'aborted' ? busyPause : failurePause,
        );
        state.value = CoupleRecoveryState.failed;
        await log('recovery: failed $lastCode, will retry');
      }
    } on Object catch (error) {
      lastCode = error.runtimeType.toString();
      _notBefore = DateTime.now().add(failurePause);
      state.value = CoupleRecoveryState.failed;
      await log('recovery: failed $lastCode, will retry');
    }
    try {
      await CoupleWorkspaceService.refresh();
    } on Object {
      // The sync's own membership listener picks the change up anyway.
    }
  }

  /// A split both spouses' phones wait on: one of them already confirmed it,
  /// so it is finished — the server resumes from its own archive.
  static Future<void> _finishSplit(String operation) async {
    state.value = CoupleRecoveryState.resuming;
    await log('recovery: finishing split ${_short(operation)}');
    try {
      await CoupleWorkspaceService.call('splitCoupleWorkspace', {
        'confirmed': true,
      });
      _notBefore = null;
      lastCode = null;
      state.value = CoupleRecoveryState.completed;
      await log('recovery: split completed');
    } on FirebaseFunctionsException catch (error) {
      lastCode = 'functions/${error.code}';
      _notBefore = DateTime.now().add(
        error.code == 'aborted' ? busyPause : failurePause,
      );
      state.value = CoupleRecoveryState.failed;
      await log('recovery: split failed $lastCode, will retry');
    } on Object catch (error) {
      lastCode = error.runtimeType.toString();
      _notBefore = DateTime.now().add(failurePause);
      state.value = CoupleRecoveryState.failed;
      await log('recovery: split failed $lastCode, will retry');
    }
    try {
      await CoupleWorkspaceService.refresh();
    } on Object {
      // The sync's membership listener follows anyway.
    }
  }

  /// "ביטול החיבור": undo a connection that has not finished. True when both
  /// accounts are back on their own databases.
  static Future<bool> rollback() async {
    await log('rollback requested');
    try {
      await CoupleWorkspaceService.call('rollbackCoupleMigration');
      state.value = CoupleRecoveryState.rolledBack;
      lastCode = null;
      await log('rollback done');
      await CoupleWorkspaceService.refresh();
      return true;
    } on FirebaseFunctionsException catch (error) {
      lastCode = 'functions/${error.code}';
      await log('rollback failed $lastCode');
      return false;
    } on Object catch (error) {
      lastCode = error.runtimeType.toString();
      await log('rollback failed $lastCode');
      return false;
    }
  }

  /// One line in the account's sync log (sent with its health report).
  static Future<void> log(String event) async {
    debugPrint('COUPLE $event');
    try {
      await AccountSyncLedger.maybeInstance?.addLog('couple $event');
    } on Object {
      // The log is a help, never a reason to fail.
    }
  }

  static String _short(String id) => id.length > 6 ? id.substring(0, 6) : id;

  /// Forgotten on sign-out, with the membership.
  static void forget() => reset();

  @visibleForTesting
  static void reset() {
    _running = null;
    _notBefore = null;
    lastCode = null;
    state.value = CoupleRecoveryState.idle;
  }
}
