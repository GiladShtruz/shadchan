import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The records behind one number on "הנתונים שלך החודש".
///
/// A number on its own is only worth as much as the ability to ask "which
/// ones?" — so every card on the stats screen opens this: the same metric, the
/// actual proposals or people it counted, and how that one metric moved across
/// the recent months.
///
/// Stateful for one reason: "זוגות שהתחילו לצאת" is the only figure here that
/// can be edited, and taking a couple out of it has to redraw the list it was
/// just removed from.
class StatDetailScreen extends StatefulWidget {
  const StatDetailScreen({
    super.key,
    required this.metric,
    this.allTime = false,
  });

  final MonthlyStatMetric metric;

  /// Whether the number that opened this screen was an all-time figure.
  ///
  /// **This exists because the two callers count different windows.** The
  /// monthly stats screen shows this Hebrew month and opens the month's
  /// records; "הנתונים שלך" on the activity screen shows everything that ever
  /// happened, and used to open the *month's* records under it — so a tile
  /// reading 42 opened a list of four. The window travels with the tap now, and
  /// the list is always the list behind the number that was pressed.
  final bool allTime;

  /// How many Hebrew months back the per-metric trend reaches. Matches the
  /// stats screen's own window.
  static const int _monthsBack = 6;

  @override
  State<StatDetailScreen> createState() => _StatDetailScreenState();
}

class _StatDetailScreenState extends State<StatDetailScreen> {
  /// Takes one couple out of the historic count — reached only by a long
  /// press on its row, and only after "להסיר את הזוג מהרשימה?" is answered.
  /// The proposal keeps its status and every note on it.
  Future<void> _removeFromCount(MatchIdea match, String names) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'להסיר את הזוג מהרשימה?',
      message: '$names לא ייספרו יותר בזוגות שיצאו. הרעיון עצמו לא ישתנה.',
      confirmText: 'הסרה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await DatingCountExclusions.exclude(match.id);
    if (!mounted) {
      return;
    }
    setState(() {});
    AppNotice.show(
      context,
      '$names הוסרו מהספירה',
      actionLabel: 'ביטול',
      onAction: () async {
        await DatingCountExclusions.restore(match.id);
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MonthlyStatMetric metric = widget.metric;
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<MatchIdea> allMatches = matchRepository.getAll();
    final List<Person> allPeople = personRepository.getAll();
    final List<MatchStatusEvent> statusEvents = matchRepository
        .getAllStatusEvents();
    final Set<String> excludedFromDating = DatingCountExclusions.all();

    final List<MonthPeriod> periods = MonthlyStats.buildPeriods(
      DateTime.now(),
      StatDetailScreen._monthsBack,
    );
    final MonthPeriod current = periods.first;

    // "כל הזמנים" runs from the app's own beginning to the end of today, which
    // is the window `ActivityStats` counts an all-time figure over — the same
    // bounds, so the list here and the number that opened it are the same
    // arithmetic rather than two readings of it.
    final DateTime windowStart = widget.allTime
        ? ActivityStats.beginningOfTime
        : current.start;
    final DateTime windowEnd = widget.allTime
        ? ActivityStats.endOfToday()
        : current.end;

    final List<DatingCoupleRecord> couples = metric == MonthlyStatMetric.dating
        ? DatingHistory.all(
            matches: allMatches,
            statusEvents: statusEvents,
            excludedMatchIds: excludedFromDating,
          )
        : const <DatingCoupleRecord>[];
    final List<MatchIdea> matches = switch (metric) {
      MonthlyStatMetric.dating => const <MatchIdea>[],
      // Every proposal ever opened, deduplicated exactly as the score counts
      // them.
      MonthlyStatMetric.ideas when widget.allTime => ActivityStats.countedIdeas(
        start: windowStart,
        end: windowEnd,
        matches: allMatches,
      ),
      _ => MonthlyStats.matchesFor(metric, current, allMatches),
    };
    // The monthly list keeps `MonthlyStats`' own rule, because the number over
    // it on the stats screen is counted by that rule; the all-time list uses
    // `ActivityStats`, because the number over it on "הנתונים שלך" is counted
    // by *that* one. Each list is the list behind the figure that opened it,
    // which is the only property that matters here.
    final List<Person> people = !widget.allTime
        ? MonthlyStats.peopleFor(metric, current, allPeople)
        : metric == MonthlyStatMetric.people
        ? ActivityStats.countedFriends(
            start: windowStart,
            end: windowEnd,
            people: allPeople,
          )
        : const <Person>[];
    final int count = switch (metric) {
      MonthlyStatMetric.people => people.length,
      MonthlyStatMetric.dating => couples.length,
      MonthlyStatMetric.ideas || MonthlyStatMetric.weddings => matches.length,
    };

    String namesFor(MatchIdea match) {
      return '${_MatchRow._name(personRepository.getById(match.personAId))} & '
          '${_MatchRow._name(personRepository.getById(match.personBId))}';
    }

    final Widget trend = _MetricTrend(
      metric: metric,
      periods: periods.reversed.toList(),
      stats: <MonthStats>[
        for (final MonthPeriod period in periods.reversed)
          MonthlyStats.statsFor(
            period,
            allMatches,
            allPeople,
            statusEvents: statusEvents,
            excludedFromDating: excludedFromDating,
          ),
      ],
    );

    if (metric == MonthlyStatMetric.dating ||
        metric == MonthlyStatMetric.weddings) {
      return _CouplesPage(
        metric: metric,
        couples: couples,
        weddings: matches,
        people: personRepository,
        onRemove: (MatchIdea match) => _removeFromCount(match, namesFor(match)),
        trend: trend,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(metric.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _Headline(
              metric: metric,
              count: count,
              monthLabel: current.label,
              allTime: widget.allTime,
            ),
            const SizedBox(height: 20),
            if (count == 0)
              _EmptyLine(metric: metric, allTime: widget.allTime)
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
                    // Not `context.push`: this screen is above the tabs, where
                    // a tab route cannot be pushed — see [openPersonProfile].
                    onTap: () => openPersonProfile(context, person.id),
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
            trend,
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
    required this.allTime,
  });

  final MonthlyStatMetric metric;
  final int count;
  final String monthLabel;
  final bool allTime;

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
                ...<Widget>[
                  Text(
                    // A history carries no month: naming one would say the
                    // figure belongs to it.
                    metric.isAllTime || allTime
                        ? metric.title
                        : '${metric.title} · $monthLabel',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allTime ? metric.allTimeExplanation : metric.explanation,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sentence beside the number at the top of "זוגות שיצאו" and "חתונות".
///
/// **It never repeats the number** — the figure is printed large right beside
/// it — so it is the words that go with the figure, in the singular for one.
@visibleForTesting
String coupleEncouragement(MonthlyStatMetric metric, int count) {
  if (metric == MonthlyStatMetric.weddings) {
    const String tail = 'מזל טוב! כל בית חדש מתחיל במישהו שחשב על שניים.';
    return count == 1
        ? 'חתונה שהייתה לך יד בדרך אליה. $tail'
        : 'חתונות שהייתה לך יד בדרך אליהן. $tail';
  }
  const String tail = 'כל הכבוד שהיית עבורם חלק משמעותי במסע אל החתונה.';
  return count == 1
      ? 'זוג יצא לדייט בזכותך! $tail'
      : 'זוגות יצאו לדייט בזכותך! $tail';
}

/// What the same tile says when there is nothing to count yet: warm, and
/// never a zero. With [community] — the whole community's own figure — it
/// says the matchmaker is part of something that is already happening.
@visibleForTesting
String coupleZeroLine(
  MonthlyStatMetric metric, {
  int? community,
  Gender? gender,
}) {
  final bool wedding = metric == MonthlyStatMetric.weddings;
  final int shared = community ?? 0;
  if (shared > 0) {
    return wedding
        ? '{אתה|את} חלק מקהילה שכבר חגגה $shared חתונות. ממשיכים לנסות — '
                  'החתונה הבאה יכולה להתחיל ממך.'
              .forGender(gender)
        : '{אתה|את} חלק מקהילה שהוציאה $shared זוגות לדייט. ממשיכים לנסות, '
                  'בשביל החברים.'
              .forGender(gender);
  }
  return wedding
      ? 'החתונה הראשונה עוד לפניך, וכל רעיון שנפתח הוא צעד בדרך אליה. '
            'ממשיכים לנסות, בשביל החברים.'
      : 'הזוג הראשון עוד לפניך, וכל רעיון שנפתח מקרב אותו. ממשיכים לנסות, '
            'בשביל החברים.';
}

/// "זוגות שיצאו" and "חתונות": one page for the two, in the home page's
/// language — the figure and one warm sentence on a paper tile, then the
/// couples themselves, each a tap away from its idea on "הרעיונות שלי".
class _CouplesPage extends StatelessWidget {
  const _CouplesPage({
    required this.metric,
    required this.couples,
    required this.weddings,
    required this.people,
    required this.onRemove,
    required this.trend,
  });

  final MonthlyStatMetric metric;

  /// The dating couples, when [metric] is dating.
  final List<DatingCoupleRecord> couples;

  /// The married ideas, when [metric] is weddings.
  final List<MatchIdea> weddings;
  final PersonRepository people;

  /// A long press on a dating couple — see [_StatDetailScreenState].
  final void Function(MatchIdea match) onRemove;
  final Widget trend;

  bool get _dating => metric == MonthlyStatMetric.dating;

  @override
  Widget build(BuildContext context) {
    final int count = _dating ? couples.length : weddings.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_dating ? 'זוגות שיצאו' : 'חתונות'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            _CouplesHeadline(metric: metric, count: count),
            const SizedBox(height: 16),
            if (_dating)
              for (final DatingCoupleRecord record in couples)
                _CoupleCard(
                  match: record.match,
                  people: people,
                  footnote: _datingSpan(record),
                  onTap: () => context.go('/matches/${record.match.id}'),
                  onLongPress: () => onRemove(record.match),
                )
            else
              for (final MatchIdea match in weddings)
                _CoupleCard(
                  match: match,
                  people: people,
                  footnote:
                      'מזל טוב · ${AppDateUtils.timeAgoShort(match.updatedAt)}',
                  onTap: () => context.go('/matches/${match.id}'),
                ),
            if (count > 0) ...<Widget>[const SizedBox(height: 20), trend],
          ],
        ),
      ),
    );
  }

  /// How long the couple have been — or were — going out, instead of a date.
  static String _datingSpan(DatingCoupleRecord record) {
    final MatchIdea match = record.match;
    switch (match.status) {
      case MatchStatus.dating:
        final String span = AppDateUtils.elapsedLabel(record.startedAt);
        return span == 'מהיום' ? 'יוצאים מהיום' : 'יוצאים כבר $span';
      case MatchStatus.married:
        return 'יצאו עד החתונה · מזל טוב!';
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.unavailable:
      case MatchStatus.rejected:
      case MatchStatus.dated:
        // How long they went out, as recorded when they stopped; for a
        // couple from before that was recorded, until the idea last moved.
        final String span = AppDateUtils.spanLabel(
          match.datingSpan() ?? match.updatedAt.difference(record.startedAt),
        );
        return span == 'מהיום' ? 'יצאו פעם אחת' : 'יצאו במשך $span';
    }
  }
}

/// The figure and its sentence — or, with nothing to count, the encouraging
/// line and nothing that looks like a score.
class _CouplesHeadline extends StatelessWidget {
  const _CouplesHeadline({required this.metric, required this.count});

  final MonthlyStatMetric metric;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = metric == MonthlyStatMetric.weddings
        ? AppColors.metric(MetricKind.weddings, dark: dark)
        : AppColors.metric(MetricKind.couples, dark: dark);
    final TextStyle? sentence = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.45,
      color: AppColors.heading(dark: dark),
    );

    return HomePaperCard(
      stripe: accent,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: count == 0
          ? Row(
              children: <Widget>[
                Icon(metric.icon, color: accent, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: FutureBuilder<int?>(
                    future: _communityFigure(metric),
                    builder:
                        (BuildContext context, AsyncSnapshot<int?> snapshot) {
                          return Text(
                            coupleZeroLine(
                              metric,
                              community: snapshot.data,
                              gender: context.userGender,
                            ),
                            style: sentence,
                          );
                        },
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Text(
                  '$count',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    coupleEncouragement(metric, count),
                    style: sentence,
                  ),
                ),
              ],
            ),
    );
  }

  /// The community's all-time figure for this metric, when it can be had
  /// without starting anything: only once Firebase is already up, and only a
  /// read that actually came back. Otherwise the line goes without it.
  static Future<int?> _communityFigure(MonthlyStatMetric metric) async {
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    try {
      final CommunityTotals totals = await CommunityService.totals(
        CommunityPeriod.allTime,
      );
      if (!totals.resolved) {
        return null;
      }
      return metric == MonthlyStatMetric.weddings
          ? totals.engagements
          : totals.couples;
    } on Object {
      return null;
    }
  }
}

/// One couple: both faces, the boy's name first in blue and the girl's in
/// rose, and one quiet line under them.
class _CoupleCard extends StatelessWidget {
  const _CoupleCard({
    required this.match,
    required this.people,
    required this.footnote,
    required this.onTap,
    this.onLongPress,
  });

  final MatchIdea match;
  final PersonRepository people;
  final String footnote;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Person? a = people.getById(match.personAId);
    final Person? b = people.getById(match.personBId);
    // The boy first, as on every board row.
    final bool aFirst = a?.gender != Gender.female;
    final Person? first = aFirst ? a : b;
    final Person? second = aFirst ? b : a;

    TextSpan name(Person? person) => TextSpan(
      text: _MatchRow._name(person),
      style: TextStyle(
        color: person == null || person.gender == Gender.unknown
            ? AppColors.heading(dark: dark)
            : AppColors.genderAccent(person.gender, dark: dark),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: <Widget>[
                HomeCardCoupleAvatars(
                  personA: first,
                  personB: second,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            name(first),
                            TextSpan(
                              text: ' & ',
                              style: TextStyle(
                                color: AppColors.muted(dark: dark),
                              ),
                            ),
                            name(second),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        footnote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted(dark: dark),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted(dark: dark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.metric, this.allTime = false});

  final MonthlyStatMetric metric;
  final bool allTime;

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
            allTime ? metric.allTimeEmptyLine : metric.emptyLine,
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
