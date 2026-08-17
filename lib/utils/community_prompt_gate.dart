import 'package:flutter/widgets.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/dialogs/engagement_dialogs.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_engagements_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/community_achievements.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/enums.dart';

/// Decides whether the app has anything to say on this launch, and says at most
/// one of it.
///
/// Three things compete for the same moment — a published "מה חדש?", a rating
/// request, an invitation to the updates group — and the point of putting them
/// behind one gate is that they can never stack. A user who opens the app and
/// dismisses three dialogs in a row has been handed a beta, and this whole
/// layer is supposed to read as a finished product.
///
/// **Nothing here brings Firebase up.** The two local prompts need no network
/// and run immediately; the announcement is a Firestore read, and it waits for
/// whoever else starts Firebase this session (the cloud-sync scheduler does, a
/// frame after launch) rather than forcing a cold start of its own. On a device
/// where Firebase never comes up, the local prompts still work and the
/// announcement simply waits for a launch where it does.
abstract final class CommunityPromptGate {
  /// The app opens once per process; the prompts belong to the launch, not to
  /// the widget, so the guard outlives any rebuild of the home screen.
  static bool _shownThisLaunch = false;

  @visibleForTesting
  static void resetForTest() => _shownThisLaunch = false;

  /// Milestones that earn the right to ask for a rating. Each is a moment the
  /// app has visibly worked, which is the only moment worth asking in.
  static const int ratingIdeasMilestone = 10;
  static const int ratingFriendsMilestone = 25;

  static void maybeShow(
    BuildContext context, {
    required PersonRepository people,
    required MatchRepository matches,
    required int actions,
    bool newWeeklyRecord = false,
    int weeklyRecord = 0,
    bool needsLeaderboardConsent = false,
  }) {
    if (_shownThisLaunch) {
      return;
    }
    _shownThisLaunch = true;

    // Consent comes before everything, including the good news. Nothing about
    // this matchmaker is published under their name until it is answered, so
    // every launch that goes past without asking is a launch spent counting
    // somebody who was never told they were being counted.
    if (needsLeaderboardConsent) {
      LeaderboardConsentDialog.show(context);
      return;
    }

    // A large import that was never acknowledged — because the app was closed
    // between the save and the celebration — is said here instead of an
    // achievement, and not beside one. It goes ahead of the milestones on
    // purpose: it describes what the matchmaker actually did, and the round
    // numbers it crossed are the less interesting half of the same event.
    _showBulkImportNoteThen(context, () {
      _maybeAchievement(
        context,
        people: people,
        matches: matches,
        actions: actions,
        newWeeklyRecord: newWeeklyRecord,
        weeklyRecord: weeklyRecord,
      );
    });
  }

  /// Shows the pending import note if there is one; otherwise runs [next].
  static Future<void> _showBulkImportNoteThen(
    BuildContext context,
    VoidCallback next,
  ) async {
    if (await BulkImportNoteDialog.maybeShow(context)) {
      return;
    }
    if (context.mounted) {
      next();
    }
  }

  static void _maybeAchievement(
    BuildContext context, {
    required PersonRepository people,
    required MatchRepository matches,
    required int actions,
    required bool newWeeklyRecord,
    required int weeklyRecord,
  }) {
    // A milestone the matchmaker reached goes first. It is the only one of the
    // four that is *about them* — the other three are the app asking for
    // something or announcing something — and it is the only one that is gone
    // for good once shown.
    final Achievement? achievement = CommunityAchievements.firstUnseen(
      friends: people.databaseCount,
      ideas: matches.getAll().length,
      actions: actions,
      couples: CommunityCounts.build(
        people: people.getAll(),
        matches: matches.getAll(),
        matchStatusEvents: matches.getAllStatusEvents(),
        events: people.getAllEvents(),
      ).couples,
      newWeeklyRecord: newWeeklyRecord,
      weeklyRecord: weeklyRecord,
      seen: CommunityProfileStore.seenAchievements,
    );
    if (achievement != null) {
      AchievementDialog.show(context, achievement);
      return;
    }

    if (CommunityPromptsStore.shouldAskForRating(
      actions: actions,
      earned: _hasEarnedRatingPrompt(people: people, matches: matches),
    )) {
      RateAppDialog.show(context, actions: actions);
      return;
    }

    if (CommunityPromptsStore.shouldOfferUpdatesGroup(actions)) {
      UpdatesGroupDialog.show(context, actions: actions);
      return;
    }

    _whenFirebaseReady(() => _maybeFromTheNetwork(context));
  }

  /// Runs [action] as soon as Firebase is up — now, if it already is.
  ///
  /// A listener rather than `ensureReady()` on purpose. `ensureReady` starts a
  /// 30-second deadline timer that never resolves inside a widget test's
  /// fake-async zone, and this runs on every launch of the landing screen, so it
  /// would fail every test that so much as opens the app. Waiting instead costs
  /// nothing and is the honest description of what this needs: not Firebase
  /// started, just Firebase available.
  static void _whenFirebaseReady(VoidCallback action) {
    if (FirebaseBootstrap.isReady) {
      action();
      return;
    }
    void listener() {
      if (!FirebaseBootstrap.isReady) {
        return;
      }
      FirebaseBootstrap.readyListenable.removeListener(listener);
      action();
    }

    FirebaseBootstrap.readyListenable.addListener(listener);
  }

  /// The two things that need the network, still at most one of them.
  ///
  /// A new couple goes ahead of a published note. One is somebody's good news
  /// and the other is the app talking about itself, and if only one of them can
  /// be said this launch it should not be the app.
  static Future<void> _maybeFromTheNetwork(BuildContext context) async {
    final CommunityEngagement? engagement =
        await CommunityEngagementsService.latestUnseen(
          seenId: CommunityPromptsStore.seenEngagementId,
        );
    if (engagement != null) {
      if (context.mounted) {
        await MazelTovDialog.show(context, engagement);
      }
      return;
    }
    if (context.mounted) {
      await _maybeAnnouncement(context);
    }
  }

  /// Shows the newest published note if this device has not seen it.
  static Future<void> _maybeAnnouncement(BuildContext context) async {
    final Announcement? note = await SupportService.fetchLatestAnnouncement();
    if (note == null ||
        note.id == CommunityPromptsStore.seenAnnouncementId ||
        !context.mounted) {
      return;
    }
    await WhatsNewDialog.show(context, note);
  }

  /// Whether something good has happened yet: a first couple who started
  /// dating, ten ideas opened, or twenty-five friends added.
  ///
  /// The dating test looks at every status *at or past* dating rather than at
  /// `dating` alone — a couple who married two months ago earned this just as
  /// much as one who started last week, and a status that has moved on should
  /// not take the milestone back.
  static bool _hasEarnedRatingPrompt({
    required PersonRepository people,
    required MatchRepository matches,
  }) {
    if (people.databaseCount >= ratingFriendsMilestone) {
      return true;
    }
    final List<MatchIdea> all = matches.getAll();
    if (all.length >= ratingIdeasMilestone) {
      return true;
    }
    return all.any(
      (MatchIdea match) =>
          match.status == MatchStatus.dating ||
          match.status == MatchStatus.dated ||
          match.status == MatchStatus.married,
    );
  }
}
