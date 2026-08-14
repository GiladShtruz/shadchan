import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/utils/monthly_stats.dart';

/// One bar on the activity chart.
class ActivityBucket {
  const ActivityBucket({required this.label, required this.count});

  final String label;
  final int count;
}

/// How much the matchmaker actually did, counted from the records themselves.
///
/// Deliberately not "time spent in the app". Sitting on the ideas screen for an
/// hour is not work, and adding a friend on the bus is. The five things counted
/// are the five that change something for a real person:
///
/// * a friend added,
/// * an idea opened,
/// * a proposal's status updated,
/// * a note written about a friend,
/// * a note written about an idea.
///
/// Each is counted from its own dated record rather than from an activity log,
/// which has two consequences worth keeping: the history survives however long
/// ago it happened, and editing the same note ten times is one note, not ten
/// actions.
abstract final class ActivityStats {
  static int countBetween({
    required DateTime start,
    required DateTime end,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<PersonNote> personNotes,
    required List<MatchNote> matchNotes,
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
    for (final PersonNote note in personNotes) {
      if (!note.isAutomatic && inRange(note.createdAt)) {
        total++;
      }
    }
    for (final MatchNote note in matchNotes) {
      if (!note.isAutomatic && inRange(note.createdAt)) {
        total++;
      }
    }
    for (final PersonEvent event in events) {
      if (event.type == PersonEventType.statusChanged &&
          inRange(event.createdAt)) {
        total++;
      }
    }
    return total;
  }

  /// One bar per Hebrew month, oldest first — the same month division the rest
  /// of the app already uses, so the chart and the figures agree.
  static List<ActivityBucket> monthlyBars({
    required List<MonthPeriod> periods,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<PersonNote> personNotes,
    required List<MatchNote> matchNotes,
    required List<PersonEvent> events,
  }) {
    return <ActivityBucket>[
      for (final MonthPeriod period in periods.reversed)
        ActivityBucket(
          label: period.shortLabel,
          count: countBetween(
            start: period.start,
            end: period.end,
            people: people,
            matches: matches,
            personNotes: personNotes,
            matchNotes: matchNotes,
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
