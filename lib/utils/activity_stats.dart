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
    int? weekForRecord,
  }) : weekForRecord = weekForRecord ?? week;

  final int week;
  final int month;
  final int allTime;

  /// The same week as [week], with any oversized import taken back out — the
  /// figure the *personal weekly record* is judged by, and the only thing this
  /// is for. Never shown, never published, never added to anybody else's.
  ///
  /// Equal to [week] unless a bulk-import limit was asked for. See
  /// [ActivityStats.countBetween].
  final int weekForRecord;
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
  /// The day an event falls on, as a key. Everything deduplicated here is
  /// deduplicated *per day* rather than for all time: adding the same friend
  /// again next month is a real second act of matchmaking, and changing
  /// somebody's status again next week is real work.
  static String _dayKey(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  /// A name reduced to what makes two entries the same person: no case, no
  /// runs of whitespace, no punctuation between the parts.
  static String _nameKey(Person person) => person.fullName
      .toLowerCase()
      .replaceAll(RegExp(r'''[\s'"־–—.,()\-]+'''), ' ')
      .trim();

  /// Which import batches are too big to be allowed to set a record.
  ///
  /// Measured over *every* person handed in, not only the ones inside the
  /// window: a batch of four hundred does not become a batch of twenty because
  /// the window happens to clip it. Records that have since been deleted are
  /// gone from the list entirely and cannot be counted, so this is the
  /// surviving size of the import rather than the size it was on the day — the
  /// error only ever runs in the matchmaker's favour, which is the right
  /// direction for a rule about who may hold a record.
  static Set<String> _oversizedBatches(List<Person> people, int limit) {
    final Map<String, int> sizes = <String, int>{};
    for (final Person person in people) {
      final String batch = person.importBatchId ?? '';
      if (batch.isNotEmpty) {
        sizes[batch] = (sizes[batch] ?? 0) + 1;
      }
    }
    return <String>{
      for (final MapEntry<String, int> entry in sizes.entries)
        if (entry.value > limit) entry.key,
    };
  }

  /// [bulkImportLimit], when given, drops friends who arrived in a single
  /// import of more than that many people.
  ///
  /// **It is off by default, and every figure anybody ever sees leaves it
  /// off.** An import of four hundred cards is real work: it counts towards the
  /// activity screen, the community total and the leaderboard exactly like
  /// four hundred friends added by hand. The one thing it may not do is set the
  /// personal weekly record, because a record of four hundred is a record
  /// nobody can beat, and an unbeatable record is not encouragement — it is the
  /// end of the feature. So the exclusion belongs to that one question and to
  /// nothing else.
  static int countBetween({
    required DateTime start,
    required DateTime end,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    required List<PersonEvent> events,
    int? bulkImportLimit,
  }) {
    bool inRange(DateTime at) => !at.isBefore(start) && at.isBefore(end);

    final Set<String> oversized = bulkImportLimit == null
        ? const <String>{}
        : _oversizedBatches(people, bulkImportLimit);

    // Everything below is counted through one of these sets, so the same act
    // can never be worth two. They exist because the figure is not private any
    // more: it feeds the community total and the leaderboard, and a number
    // anybody can inflate by flipping a status back and forth is not a number
    // worth showing to other people.
    final Set<String> counted = <String>{};
    bool once(String key) => counted.add(key);

    int total = 0;

    // A friend added. Deduplicated by name *and day*, which covers three of the
    // rules at once: an import run twice, a contact added twice by hand, and a
    // record deleted and immediately re-added — that last one comes back with a
    // new id, so an id-based check would miss it entirely.
    for (final Person person in people) {
      if (person.hidden || !inRange(person.createdAt)) {
        continue;
      }
      if (oversized.contains(person.importBatchId)) {
        continue;
      }
      if (once('person:${_nameKey(person)}:${_dayKey(person.createdAt)}')) {
        total++;
      }
    }

    // An idea opened. Keyed by the pair rather than by the proposal id, for the
    // same delete-and-reopen reason.
    for (final MatchIdea match in matches) {
      if (!inRange(match.createdAt)) {
        continue;
      }
      final List<String> pair = <String>[match.personAId, match.personBId]
        ..sort();
      if (once('idea:${pair.join('|')}:${_dayKey(match.createdAt)}')) {
        total++;
      }
    }

    // A proposal's own moves, from the ledger the repository writes on every
    // transition. `automatic` ones are the app moving a proposal because a
    // candidate went on a break — one decision about a person, which is counted
    // once as that person's own status change, below.
    //
    // One per proposal per day. Moving a proposal to "בבדיקה" and back again
    // the same afternoon is one piece of work, however many rows it wrote.
    for (final MatchStatusEvent event in matchStatusEvents) {
      if (event.automatic || !inRange(event.createdAt)) {
        continue;
      }
      if (once('ideaStatus:${event.matchId}:${_dayKey(event.createdAt)}')) {
        total++;
      }
    }

    // A candidate's own status changes. One with a `relatedMatchId` was written
    // by the app because a proposal moved — a couple who started dating are
    // both marked "תפוס" — and the proposal's move has already been counted, so
    // counting these too would make one act worth three. Same one-per-day rule.
    for (final PersonEvent event in events) {
      if (event.type != PersonEventType.statusChanged ||
          event.relatedMatchId != null ||
          !inRange(event.createdAt)) {
        continue;
      }
      if (once('personStatus:${event.personId}:${_dayKey(event.createdAt)}')) {
        total++;
      }
    }
    return total;
  }

  /// This week, this Hebrew month, and everything ever — what the home card
  /// offers as three choices.
  /// [recordBulkImportLimit] is passed straight through to [countBetween] for
  /// the extra `weekForRecord` figure only; the three figures on show are
  /// always counted with everything in.
  static ActivityTotals totals({
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    required List<PersonEvent> events,
    DateTime? now,
    int? recordBulkImportLimit,
  }) {
    final DateTime at = now ?? DateTime.now();
    final DateTime today = DateTime(at.year, at.month, at.day);
    final MonthPeriod month = MonthlyStats.buildPeriods(at, 1).first;

    int count(DateTime start, DateTime end, {int? bulkImportLimit}) =>
        countBetween(
          start: start,
          end: end,
          people: people,
          matches: matches,
          matchStatusEvents: matchStatusEvents,
          events: events,
          bulkImportLimit: bulkImportLimit,
        );

    final DateTime weekStart = today.subtract(const Duration(days: 6));
    final DateTime tomorrow = today.add(const Duration(days: 1));

    return ActivityTotals(
      week: count(weekStart, tomorrow),
      month: count(month.start, month.end),
      allTime: count(DateTime(2000), at.add(const Duration(days: 1))),
      weekForRecord: recordBulkImportLimit == null
          ? null
          : count(weekStart, tomorrow, bulkImportLimit: recordBulkImportLimit),
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
