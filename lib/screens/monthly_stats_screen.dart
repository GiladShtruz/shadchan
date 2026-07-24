import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';

/// "הנתונים שלך החודש" — a calm dashboard of what happened this Hebrew month
/// (since Rosh Chodesh) together with a running comparison to previous months.
///
/// Counts are read straight from the records rather than kept as running
/// totals, so they reset on their own every Rosh Chodesh.
class MonthlyStatsScreen extends StatelessWidget {
  const MonthlyStatsScreen({super.key});

  /// How many Hebrew months back the comparison trend reaches.
  static const int _monthsBack = 6;

  // The calm pastel accents that carry each metric across cards and chart.
  static const Color _amber = Color(0xFFE0A33C);
  static const Color _blue = Color(0xFF5E86A6);
  static const Color _green = Color(0xFF6FA07E);
  static const Color _pink = Color(0xFFCF87A9);

  @override
  Widget build(BuildContext context) {
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<MatchIdea> matches = matchRepository.getAll();
    final List<Person> people = personRepository.getAll();

    final List<_MonthPeriod> periods = _buildPeriods(
      DateTime.now(),
      _monthsBack,
    );
    final List<_MonthStats> stats = <_MonthStats>[
      for (final _MonthPeriod period in periods)
        _statsFor(period, matches, people),
    ];

    final _MonthStats current = stats.first;
    final _MonthStats? previous = stats.length > 1 ? stats[1] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('הנתונים שלך החודש'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _MonthHeader(
              monthLabel: periods.first.label,
              totalThisMonth: current.total,
            ),
            const SizedBox(height: 16),
            if (current.weddings > 0) ...<Widget>[
              _MazalTovCard(count: current.weddings),
              const SizedBox(height: 16),
            ],
            // A 2×2 grid. RTL order puts ideas top-right, people top-left,
            // couples-dating bottom-right and weddings bottom-left.
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.98,
              children: <Widget>[
                _StatCard(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'רעיונות שנפתחו',
                  value: current.ideas,
                  previous: previous?.ideas,
                  accent: _amber,
                ),
                _StatCard(
                  icon: Icons.handshake_outlined,
                  label: 'חברים שנוספו',
                  value: current.people,
                  previous: previous?.people,
                  accent: _blue,
                ),
                _StatCard(
                  icon: Icons.favorite_rounded,
                  label: 'זוגות שהתחילו לצאת',
                  value: current.dating,
                  previous: previous?.dating,
                  accent: _green,
                ),
                _StatCard(
                  icon: Icons.diamond_outlined,
                  label: 'חתונות החודש',
                  value: current.weddings,
                  previous: previous?.weddings,
                  accent: _pink,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _TrendSection(
              periods: periods.reversed.toList(),
              stats: stats.reversed.toList(),
            ),
            const SizedBox(height: 20),
            const _DidYouKnowCard(),
          ],
        ),
      ),
    );
  }

  // --- Data ---------------------------------------------------------------

  /// The last [count] Hebrew months, newest first. Each period is a Gregorian
  /// half-open range `[start, end)` running from one Rosh Chodesh to the next.
  static List<_MonthPeriod> _buildPeriods(DateTime now, int count) {
    final List<_MonthPeriod> periods = <_MonthPeriod>[];
    DateTime start = HebrewDateUtils.hebrewMonthStart(now);
    // The current month ends at the next Rosh Chodesh (a few days ahead).
    DateTime end = HebrewDateUtils.hebrewMonthStart(
      start.add(const Duration(days: 32)),
    );

    for (int i = 0; i < count; i++) {
      final ({int year, int month, int day})? hebrew = HebrewDateUtils.today(
        from: start,
      );
      periods.add(
        _MonthPeriod(
          start: start,
          end: end,
          label: hebrew == null
              ? ''
              : HebrewDateUtils.monthYearLabel(
                  year: hebrew.year,
                  month: hebrew.month,
                ),
          shortLabel: hebrew == null
              ? ''
              : HebrewDateUtils.monthName(
                  year: hebrew.year,
                  month: hebrew.month,
                ),
        ),
      );

      // Step back one Hebrew month: the day before this month's start belongs
      // to the previous month, whichever length or leap month that may be.
      end = start;
      start = HebrewDateUtils.hebrewMonthStart(
        start.subtract(const Duration(days: 1)),
      );
    }

    return periods;
  }

  static _MonthStats _statsFor(
    _MonthPeriod period,
    List<MatchIdea> matches,
    List<Person> people,
  ) {
    bool within(DateTime date) =>
        !date.isBefore(period.start) && date.isBefore(period.end);

    final int ideas = matches
        .where((MatchIdea m) => within(m.createdAt))
        .length;
    final int newPeople = people
        .where((Person p) => !p.hidden && within(p.createdAt))
        .length;
    // A couple's move into "יוצאים"/"חתונה" is not stamped separately, so the
    // proposal's last update stands in for when it happened.
    final int dating = matches
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.dating && within(m.updatedAt),
        )
        .length;
    final int weddings = matches
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.married && within(m.updatedAt),
        )
        .length;

    return _MonthStats(
      ideas: ideas,
      people: newPeople,
      dating: dating,
      weddings: weddings,
    );
  }
}

/// One Hebrew month as a Gregorian half-open range with its display labels.
class _MonthPeriod {
  const _MonthPeriod({
    required this.start,
    required this.end,
    required this.label,
    required this.shortLabel,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final String shortLabel;
}

class _MonthStats {
  const _MonthStats({
    required this.ideas,
    required this.people,
    required this.dating,
    required this.weddings,
  });

  final int ideas;
  final int people;
  final int dating;
  final int weddings;

  int get total => ideas + people + dating + weddings;
}

// --- Widgets --------------------------------------------------------------

/// A clean banner naming the current Hebrew month with a word of praise.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.monthLabel, required this.totalThisMonth});

  final String monthLabel;
  final int totalThisMonth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color blue = MonthlyStatsScreen._blue;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  monthLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  totalThisMonth == 0
                      ? 'חודש חדש, דף חדש — קדימה לעבודה!'
                      : 'כל הכבוד! כבר עשית $totalThisMonth פעולות טובות '
                            'החודש עבור החברים שלך!',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: blue.withValues(alpha: 0.14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(Icons.calendar_month_rounded, color: blue, size: 32),
                Positioned(
                  bottom: 12,
                  child: Icon(
                    Icons.favorite_rounded,
                    color: MonthlyStatsScreen._pink,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single metric card: coloured icon badge, big number and — only when the
/// month improved on the previous one — a rise chip.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.previous,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final int value;
  final int? previous;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Requirement: only surface the month-over-month comparison when there is a
    // genuine rise. Drops or "no change" show nothing at all.
    final int? prev = previous;
    final bool showRise = prev != null && value - prev > 0;
    final int delta = prev == null ? 0 : value - prev;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '$value',
            style: theme.textTheme.displaySmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          // A fixed slot keeps every card the same height whether or not a rise
          // chip is present.
          SizedBox(
            height: 26,
            child: showRise
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _RiseChip(delta: delta),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// "▲ +2 מהחודש שעבר" — shown only for a rise.
class _RiseChip extends StatelessWidget {
  const _RiseChip({required this.delta});

  final int delta;

  static const Color _riseColor = Color(0xFF2E9E5B);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _riseColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.trending_up_rounded, size: 15, color: _riseColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '+$delta מהחודש שעבר',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: _riseColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The month-over-month tracker: a small bar chart of total activity across the
/// last few Hebrew months, with the current month highlighted. No y-axis scale.
class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.periods, required this.stats});

  /// Oldest first, so the bars read right-to-left up to the current month.
  final List<_MonthPeriod> periods;
  final List<_MonthStats> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int maxTotal = stats
        .map((_MonthStats s) => s.total)
        .fold<int>(0, (int a, int b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'מעקב לאורך החודשים',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'סך כל הפעילות בכל חודש',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.show_chart_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < periods.length; i++)
                  Expanded(
                    child: _TrendBar(
                      value: stats[i].total,
                      maxValue: maxTotal,
                      label: periods[i].shortLabel,
                      isCurrent: i == periods.length - 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.value,
    required this.maxValue,
    required this.label,
    required this.isCurrent,
  });

  final int value;
  final int maxValue;
  final String label;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double factor = maxValue == 0 ? 0 : value / maxValue;

    final Color barColor = isCurrent
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: isCurrent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          // The bar area flexes to whatever height is left, so the labels above
          // and below always fit — no manual height arithmetic to overflow.
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              widthFactor: 1,
              // Keep a sliver of a bar even at zero so the axis reads as a base.
              heightFactor: factor.clamp(0.03, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
              color: isCurrent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A gentle "did you know" nudge to keep piling up ideas.
class _DidYouKnowCard extends StatelessWidget {
  const _DidYouKnowCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.emoji_objects_rounded, color: accent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'הידעת? בממוצע רק 1 מתוך 40 רעיונות יוצא לפועל! '
              'לא מתייאשים – ככל שחושבים על יותר רעיונות, כך גדל הסיכוי '
              'ליותר שידוכים.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MazalTovCard extends StatelessWidget {
  const _MazalTovCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color pink = MonthlyStatsScreen._pink;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pink.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pink.withValues(alpha: 0.18),
            ),
            child: Icon(Icons.celebration_rounded, color: pink, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              count == 1
                  ? 'מזל טוב! זוג אחד הגיע לחופה החודש'
                  : 'מזל טוב! $count זוגות הגיעו לחופה החודש',
              style: theme.textTheme.titleMedium?.copyWith(
                color: pink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
