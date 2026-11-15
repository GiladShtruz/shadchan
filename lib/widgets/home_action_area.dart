import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/weekly_pace.dart';
import 'package:shadchan/widgets/home_add_hub.dart';

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// "הוספת חברים" | "הוספת רעיון" — the home page's two main buttons.
///
/// **No title over them any more.** "מה עושים עכשיו?" was one more line
/// between the figures and the buttons; the buttons say what they do. What is
/// worth doing next is the list under them, headed [nextStepTitle].
///
/// On the home page the row is pinned ([pinnedSliver]): the figures above it
/// scroll away, the search bar and these two buttons stay at the top.
class HomeActionArea extends StatelessWidget {
  const HomeActionArea({super.key});

  /// The heading over the list of what to do next, under the two buttons.
  static const String nextStepTitle = 'מה השלב הבא שלך?';

  /// The space above and below the row inside its pinned band.
  static const double _bandPadding = 8;

  /// The two buttons as a pinned sliver, [inset] from the page's edges.
  static Widget pinnedSliver(BuildContext context, {required double inset}) {
    final double height =
        HomeAddHub.heightFor(MediaQuery.textScalerOf(context)) +
        _bandPadding * 2;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedActionsDelegate(height: height, inset: inset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Gender? gender = _maybeWatch<UserProfileProvider>(context)?.gender;
    return HomeAddHub(
      gender: gender,
      onAddPeople: () => AddPeopleDialog.show(context),
      onAddIdea: () => context.push('/matches/add'),
    );
  }
}

class _PinnedActionsDelegate extends SliverPersistentHeaderDelegate {
  _PinnedActionsDelegate({required this.height, required this.inset});

  final double height;
  final double inset;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final ThemeData theme = Theme.of(context);
    // The page's own ground, so what scrolls under the band is hidden; and
    // a hairline under it once something does, so the band reads as the top
    // of the page rather than as one more row.
    final bool covering = overlapsContent || shrinkOffset > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: covering
            ? Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: inset,
          vertical: HomeActionArea._bandPadding,
        ),
        child: const HomeActionArea(),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedActionsDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.inset != inset;
}

/// The heading over the list of what to do next.
class HomeNextStepTitle extends StatelessWidget {
  const HomeNextStepTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      HomeActionArea.nextStepTitle,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

/// The small progress line under the two add actions.
///
/// **Up to a hundred friends, building the database is the goal**: the same
/// staged milestones as always — 10 → 25 → 50 → 100 — with how many are in
/// and how many are missing to the next one ([HomeMilestone], unchanged).
///
/// **From a hundred, the matchmaker races themselves.** One metric a week,
/// picked from what they actually do, and a target one past last week or
/// past their best week ([WeeklyPaces]). The switch is made once, when the
/// database first reaches a hundred, and is not undone by a clean-up that
/// takes it back under.
class HomeWeeklyProgress extends StatelessWidget {
  const HomeWeeklyProgress({super.key});

  /// This week's personal pace, read from the repositories.
  static WeeklyPace paceFor({
    required PersonRepository people,
    required MatchRepository matches,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final DateTime weekStart =
        CommunityPeriods.startOf(CommunityPeriod.week, at) ??
        DateTime(at.year, at.month, at.day);
    final Map<PaceMetric, List<int>> history = WeeklyPaces.history(
      weekStart: weekStart,
      now: at,
      people: people.getAll(),
      matches: matches.getAll(),
      statusEvents: matches.getAllStatusEvents(),
      notes: matches.getAllNotes(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    return WeeklyPaces.choose(
      history: history,
      weekNumber: WeeklyPaces.weekNumber(weekStart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PersonRepository people = context.watch<PersonRepository>();
    final MatchRepository matches = context.watch<MatchRepository>();
    final int friends = people.databaseCount;
    if (!WeeklyPaces.unlocked(friends)) {
      return MilestoneProgressLine(milestone: HomeMilestone.forCount(friends));
    }
    return PersonalPaceLine(
      pace: paceFor(people: people, matches: matches),
      gender: _maybeWatch<UserProfileProvider>(context)?.gender,
    );
  }
}

/// "בשבוע שעבר הוספת 4 חברים. השבוע שוברים את השיא?" over a small bar and
/// "2/5". Not a game: no flashing, no score, nothing that blocks anything —
/// and once the target is reached it says so once and keeps counting.
class PersonalPaceLine extends StatelessWidget {
  const PersonalPaceLine({super.key, required this.pace, this.gender});

  final WeeklyPace pace;
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final String headline = pace.headline(gender);
    return _ProgressLine(
      icon: Icons.emoji_events_outlined,
      headline: headline,
      progress: pace.progress,
      figure: '${pace.done}/${pace.target}',
      reached: pace.reached,
      semantics: '$headline ${pace.done} מתוך ${pace.target}',
    );
  }
}

/// The milestone line for a database under a hundred: "34 מתוך 50 חברים" and
/// the existing sentence about how many are still missing.
class MilestoneProgressLine extends StatelessWidget {
  const MilestoneProgressLine({super.key, required this.milestone});

  final HomeMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final int? target = milestone.target;
    return _ProgressLine(
      icon: Icons.flag_outlined,
      headline: milestone.message,
      progress: milestone.progress,
      figure: target == null
          ? '${milestone.friends}'
          : '${milestone.friends}/$target',
      reached: milestone.isReached,
      semantics: target == null
          ? milestone.message
          : '${milestone.friends} מתוך $target חברים. ${milestone.message}',
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.icon,
    required this.headline,
    required this.progress,
    required this.figure,
    required this.reached,
    required this.semantics,
  });

  final IconData icon;
  final String headline;
  final double progress;
  final String figure;
  final bool reached;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color copper = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    final Color fill = reached
        ? (dark ? AppColors.statusDatingDm : AppColors.statusDating)
        : copper;

    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: copper.withValues(alpha: dark ? 0.18 : 0.12),
            ),
            child: Icon(icon, size: 20, color: copper),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (BuildContext context, double value, _) =>
                              LinearProgressIndicator(
                                value: value,
                                minHeight: 6,
                                backgroundColor: dark
                                    ? AppColors.primaryLightDarkDm
                                    : AppColors.primaryLight,
                                valueColor: AlwaysStoppedAnimation<Color>(fill),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      figure,
                      // The figure is a fraction; it reads left to right.
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
