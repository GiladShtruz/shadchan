import 'package:flutter/foundation.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/cloud_sync_service.dart';
import 'package:shadchan/services/account_remote_data_service.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';

/// Leaving one account and handing the phone to the next.
///
/// **Signing out used to cost nothing and that was the bug.** The database
/// lived in Hive and stayed there: signing out of Google disconnected a backup
/// and left every person, proposal, note and photograph exactly where they
/// were, so signing into a second account showed the second matchmaker the
/// first one's work — and then, on the next sync, uploaded it into their
/// account. With an account behind every launch, records belong to somebody,
/// and "somebody" has to be able to change.
///
/// So this is the whole of a sign-out, in the one order that cannot lose
/// anything:
///
/// 1. **Push what is here upward, and stop if that fails.** This is the last
///    moment the outgoing account's records exist on this device. A wipe that
///    ran after a failed upload would be a data loss with a confirmation dialog
///    in front of it, so a failed sync abandons the whole operation and says so
///    — see [AccountSwitchResult.syncFailed].
/// 2. **Sign out.** `AccountService.signOut` drops back to a fresh anonymous
///    session, which keeps App Check and the AI channel working for the sign-in
///    screen the matchmaker is about to land on.
/// 3. **Forget the ledger**, which describes what is in *that* account's cloud
///    tree and is wrong for any other.
/// 4. **Erase the local records** — people, proposals, notes, events, the
///    matchmaker's own profile, the board, the activity strip and everything
///    the community store remembers about them.
/// 5. **Clear the gate**, so the app is back at [SignInScreen] on this launch
///    and the next.
///
/// Nothing here touches the cloud tree. The outgoing account's backup is
/// complete and untouched, and signing back into it restores everything.
abstract final class AccountSwitch {
  static Future<AccountSwitchResult> signOutAndClear({
    required AccountProvider account,
    required SyncProvider sync,
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
    required CommunityProvider community,
  }) async {
    // Step 1. The one step that is allowed to stop the rest.
    final bool backedUp = await _finalBackup(
      sync: sync,
      people: people,
      matches: matches,
      profile: profile,
    );
    if (!backedUp) {
      return AccountSwitchResult.syncFailed;
    }

    await account.signOut();
    await _clearLocalData(
      sync: sync,
      people: people,
      matches: matches,
      profile: profile,
      community: community,
    );
    return AccountSwitchResult.done;
  }

  /// Permanently removes the account, its server data and this device's copy.
  ///
  /// Reauthentication and remote erasure happen inside [AccountService] while
  /// the account is still valid. Local data is cleared only after Firebase has
  /// confirmed that the authentication account itself is gone.
  static Future<AccountDeletionResult> deleteAccountAndClear({
    required AccountProvider account,
    required SyncProvider sync,
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
    required CommunityProvider community,
    String? password,
  }) async {
    final AccountDeletionResult result = await account.deleteAccount(
      password: password,
      deleteRemoteData: AccountRemoteDataService.deleteAll,
    );
    if (result.outcome != AccountDeletionOutcome.success) {
      return result;
    }

    await _clearLocalData(
      sync: sync,
      people: people,
      matches: matches,
      profile: profile,
      community: community,
    );
    return result;
  }

  static Future<void> _clearLocalData({
    required SyncProvider sync,
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
    required CommunityProvider community,
  }) async {
    await sync.forget();
    await people.clearAll();
    await matches.clearAll();
    await profile.clear();
    await CommunityProfileStore.reset();
    HomeBoardStore.instance.reset();
    RecentActivityStore.instance.reset();
    community.reset();
    SignInPromptStore.markSignedOut();
  }

  /// True when the outgoing account's backup is up to date.
  ///
  /// A sync that throws is treated exactly like a sync that reports failure:
  /// both mean the records on this phone may be the only copy, which is the one
  /// state in which nothing may be erased.
  static Future<bool> _finalBackup({
    required SyncProvider sync,
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
  }) async {
    try {
      final CloudSyncResult result = await sync.sync(
        personRepo: people,
        matchRepo: matches,
        profile: profile,
      );
      // `skipped` is deliberately not good enough. It means the sync did not
      // run at all — no account, no Firebase, no network — and the records on
      // this phone may be the only copy there is.
      return result == CloudSyncResult.success ||
          result == CloudSyncResult.upToDate;
    } on Object catch (error, stackTrace) {
      debugPrint('ACCOUNT final backup failed: $error\n$stackTrace');
      return false;
    }
  }
}

enum AccountSwitchResult {
  done,

  /// The last backup did not go through, so nothing was signed out and nothing
  /// was erased. The matchmaker is told to try again with a connection.
  syncFailed,
}
