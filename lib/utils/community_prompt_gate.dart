import 'package:flutter/widgets.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/enums.dart';

/// Decides whether the app has anything to say **on this launch**, and says at
/// most one of it.
///
/// **Only things that genuinely belong to a launch are still here.** A consent
/// question, a rating request, an invitation to the updates group, a published
/// "מה חדש?", and one reminder for somebody working without an account. Every
/// one of those is a thing to read or answer, which is what a dialog is for.
///
/// Milestones, the note after a large import and "מזל טוב! זוג חדש התארס" used
/// to be here too, and none of them belonged: they are not about this launch,
/// they are about something that happened. Milestones are now a toast at the
/// moment they are earned (`AchievementWatcher`), and the engagement is a card
/// on the home screen (`HomeEngagementCard`). Nothing is stored up to be
/// popped later.
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
    required CommunityMemberCounts counts,
    bool needsLeaderboardConsent = false,
    bool isSignedIn = true,
  }) {
    if (_shownThisLaunch) {
      return;
    }
    _shownThisLaunch = true;

    // Consent comes before everything, including the good news. Nothing about
    // this matchmaker is published under their name until it is answered, so
    // every launch that goes past without asking is a launch spent counting
    // somebody who was never told they were being counted.
    // Only a signed-in matchmaker is ever published, so only a signed-in
    // matchmaker has this to answer. Asking somebody who is not in the
    // community whether their name may appear in it is a question about
    // nothing.
    if (isSignedIn && needsLeaderboardConsent) {
      LeaderboardConsentDialog.show(context);
      return;
    }

    _maybeAsk(
      context,
      people: people,
      matches: matches,
      counts: counts,
      isSignedIn: isSignedIn,
    );
  }

  static void _maybeAsk(
    BuildContext context, {
    required PersonRepository people,
    required MatchRepository matches,
    required CommunityMemberCounts counts,
    required bool isSignedIn,
  }) {
    // The pacing figure for everything below is the all-time score, which is
    // the same "כל הזמנים" number the home block shows. It is handed in rather
    // than recomputed here: it costs a walk of every ledger in the app, and the
    // caller has just done it.
    final int points = counts.allTime.points;

    if (CommunityPromptsStore.shouldAskForRating(
      actions: points,
      earned: _hasEarnedRatingPrompt(people: people, matches: matches),
    )) {
      RateAppDialog.show(context, actions: points);
      return;
    }

    if (CommunityPromptsStore.shouldOfferUpdatesGroup(points)) {
      UpdatesGroupDialog.show(context, actions: points);
      return;
    }

    // Last, and only for somebody who chose to work locally. It sits at the
    // bottom of the order because it is the only prompt here that asks for
    // something the matchmaker has already declined once — everything above it
    // is either their own good news or a question they have not been asked.
    final int friends = people.databaseCount;
    if (!isSignedIn && SignInPromptStore.shouldRemind(friends)) {
      SignInReminderDialog.show(context, friends: friends);
      return;
    }

    // A signed-out device has no community to read from, and every call below
    // would be refused by `CommunityService`'s own account check anyway.
    if (!isSignedIn) {
      return;
    }
    _whenFirebaseReady(() => _maybeAnnouncement(context));
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
