import 'package:flutter/material.dart';
import 'package:shadchan/widgets/matchmaker_rank_badge.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_progress.dart';
import 'package:shadchan/utils/weekly_pace.dart';
import 'package:shadchan/widgets/home_add_hub.dart';

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
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
  static const String nextStepTitle = 'הפעולה הבאה שלך';

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

/// The compact progress line between "הפעולה הבאה שלך" and its list.
///
/// **Up to a hundred friends, building the database is the goal**: the staged
/// milestones 10 → 25 → 50 → 100 ("73/100 חברים במאגר · עוד 27 ליעד הבא").
///
/// **From a hundred, a real figure of the matchmaker's own** — the ideas they
/// opened, the friends who went out or married thanks to them — as the next
/// step ("הוסף את הרעיון הבא שלך · כבר פתחת 24 רעיונות"). The switch is made
/// once, when the database first reaches a hundred ([WeeklyPaces.unlocked]),
/// and is not undone by a clean-up that takes it back under. See
/// [HomeProgress].
class HomeWeeklyProgress extends StatelessWidget {
  const HomeWeeklyProgress({super.key});

  /// The line, read from the repositories.
  static HomeProgress progressFor({
    required PersonRepository people,
    required MatchRepository matches,
    Gender? gender,
    DateTime? now,
  }) {
    final int friends = people.databaseCount;
    if (!WeeklyPaces.unlocked(friends)) {
      return HomeProgress.milestone(friends);
    }
    final ActivityBreakdown all = ActivityStats.allTime(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    // From a hundred friends: the way to the next rank, by ideas opened.
    return HomeProgress.rank(ideas: all.ideas, gender: gender);
  }

  @override
  Widget build(BuildContext context) {
    final HomeProgress progress = progressFor(
      people: context.watch<PersonRepository>(),
      matches: context.watch<MatchRepository>(),
      gender: _maybeWatch<UserProfileProvider>(context)?.gender,
    );
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool full = progress.progress >= 1;
    final Color fill = full
        ? (dark ? AppColors.statusDatingDm : AppColors.statusDating)
        : (dark ? AppColors.secondaryDarkDm : AppColors.secondary);
    final String? sub = progress.subline;
    final int? ideas = progress.rankIdeas;
    // Clean and compact, no card of its own: the line, a thin scale, and —
    // for a rank — one small line on what is next. It reads as the head of
    // the action list under it, not as a block beside it.
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          progress.line,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress.progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, _) =>
                LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: dark
                      ? AppColors.primaryLightDarkDm
                      : AppColors.primaryLight,
                  valueColor: AlwaysStoppedAnimation<Color>(fill),
                ),
          ),
        ),
        if (sub != null) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
    return Semantics(
      label: <String>[progress.line, ?sub].join(' · '),
      excludeSemantics: true,
      button: ideas != null,
      child: ideas == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: body,
            )
          : InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => MatchmakerRankSheet.show(
                context,
                ideas: ideas,
                gender: _maybeRead<UserProfileProvider>(context)?.gender,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: body,
              ),
            ),
    );
  }
}
