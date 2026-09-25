import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "חברים", "רעיונות", "זוגות שיצאו", "חתונות" — all time, in a row of four
/// at the head of the section.
///
/// Counted by [ActivityStats.allTime], exactly as "הנתונים שלך" counts them,
/// and each opens the same all-time list that screen opens.
///
/// **One word each, and no picture.** They read "חברים שהוספת" and "רעיונות
/// שפתחת" once, which is a sentence about the matchmaker where a label was
/// wanted — and it was long enough to wrap, which is what made four short wide
/// tiles into four tall boxes. A figure over a noun is the whole of it; the
/// icon over each one was a third thing to look at in a tile the width of a
/// thumb.
class ActivityFigureRow extends StatelessWidget {
  const ActivityFigureRow({
    super.key,
    required this.people,
    required this.matches,
    this.padding = EdgeInsets.zero,
  });

  final PersonRepository people;
  final MatchRepository matches;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ActivityBreakdown all = ActivityStats.allTime(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    Widget tile(int value, String label, MonthlyStatMetric m, Color accent) {
      return Expanded(
        child: _FigureTile(
          value: value,
          label: label,
          accent: accent,
          // Friends and ideas are a tab each: the figure is a shortcut to the
          // list itself. The other two open the records behind them.
          onTap: switch (m) {
            MonthlyStatMetric.people => () => context.go('/people'),
            MonthlyStatMetric.ideas => () => context.go('/matches'),
            _ => () => context.push('/stats/month/${m.name}?window=all'),
          },
        ),
      );
    }

    return Padding(
      padding: padding,
      // Equal heights whichever label is the longest.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            tile(
              all.friends,
              'חברים',
              MonthlyStatMetric.people,
              dark ? AppColors.metricFriendsDm : AppColors.metricFriends,
            ),
            const SizedBox(width: 8),
            tile(
              all.ideas,
              'רעיונות',
              MonthlyStatMetric.ideas,
              dark ? AppColors.metricIdeasDm : AppColors.metricIdeas,
            ),
            const SizedBox(width: 8),
            tile(
              all.couples,
              'זוגות שיצאו',
              MonthlyStatMetric.dating,
              dark ? AppColors.metricCouplesDm : AppColors.metricCouples,
            ),
            const SizedBox(width: 8),
            tile(
              all.engagements,
              'חתונות',
              MonthlyStatMetric.weddings,
              dark ? AppColors.metricWeddingsDm : AppColors.metricWeddings,
            ),
          ],
        ),
      ),
    );
  }
}

/// One figure: the number, the noun under it, and the page's one rule along
/// the foot.
///
/// **A colour per metric, from the palette and nowhere else** — blue for
/// friends, copper for ideas, rose for the couples who went out, the palest
/// blue for a wedding. The four rules are the one place the row wears colour;
/// the figures themselves are the page's ink, like every other heading on it,
/// so the row reads as four counts about one database rather than as four
/// competing badges.
class _FigureTile extends StatelessWidget {
  const _FigureTile({
    required this.value,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final int value;
  final String label;

  /// The rule under this figure. See [AppColors.metricFriends] and friends.
  final Color accent;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: AppColors.onSurface.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      // The rule is flush to the bottom edge; this clip is what rounds it.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // The four tiles are stretched to one height by an `IntrinsicHeight`
        // above, so this column has to fill that height rather than sit at the
        // top of it — otherwise a tile whose label had to shrink ends up with
        // its rule floating a few pixels above the card's own foot, and the
        // four rules no longer line up.
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 9, 4, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        CommunityFigure.format(value),
                        maxLines: 1,
                        // The one figure on the page drawn larger than the
                        // type scale: it is the thing being read, and at the
                        // page's title size four of them in a row disappear
                        // into the nouns under them.
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: HomeTypography.lead,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AccentUnderline(color: accent),
          ],
        ),
      ),
    );
  }
}
