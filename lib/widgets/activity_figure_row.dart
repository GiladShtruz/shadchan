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
    this.compact = false,
  });

  final PersonRepository people;
  final MatchRepository matches;
  final EdgeInsetsGeometry padding;

  /// The home screen's version: the same four squares, smaller and closer
  /// together, so the row costs little height at the head of the page.
  final bool compact;

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
          compact: compact,
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
            // Reading order in RTL: friends at the start (the right).
            tile(
              all.friends,
              'חברים',
              MonthlyStatMetric.people,
              AppColors.metric(MetricKind.friends, dark: dark),
            ),
            SizedBox(width: compact ? 6 : 8),
            tile(
              all.ideas,
              'רעיונות',
              MonthlyStatMetric.ideas,
              AppColors.metric(MetricKind.ideas, dark: dark),
            ),
            SizedBox(width: compact ? 6 : 8),
            tile(
              all.couples,
              'זוגות שיצאו',
              MonthlyStatMetric.dating,
              AppColors.metric(MetricKind.couples, dark: dark),
            ),
            SizedBox(width: compact ? 6 : 8),
            tile(
              all.engagements,
              'חתונות',
              MonthlyStatMetric.weddings,
              AppColors.metric(MetricKind.weddings, dark: dark),
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
/// **A colour per metric, from the palette and nowhere else** — the deep blue
/// for friends, copper for ideas, the light blue for the couples who went out
/// and the rose for a wedding. The four rules are the one place the row wears colour;
/// the figures themselves are the page's ink, like every other heading on it,
/// so the row reads as four counts about one database rather than as four
/// competing badges.
class _FigureTile extends StatelessWidget {
  const _FigureTile({
    required this.value,
    required this.label,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final int value;
  final String label;
  final bool compact;

  /// The rule under this figure. See [AppColors.metricFriends] and friends.
  final Color accent;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(compact ? 12 : 14),
      elevation: compact ? 1 : 2,
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
                padding: compact
                    ? const EdgeInsets.fromLTRB(4, 6, 4, 5)
                    : const EdgeInsets.fromLTRB(4, 9, 4, 8),
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
                          fontSize: compact
                              ? HomeTypography.lead - 2
                              : HomeTypography.lead,
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

/// The same four all-time figures as [ActivityFigureRow], said as one quiet
/// line: "611 חברים · 213 רעיונות · 8 זוגות יצאו · 2 חתונות".
///
/// **For the home screen, where the figures must not compete with what to do
/// next.** Four tiles at the head of the page were the loudest thing on it;
/// the numbers are still here, each still a tap into its list, but they read
/// as a caption under the greeting rather than as a dashboard. The activity
/// screen keeps the tiles.
class ActivityFigureLine extends StatelessWidget {
  const ActivityFigureLine({
    super.key,
    required this.people,
    required this.matches,
  });

  final PersonRepository people;
  final MatchRepository matches;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final ActivityBreakdown all = ActivityStats.allTime(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    final TextStyle? figure = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w900,
    );
    final TextStyle? noun = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.muted(dark: dark),
      fontWeight: FontWeight.w600,
    );

    Widget part(int value, String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: CommunityFigure.format(value), style: figure),
                TextSpan(text: ' $label', style: noun),
              ],
            ),
            maxLines: 1,
          ),
        ),
      );
    }

    Widget dot() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text('·', style: noun),
    );

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            part(all.friends, 'חברים', () => context.go('/people')),
            dot(),
            part(all.ideas, 'רעיונות', () => context.go('/matches')),
            dot(),
            part(
              all.couples,
              'זוגות יצאו',
              () => context.push(
                '/stats/month/${MonthlyStatMetric.dating.name}?window=all',
              ),
            ),
            dot(),
            part(
              all.engagements,
              'חתונות',
              () => context.push(
                '/stats/month/${MonthlyStatMetric.weddings.name}?window=all',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
