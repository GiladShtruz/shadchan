import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/sync_quiet.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_achievements.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/widgets/app_celebration.dart';
import 'package:shadchan/widgets/app_toast.dart';
import 'package:shadchan/widgets/points_reward.dart';

/// Congratulates the matchmaker **when the thing happens**, and never again
/// afterwards.
///
/// Milestones used to be checked once per launch, which put them a whole
/// session late: somebody added their fiftieth friend on Tuesday afternoon and
/// was told about it on Wednesday morning, in a dialog, with no memory of what
/// they had done to earn it. Worse, anything crossed and not shown was *kept*,
/// so an import could leave three of them stacked up for the next three
/// launches.
///
/// This watches the two repositories instead. Every write notifies, so the
/// moment a record lands the milestone it crossed can be said — as a toast,
/// while the matchmaker is still looking at the screen they did it on.
///
/// **The baseline is the part that is easy to get wrong.** An existing install
/// has already passed most of the ladder; noticing that for the first time and
/// announcing it would greet the update with a congratulation for something
/// that happened months ago. So the first run ever writes down everything
/// already reached and says nothing — see
/// [CommunityProfileStore.hasBaselinedAchievements] — and it runs in
/// `initState`, before any change can arrive, so it can never swallow the
/// achievement belonging to the action that woke it up.
class AchievementWatcher extends StatefulWidget {
  const AchievementWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<AchievementWatcher> createState() => _AchievementWatcherState();
}

class _AchievementWatcherState extends State<AchievementWatcher> {
  /// A single edit notifies several times — the record, then the status event,
  /// then whatever the repository does next — and an import notifies once per
  /// person. One pass at the end of the burst is both cheaper and more correct:
  /// it is the *finished* state that crossed a milestone.
  static const Duration _settleAfter = Duration(milliseconds: 700);

  Timer? _debounce;
  PersonRepository? _people;
  MatchRepository? _matches;

  /// The all-time breakdown at the last check — what "+N" is measured from.
  /// In memory only: a launch starts from what is already there, so nothing
  /// done before it is ever "rewarded" again.
  ActivityBreakdown? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final PersonRepository people = context.read<PersonRepository>();
    final MatchRepository matches = context.read<MatchRepository>();
    if (identical(people, _people) && identical(matches, _matches)) {
      return;
    }

    _people?.removeListener(_onChanged);
    _matches?.removeListener(_onChanged);
    _people = people..addListener(_onChanged);
    _matches = matches..addListener(_onChanged);

    if (!CommunityProfileStore.hasBaselinedAchievements) {
      _baseline();
    }
    _last = _reached().breakdown;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _people?.removeListener(_onChanged);
    _matches?.removeListener(_onChanged);
    super.dispose();
  }

  /// Whether the burst being settled carried a change that arrived by sync —
  /// the account catching up after a reconnect, a friend's card following
  /// itself in. Such a burst moves the baseline and says nothing.
  bool _burstFromSync = false;

  void _onChanged() {
    if (SyncQuiet.active) {
      _burstFromSync = true;
    }
    _debounce?.cancel();
    _debounce = Timer(_settleAfter, _check);
  }

  /// Everything already earned, marked as told, silently — once ever.
  void _baseline() {
    _baselineQuietly();
    CommunityProfileStore.markAchievementsBaselined();
  }

  void _check() {
    if (!mounted || !CommunityProfileStore.hasBaselinedAchievements) {
      return;
    }
    final _Reached reached = _reached();
    final ActivityBreakdown? before = _last;
    _last = reached.breakdown;
    if (_burstFromSync) {
      // Nothing was just done here: no "+1", no milestone, no toast. What the
      // sync brought is counted from now on like everything else.
      _burstFromSync = false;
      _baselineQuietly();
      return;
    }

    // A large import says one thing about the import, and the milestones it
    // crossed are marked as told rather than queued behind it. Being handed
    // "הוספת 300 חברים", then "הגעת ל־200 חברים", then "הגעת ל־250 נקודות" is
    // being told the same good news three times in decreasing order of
    // interest.
    final int imported = CommunityProfileStore.pendingBulkImport;
    if (imported >= CommunityProfileStore.bulkImportNoticeFrom) {
      CommunityProfileStore.clearPendingBulkImport();
      _baselineQuietly();
      _toast(CommunityAchievements.bulkImportMessage(imported), '🙌');
      return;
    }

    final Achievement? achievement = _firstUnseen(reached);
    if (achievement == null) {
      if (before != null) {
        _reward(before, reached.breakdown);
      }
      return;
    }
    // Only the most significant one. `firstUnseen` already ranks them, and
    // marking just this one seen leaves the rest for the days they are the best
    // thing that happened — which is the whole point of not queueing.
    CommunityProfileStore.markSeen(achievement.id);
    _toast(achievement.title, '🎉');
  }

  /// The router's navigator overlay: this widget sits above the navigator,
  /// so the overlay notices draw in is not among its ancestors.
  OverlayState? get _overlay =>
      AppRouter.router.routerDelegate.navigatorKey.currentState?.overlay ??
      Overlay.maybeOf(context, rootOverlay: true);

  void _toast(String message, String emoji) {
    final OverlayState? overlay = _overlay;
    if (overlay != null) {
      AppToast.showIn(overlay, message, emoji: emoji);
    }
  }

  /// "+N" for what was just done — only when nothing larger is already saying
  /// it (a milestone, a batch celebration), and only for growth: a deletion
  /// moves the baseline and says nothing.
  void _reward(ActivityBreakdown before, ActivityBreakdown after) {
    final int points = after.points - before.points;
    if (points <= 0 || AppCelebration.isShowing) {
      return;
    }
    final OverlayState? overlay = _overlay;
    if (overlay == null) {
      return;
    }
    int grew(int a, int b) => b > a ? b - a : 0;
    PointsReward.show(
      overlay,
      points: points,
      label: PointsReward.labelFor(
        friends: grew(before.friends, after.friends),
        ideas: grew(before.ideas, after.ideas),
        couples: grew(before.couples, after.couples),
        engagements: grew(before.engagements, after.engagements),
      ),
    );
  }

  /// Marks everything currently reached as told without saying any of it.
  ///
  /// The loop re-reads the seen set each time round, which is what makes it
  /// terminate: `firstUnseen` returns the next one down the ranking until there
  /// is nothing left unseen.
  void _baselineQuietly() {
    for (
      Achievement? achievement = _firstUnseen(_reached());
      achievement != null;
      achievement = _firstUnseen(_reached())
    ) {
      CommunityProfileStore.markSeen(achievement.id);
    }
  }

  Achievement? _firstUnseen(_Reached reached) {
    return CommunityAchievements.firstUnseen(
      friends: reached.friends,
      ideas: reached.ideas,
      points: reached.points,
      couples: reached.couples,
      seen: CommunityProfileStore.seenAchievements,
    );
  }

  _Reached _reached() {
    final PersonRepository people = _people!;
    final MatchRepository matches = _matches!;
    final CommunityMemberCounts counts = CommunityCounts.build(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    return _Reached(
      friends: people.databaseCount,
      ideas: matches.getAll().length,
      points: counts.allTime.points,
      couples: counts.allTime.couples,
      breakdown: counts.allTime,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Reached {
  const _Reached({
    required this.friends,
    required this.ideas,
    required this.points,
    required this.couples,
    required this.breakdown,
  });

  final int friends;
  final int ideas;
  final int points;
  final int couples;
  final ActivityBreakdown breakdown;
}
