import 'package:shadchan/screens/people_screen.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/deleted_matches_store.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/home_search_filter_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/services/tag_library.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/card_updates_seen.dart';
import 'package:shadchan/utils/home_board_feed.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/utils/think_rotation.dart';
import 'package:shadchan/widgets/first_visit_tip.dart';

/// The stores that keep a setting in memory, made to read it again.
///
/// Most of them answer from a value held since it was last written — that is
/// what lets a write land on disk a microtask later without the screen
/// flickering. It also means a value that arrived from the account (a board
/// pinned on the other phone, a dismissed suggestion, a reminder seen) would
/// stay invisible here until the app restarted. Called whenever the account
/// changes the `settings` box.
abstract final class LocalSettingCaches {
  static void forgetAll() {
    WorkspaceStore.forgetCache();
    TagLibrary.forgetCache();
    NewIdeaRotation.forgetCache();
    HomeSearchFilterStore.forgetCache();
    CardUpdatesSeen.forgetCache();
    ThinkRotation.forgetCache();
    ThinkLater.forgetCache();
    BoardAllCategories.forgetCache();
    BoardSeen.forgetCache();
    FirstVisitTips.forgetCache();
    CommunityPromptsStore.forgetCache();
    CommunityProfileStore.forgetCache();
    PeopleSortDefault.forgetCache();
    PeopleViewChoice.forgetCache();
    HomeBoardStore.instance.forgetCache();
    ReminderLog.instance.forgetCache();
    RecentActivityStore.instance.forgetCache();
    DeletedMatchesStore.instance.forgetCache();
  }
}
