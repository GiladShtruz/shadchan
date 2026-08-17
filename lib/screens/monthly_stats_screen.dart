import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/monthly_stats.dart';

/// "הפעילות שלך" — what this matchmaker has actually done, month by month.
///
/// One chart, not two. The screen used to carry an actions-per-month chart and
/// a "מעקב לאורך החודשים" chart directly under it; they counted slightly
/// different things but drew the same six bars over the same six months, which
/// read as the same chart printed twice. What is left is the one chart that
/// answers the question, and it is now the screen's control as well as its
/// picture: tapping a month moves every number above it to that month, so the
/// figures and the bars can never disagree about which month is being read.
class MonthlyStatsScreen extends StatefulWidget {
  const MonthlyStatsScreen({super.key});

  /// How many Hebrew months back the chart reaches.
  static const int _monthsBack = 6;

  // The two calm pastels this screen draws with outside the metric cards —
  // the per-metric accents themselves live on [MonthlyStatMetric.color].
  static const Color _blue = MonthlyStats.peopleColor;
  static const Color _pink = MonthlyStats.weddingsColor;

  @override
  State<MonthlyStatsScreen> createState() => _MonthlyStatsScreenState();
}

class _MonthlyStatsScreenState extends State<MonthlyStatsScreen> {
  /// Index into the newest-first list of periods. 0 is the current month.
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<MatchIdea> matches = matchRepository.getAll();
    final List<Person> people = personRepository.getAll();

    final List<MatchStatusEvent> matchStatusEvents = matchRepository
        .getAllStatusEvents();
    final List<PersonEvent> events = personRepository.getAllEvents();
    final Set<String> excludedFromDating = DatingCountExclusions.all();

    final List<MonthPeriod> periods = MonthlyStats.buildPeriods(
      DateTime.now(),
      MonthlyStatsScreen._monthsBack,
    );
    final int selected = _selected.clamp(0, periods.length - 1);
    final List<MonthStats> stats = <MonthStats>[
      for (final MonthPeriod period in periods)
        MonthlyStats.statsFor(
          period,
          matches,
          people,
          statusEvents: matchStatusEvents,
          excludedFromDating: excludedFromDating,
        ),
    ];

    final MonthStats shown = MonthlyStats.withAllTimeTotals(
      stats[selected],
      matches,
      matchStatusEvents,
      excludedFromDating: excludedFromDating,
    );
    // The comparison is always against the month before the one on screen, so
    // stepping back through the chart keeps saying something true.
    final MonthStats? previous = selected + 1 < stats.length
        ? stats[selected + 1]
        : null;

    final List<ActivityBucket> bars = ActivityStats.monthlyBars(
      periods: periods,
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      events: events,
    );
    final int actionsInMonth = ActivityStats.countBetween(
      start: periods[selected].start,
      end: periods[selected].end,
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      events: events,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('הפעילות שלך'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _MonthHeader(
              monthLabel: periods[selected].label,
              actions: actionsInMonth,
              isCurrentMonth: selected == 0,
            ),
            const SizedBox(height: 16),
            if (stats[selected].weddings > 0) ...<Widget>[
              _MazalTovCard(count: stats[selected].weddings),
              const SizedBox(height: 16),
            ],
            // A 2×2 grid. RTL order puts ideas top-right, people top-left,
            // couples-dating bottom-right and weddings bottom-left.
            //
            // The aspect ratio leaves room for a third label line: "זוגות
            // שהתחילו לצאת" does not fit two at this width, and a cut label is
            // worse than a slightly taller card.
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.86,
              children: <Widget>[
                for (final MonthlyStatMetric metric in MonthlyStatMetric.values)
                  _StatCard(
                    metric: metric,
                    value: metric.valueOf(shown),
                    previous: metric.isAllTime || previous == null
                        ? null
                        : metric.valueOf(previous),
                    onTap: () => context.push('/stats/month/${metric.name}'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _ActivityChart(
              bars: bars,
              // The bars run oldest-first, the periods newest-first.
              selectedBar: bars.length - 1 - selected,
              onSelect: (int barIndex) =>
                  setState(() => _selected = bars.length - 1 - barIndex),
            ),
            const SizedBox(height: 20),
            const _DidYouKnowCard(),
          ],
        ),
      ),
    );
  }
}

// --- Widgets --------------------------------------------------------------

/// The activity chart: one bar per Hebrew month, counted in actions, and the
/// control that chooses which month the whole screen is about.
///
/// This is the one place in the app where a chart earns its keep — it is the
/// screen someone opened *to see numbers*. Even here it stays a plain bar per
/// month with no axes or gridlines, and the word underneath is generous by
/// design: the point is to notice a good month, never to grade a bad one.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({
    required this.bars,
    required this.selectedBar,
    required this.onSelect,
  });

  final List<ActivityBucket> bars;
  final int selectedBar;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color blue = MonthlyStatsScreen._blue;
    final int peak = bars.fold<int>(
      0,
      (int max, ActivityBucket bucket) =>
          bucket.count > max ? bucket.count : max,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'פעולות לפי חודשים',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: blue.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        ActivityStats.grade(
                          selectedBar >= 0 && selectedBar < bars.length
                              ? bars[selectedBar].count
                              : 0,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: blue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // What counts, said plainly. A note is deliberately absent from
                // this list — writing something down is thinking, not doing.
                Text(
                  'נספרות הוספת חבר, פתיחת רעיון ועדכון סטטוס של חבר/רעיון. '
                  'לחיצה על חודש תציג את הנתונים שלו למעלה.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < bars.length; i++)
                  Expanded(
                    child: _Bar(
                      bucket: bars[i],
                      peak: peak,
                      selected: i == selectedBar,
                      onTap: () => onSelect(i),
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

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bucket,
    required this.peak,
    required this.selected,
    required this.onTap,
  });

  final ActivityBucket bucket;
  final int peak;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color blue = MonthlyStatsScreen._blue;
    final double factor = peak == 0 ? 0 : bucket.count / peak;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Column(
          children: <Widget>[
            Text(
              '${bucket.count}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
                color: selected ? blue : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            // The bar area flexes to whatever height is left, so the labels
            // above and below always fit — no manual height arithmetic.
            Expanded(
              child: FractionallySizedBox(
                alignment: Alignment.bottomCenter,
                widthFactor: 1,
                // Keep a sliver of a bar even at zero so the axis reads as a
                // base rather than as a gap.
                heightFactor: factor.clamp(0.04, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: selected ? 0.95 : 0.34),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              bucket.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? blue : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A clean banner naming the month being read, with a word of praise.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.monthLabel,
    required this.actions,
    required this.isCurrentMonth,
  });

  final String monthLabel;
  final int actions;

  /// Past months are described in the past tense; there is nothing left to
  /// encourage about a month that is over.
  final bool isCurrentMonth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color blue = MonthlyStatsScreen._blue;

    final String line;
    if (actions == 0) {
      line = isCurrentMonth
          ? 'חודש חדש, דף חדש — קדימה לעבודה!'
          : 'בחודש הזה לא נרשמו פעולות.';
    } else if (isCurrentMonth) {
      line = 'כל הכבוד! כבר עשית $actions פעולות טובות החודש עבור החברים שלך!';
    } else {
      line = 'בחודש הזה עשית $actions פעולות עבור החברים שלך.';
    }

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
                  line,
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
/// month improved on the previous one — a rise chip. Tapping it opens the
/// records the number was counted from.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.metric,
    required this.value,
    required this.previous,
    required this.onTap,
  });

  final MonthlyStatMetric metric;
  final int value;
  final int? previous;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = metric.color;

    // Requirement: only surface the month-over-month comparison when there is a
    // genuine rise. Drops or "no change" show nothing at all.
    final int? prev = previous;
    final bool showRise = prev != null && value - prev > 0;
    final int delta = prev == null ? 0 : value - prev;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      metric.title,
                      // Three lines: the longest label ("זוגות שהתחילו לצאת")
                      // needs a third at a phone's column width.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
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
                    child: Icon(metric.icon, color: accent, size: 24),
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
              // A fixed slot keeps every card the same height whether or not a
              // rise chip is present.
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
        ),
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '+$delta מהחודש שעבר',
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _riseColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
