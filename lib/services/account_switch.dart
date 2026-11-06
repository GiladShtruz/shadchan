import 'package:shadchan/utils/home_next_step.dart';
import 'package:shadchan/services/couple_workspace_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';

import 'package:flutter/foundation.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/services/deleted_matches_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/account_remote_data_service.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/database_hash_upload.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/home_search_filter_store.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/services/local_setting_caches.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/services/push_service.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/widgets/notification_center.dart';

/// Leaving one account and handing the phone to the next.
///
/// **The database belongs to the account, not to the phone**, so signing out
/// loses nothing: the account holds every record, and signing in again — here
/// or anywhere — brings all of it back. That is also why signing out no longer
/// waits for a backup or refuses to happen without one: there is no backup,
/// only the account, and whatever was changed offline a moment ago is already
/// in Firestore's own on-disk queue for this account, sent the next time it
/// signs in on this phone.
///
/// The order is the one thing that matters:
///
/// 1. **Hand what is waiting to Firestore**, briefly and best-effort.
/// 2. **Stop the sync, and forget its ledger.** Before anything is cleared —
///    a running sync would read the emptied boxes as the matchmaker deleting
///    their whole database, and pass that on to the account.
/// 3. **Sign out** (back to an anonymous session for App Check and the AI).
/// 4. **Clear this device**, so the next person to sign in sees their own
///    database and nobody else's.
abstract final class AccountSwitch {
  static Future<AccountSwitchResult> signOutAndClear({
    required AccountProvider account,
    required SyncProvider sync,
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
    PersonalCardProvider? personalCard,
    CardAccessProvider? cardAccess,
    InboxProvider? inbox,
    required CommunityProvider community,
  }) async {
    await _handOver(sync);
    await sync.forget();

    // While the account is still signed in, so its push list can be edited:
    // the next person on this phone must not receive this one's news.
    await PushService.stop();
    await cardAccess?.stop();
    await inbox?.stop();
    await account.signOut();
    // Once more, now that nobody is signed in: anything that started the sync
    // again in the moments above (the app coming back to the foreground) is
    // stopped before a single record is cleared.
    await sync.stop();
    await _clearLocalData(
      people: people,
      matches: matches,
      profile: profile,
      personalCard: personalCard,
      community: community,
    );
    return AccountSwitchResult.done;
  }

  /// Puts the account into its 30 days of grace and leaves it.
  ///
  /// Nothing is erased yet: the account is reauthenticated, marked for
  /// deletion and signed out, and what it shows the community is taken down
  /// so it disappears at once. Signing back in within 30 days offers to
  /// restore everything; after that `purgeDeletedAccounts` erases it for good.
  static Future<AccountDeletionResult> requestDeletionAndLeave({
    required AccountProvider account,
    required SyncProvider sync,
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
    PersonalCardProvider? personalCard,
    CardAccessProvider? cardAccess,
    InboxProvider? inbox,
    required CommunityProvider community,
    String? password,
  }) async {
    if (CoupleWorkspaceService.isCouple) {
      return const AccountDeletionResult.failure(
        AccountDeletionOutcome.dataDeletionFailed,
        'לפני מחיקת החשבון יש לפצל את המאגר הזוגי בהגדרות ← מאגר זוגי ← ניהול מתקדם.',
      );
    }

    await _handOver(sync);
    final AccountDeletionResult result = await account.deleteAccount(
      password: password,
      deleteRemoteData: () async => true,
      scheduleOnly: true,
    );
    if (result.outcome != AccountDeletionOutcome.success) {
      return result;
    }

    // Taken down now, rebuilt from the database if the account is restored:
    // the community row is republished on the next app open, and a deleted
    // personal card is restored from the personal area like any other.
    try {
      await CommunityService.deleteMyData();
    } on Object catch (error) {
      debugPrint('ACCOUNT community takedown failed: $error');
    }
    if (personalCard != null && personalCard.hasCard) {
      try {
        if (await PersonalCardSync.deleteNow()) {
          await personalCard.markDeleted();
        }
      } on Object catch (error) {
        debugPrint('ACCOUNT card takedown failed: $error');
      }
    }
    await _handOver(sync);

    await sync.forget();
    await PushService.stop();
    await cardAccess?.stop();
    await inbox?.stop();
    await account.signOut();
    // Once more, now that nobody is signed in: anything that started the sync
    // again in the moments above (the app coming back to the foreground) is
    // stopped before a single record is cleared.
    await sync.stop();
    await _clearLocalData(
      people: people,
      matches: matches,
      profile: profile,
      personalCard: personalCard,
      community: community,
    );
    return result;
  }

  /// Whatever is waiting goes into Firestore's queue — a moment, not a wait
  /// for the server. Never a reason not to continue.
  static Future<void> _handOver(SyncProvider sync) async {
    try {
      await sync.syncNow().timeout(const Duration(seconds: 4));
    } on Object catch (error) {
      debugPrint('ACCOUNT hand-over before leaving: $error');
    }
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
    PersonalCardProvider? personalCard,
    required CommunityProvider community,
    String? password,
  }) async {
    if (CoupleWorkspaceService.isCouple) {
      return const AccountDeletionResult.failure(
        AccountDeletionOutcome.dataDeletionFailed,
        'לפני מחיקת החשבון יש לפצל את המאגר הזוגי בהגדרות ← מאגר זוגי ← ניהול מתקדם.',
      );
    }

    await sync.stop();
    final AccountDeletionResult result = await account.deleteAccount(
      password: password,
      deleteRemoteData: AccountRemoteDataService.deleteAll,
    );
    if (result.outcome != AccountDeletionOutcome.success) {
      unawaited(sync.start());
      return result;
    }

    await sync.forget();
    await _clearLocalData(
      people: people,
      matches: matches,
      profile: profile,
      personalCard: personalCard,
      community: community,
    );
    return result;
  }

  static Future<void> _clearLocalData({
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
    PersonalCardProvider? personalCard,
    required CommunityProvider community,
  }) async {
    await people.clearAll();
    await matches.clearAll();
    await profile.clear();
    await personalCard?.clear();
    await WorkspaceStore.reset();
    await PersonalCardSync.forget();
    await ContactHashUpload.forget();
    await DatabaseHashUpload.forget();
    InviteLinkService.clear();
    await CommunityProfileStore.reset();
    HomeBoardStore.instance.reset();
    HomeSearchFilterStore.reset();
    ReminderLog.instance.reset();
    NotificationCenter.reset();
    NextStepStore.forget();
    RecentActivityStore.instance.reset();
    DeletedMatchesStore.instance.clear();
    community.reset();
    await clearAccountCopy();
    SignInPromptStore.markSignedOut();
  }

  /// Everything else on this device that is a copy of the account: every
  /// synced setting (tags, board notes, reminders, preferences…) and the
  /// photos and recordings the records referred to.
  ///
  /// **This is what keeps two accounts apart on one phone.** The stores above
  /// reset what they know about; a setting nobody remembered to reset would
  /// otherwise still be in the box when the next account signs in, and its
  /// first read — which sends whatever this device holds and the account
  /// lacks — would carry it into the other person's database. The account
  /// keeps all of it; signing back in brings it down again.
  ///
  /// Only ever called with the sync stopped: a running sync would read these
  /// deletions as the matchmaker's own and pass them on.
  static Future<void> clearAccountCopy() async {
    if (Hive.isBoxOpen('settings')) {
      final Box<dynamic> settings = Hive.box<dynamic>('settings');
      final List<String> synced = settings.keys
          .whereType<String>()
          .where(
            (String key) =>
                AccountSyncCodec.isSyncedSetting(key) ||
                CoupleWorkspaceService.sharedSetting(key),
          )
          .toList();
      if (synced.isNotEmpty) {
        await settings.deleteAll(synced);
      }
      // Every store's in-memory copy of a setting just removed.
      LocalSettingCaches.forgetAll();
    }
    for (final Future<Directory> Function() folder
        in <Future<Directory> Function()>[
          PhotoPickerService.ensurePhotosDirectory,
          VoiceNoteStore.directory,
        ]) {
      try {
        final Directory directory = await folder();
        if (directory.existsSync()) {
          for (final FileSystemEntity entity in directory.listSync()) {
            await entity.delete(recursive: true);
          }
        }
      } on Object catch (error) {
        debugPrint('ACCOUNT local files not cleared: $error');
      }
    }
  }
}

enum AccountSwitchResult { done }
