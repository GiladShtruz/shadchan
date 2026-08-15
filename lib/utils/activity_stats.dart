import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/utils/monthly_stats.dart';

/// One bar on the activity chart.
class ActivityBucket {
  const ActivityBucket({
    required this.label,
    required this.count,
    required this.period,
  });

  final String label;
  final int count;

  /// The month the bar stands for, so tapping it can move the whole screen to
  /// that month rather than only highlighting a column.
  final MonthPeriod period;
}

/// The three windows the home card offers.
class ActivityTotals {
  const ActivityTotals({
    required this.week,
    required this.month,
    required this.allTime,
  });

  final int week;
  final int month;
  final int allTime;
}

/// How much the matchmaker actually did, counted from the records themselves.
///
/// Deliberately not "time spent in the app". Sitting on the ideas screen for an
/// hour is not work, and adding a friend on the bus is. Three things are
/// counted, and they are the three that change something for a real person:
///
/// * a friend added,
/// * an idea opened,
/// * a status updated — on a friend or on an idea.
///
/// Both status kinds now come from a dedicated dated record — `PersonEvent`
/// for a candidate, `MatchStatusEvent` for a proposal — rather than being
/// inferred from whichever journal notes the app happens to write. That is what
/// makes the figure arithmetic instead of an estimate.
///
/// **A note is not an action.** Writing something down is how the matchmaker
/// thinks; counting it rewards typing rather than doing, and someone who keeps
/// careful notes on one candidate would out-score someone who opened five
/// proposals.
///
/// Each is counted from its own dated record rather than from an activity log,
/// which has two consequences worth keeping: the history survives however long
/// ago it happened, and editing the same record ten times is one action.
abstract final class ActivityStats {
  static int countBetween({
    required DateTime start,
    required DateTime end,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    required List<PersonEvent> events,
  }) {
    bool inRange(DateTime at) => !at.isBefore(start) && at.isBefore(end);

    int total = 0;
    for (final Person person in people) {
      if (!person.hidden && inRange(person.createdAt)) {
        total++;
      }
    }
    for (final MatchIdea match in matches) {
      if (inRange(match.createdAt)) {
        total++;
      }
    }

    // A proposal's own moves, from the ledger the repository writes on every
    // transition. `automatic` ones are the app moving a proposal because a
    // candidate went on a break — one decision about a person, which is counted
    // once as that person's own status change, below.
    for (final MatchStatusEvent event in matchStatusEvents) {
      if (!event.automatic && inRange(event.createdAt)) {
        total++;
      }
    }

    // A candidate's own status changes. One with a `relatedMatchId` was written
    // by the app because a proposal moved — a couple who started dating are
    // both marked "תפוס" — and the proposal's move has already been counted, so
    // counting these too would make one act worth three.
    for (final PersonEvent event in events) {
      if (event.type == PersonEventType.statusChanged &&
          event.relatedMatchId == null &&
          inRange(event.createdAt)) {
        total++;
      }
    }
    return total;
  }

  /// This week, this Hebrew month, and everything ever — what the home card
  /// offers as three choices.
  static ActivityTotals totals({
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    required List<PersonEvent> events,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final DateTime today = DateTime(at.year, at.month, at.day);
    final MonthPeriod month = MonthlyStats.buildPeriods(at, 1).first;

    int count(DateTime start, DateTime end) => countBetween(
      start: start,
      end: end,
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      events: events,
    );

    return ActivityTotals(
      week: count(
        today.subtract(const Duration(days: 6)),
        today.add(const Duration(days: 1)),
      ),
      month: count(month.start, month.end),
      allTime: count(DateTime(2000), at.add(const Duration(days: 1))),
    );
  }

  /// One bar per Hebrew month, oldest first — the same month division the rest
  /// of the app already uses, so the chart and the figures agree.
  static List<ActivityBucket> monthlyBars({
    required List<MonthPeriod> periods,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    required List<PersonEvent> events,
  }) {
    return <ActivityBucket>[
      for (final MonthPeriod period in periods.reversed)
        ActivityBucket(
          label: period.shortLabel,
          period: period,
          count: countBetween(
            start: period.start,
            end: period.end,
            people: people,
            matches: matches,
            matchStatusEvents: matchStatusEvents,
            events: events,
          ),
        ),
    ];
  }

  /// A word for how the month has gone.
  ///
  /// Generous on purpose, and never comparative: the scale is what this
  /// matchmaker did, not how they rank against anybody. There is no wording for
  /// "not enough" because there is no such amount.
  static String grade(int actions) {
    if (actions == 0) {
      return 'מוכנים להתחיל';
    }
    if (actions < 5) {
      return 'התחלה טובה';
    }
    if (actions < 15) {
      return 'שבוע פעיל';
    }
    if (actions < 40) {
      return 'קצב יפה';
    }
    return 'בונה בתים';
  }
}
