import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The records behind one number on "הנתונים שלך החודש".
///
/// A number on its own is only worth as much as the ability to ask "which
/// ones?" — so every card on the stats screen opens this: the same metric, the
/// same Hebrew month, and the actual proposals or people it counted, followed
/// by how that one metric moved across the recent months.
class StatDetailScreen extends StatelessWidget {
  const StatDetailScreen({super.key, required this.metric});

  final MonthlyStatMetric metric;

  /// How many Hebrew months back the per-metric trend reaches. Matches the
  /// stats screen's own window.
  static const int _monthsBack = 6;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<MatchIdea> allMatches = matchRepository.getAll();
    final List<Person> allPeople = personRepository.getAll();

    final List<MonthPeriod> periods = MonthlyStats.buildPeriods(
      DateTime.now(),
      _monthsBack,
    );
    final MonthPeriod current = periods.first;

    final List<MatchIdea> matches = MonthlyStats.matchesFor(
      metric,
      current,
      allMatches,
    );
    final List<Person> people = MonthlyStats.peopleFor(
      metric,
      current,
      allPeople,
    );
    final int count = metric == MonthlyStatMetric.people
        ? people.length
        : matches.length;

    return Scaffold(
      appBar: AppBar(title: Text(metric.title), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _Headline(metric: metric, count: count, monthLabel: current.label),
            const SizedBox(height: 20),
            if (count == 0)
              _EmptyLine(metric: metric)
            else ...<Widget>[
              Text(
                'מה נספר',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (metric == MonthlyStatMetric.people)
                for (final Person person in people)
                  _PersonRow(
                    person: person,
                    onTap: () => context.push('/people/${person.id}'),
                  )
              else
                for (final MatchIdea match in matches)
                  _MatchRow(
                    match: match,
                    personA: personRepository.getById(match.personAId),
                    personB: personRepository.getById(match.personBId),
                    metric: metric,
                    onTap: () => context.push('/matches/${match.id}'),
                  ),
            ],
            const SizedBox(height: 24),
            _MetricTrend(
              metric: metric,
              periods: periods.reversed.toList(),
              stats: <MonthStats>[
                for (final MonthPeriod period in periods.reversed)
                  MonthlyStats.statsFor(period, allMatches, allPeople),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The big number, in the metric's own accent, over the month it belongs to.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.metric,
    required this.count,
    required this.monthLabel,
  });

  final MonthlyStatMetric metric;
  final int count;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = metric.color;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
            ),
            child: Icon(metric.icon, color: accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$count',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${metric.title} · $monthLabel',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.explanation,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
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

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.metric});

  final MonthlyStatMetric metric;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: <Widget>[
          Icon(
            metric.icon,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            metric.emptyLine,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.personA,
    required this.personB,
    required this.metric,
    required this.onTap,
  });

  final MatchIdea match;
  final Person? personA;
  final Person? personB;
  final MonthlyStatMetric metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // "רעיונות שנפתחו" is dated by when it opened; the other two by the update
    // that moved the couple, which is what was counted.
    final DateTime at = metric == MonthlyStatMetric.ideas
        ? match.createdAt
        : match.updatedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                HomeCardCoupleAvatars(
                  personA: personA,
                  personB: personB,
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${_name(personA)} & ${_name(personB)}',
                        maxLines: 2,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${match.status.displayName} · '
                        '${AppDateUtils.formatDateShort(at)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _name(Person? person) {
    final String full = person?.fullName.trim() ?? '';
    return full.isEmpty ? '—' : full;
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                PersonAvatar(person: person, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        person.fullName.trim(),
                        maxLines: 2,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'נוסף · ${AppDateUtils.formatDateShort(person.createdAt)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same bar chart the stats screen draws, but for this one metric only.
class _MetricTrend extends StatelessWidget {
  const _MetricTrend({
    required this.metric,
    required this.periods,
    required this.stats,
  });

  /// Oldest first, so the bars read right-to-left up to the current month.
  final MonthlyStatMetric metric;
  final List<MonthPeriod> periods;
  final List<MonthStats> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<int> values = <int>[
      for (final MonthStats month in stats) metric.valueOf(month),
    ];
    final int maxValue = values.fold<int>(0, (int a, int b) => a > b ? a : b);

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
          Text(
            '${metric.title} לאורך החודשים',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < periods.length; i++)
                  Expanded(
                    child: _Bar(
                      value: values[i],
                      maxValue: maxValue,
                      label: periods[i].shortLabel,
                      accent: metric.color,
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

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.maxValue,
    required this.label,
    required this.accent,
    required this.isCurrent,
  });

  final int value;
  final int maxValue;
  final String label;
  final Color accent;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double factor = maxValue == 0 ? 0 : value / maxValue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: isCurrent ? accent : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              widthFactor: 1,
              // Keep a sliver of a bar even at zero so the axis reads as a base.
              heightFactor: factor.clamp(0.03, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrent ? accent : accent.withValues(alpha: 0.35),
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
              color: isCurrent ? accent : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
