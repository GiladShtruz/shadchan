import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';

/// The four windows this device publishes, built from the same ledgers.
///
/// The day and the week are Israel-timed on purpose: two matchmakers' weeks
/// have to be the same week before their scores can be added together, and the
/// leaderboard resets at midnight in Jerusalem wherever the phone is. The week
/// turns over at midnight on מוצאי שבת — Sunday 00:00 — and the month is the
/// **Hebrew** month, from one Rosh Chodesh to the next, which is the month
/// every chart in the app is already drawn in.
void main() {
  // A Wednesday. The Sunday-start week therefore begins on the 16th.
  final DateTime now = DateTime(2026, 8, 19, 12);
  final DateTime roshChodesh = HebrewDateUtils.hebrewMonthStart(now);

  Person person(String id, DateTime created) => Person(
    id: id,
    firstName: 'שם$id',
    lastName: 'משפחה',
    gender: Gender.male,
    createdAt: created,
    updatedAt: created,
  );

  MatchIdea match(String id, DateTime created, {MatchStatus? status}) =>
      MatchIdea(
        id: id,
        personAId: 'a$id',
        personBId: 'b$id',
        status: status ?? MatchStatus.idea,
        currentHandler: CurrentHandler.me,
        createdAt: created,
        updatedAt: created,
      );

  CommunityMemberCounts build({
    List<Person> people = const <Person>[],
    List<MatchIdea> matches = const <MatchIdea>[],
    List<MatchStatusEvent> events = const <MatchStatusEvent>[],
  }) {
    return CommunityCounts.build(
      people: people,
      matches: matches,
      matchStatusEvents: events,
      now: now,
    );
  }

  test('the week starts at midnight on מוצאי שבת', () {
    final DateTime? start = CommunityPeriods.startOf(CommunityPeriod.week, now);
    // Sunday the 16th, at midnight — the moment Saturday night becomes Sunday.
    expect(start, DateTime(2026, 8, 16));
    expect(start!.weekday, DateTime.sunday);
  });

  test('the month starts at Rosh Chodesh, not on the 1st', () {
    expect(CommunityPeriods.startOf(CommunityPeriod.month, now), roshChodesh);
    // The Hebrew month key is what every device agrees on, and it is not the
    // Gregorian one.
    expect(CommunityPeriods.monthKey(now).startsWith('H'), isTrue);
    expect(
      CommunityPeriods.monthKey(now),
      CommunityPeriods.monthKey(roshChodesh),
    );
    expect(
      CommunityPeriods.monthKey(now),
      isNot(
        CommunityPeriods.monthKey(
          roshChodesh.subtract(const Duration(days: 1)),
        ),
      ),
    );
  });

  test('the four windows nest inside each other', () {
    final CommunityMemberCounts counts = build(
      people: <Person>[
        person('today', now),
        person('monday', DateTime(2026, 8, 17)),
        // Inside the Hebrew month but before this week began.
        person('roshChodesh', roshChodesh),
        person('lastYear', DateTime(2025, 3, 3)),
      ],
    );

    expect(counts.day.friends, 1);
    // Sunday the 16th onwards: today and Monday.
    expect(counts.week.friends, 2);
    // This Hebrew month: the two above and the one added on Rosh Chodesh.
    expect(counts.month.friends, 3);
    expect(counts.allTime.friends, 4);
  });

  test('a narrower window never reports more than a wider one', () {
    // One friend on every day of the last hundred, so no window can be empty
    // and every boundary is crossed by something.
    final CommunityMemberCounts counts = build(
      people: <Person>[
        for (int day = 0; day < 100; day++)
          person('d$day', now.subtract(Duration(days: day))),
      ],
    );

    expect(counts.day.friends, lessThanOrEqualTo(counts.week.friends));
    expect(counts.month.friends, lessThanOrEqualTo(counts.allTime.friends));
    expect(counts.day.points, lessThanOrEqualTo(counts.week.points));
    expect(counts.month.points, lessThanOrEqualTo(counts.allTime.points));
    // The week is inside the month whenever it did not begin before Rosh
    // Chodesh, which is the only case the two can honestly disagree in.
    final DateTime weekStart = CommunityPeriods.startOf(
      CommunityPeriod.week,
      now,
    )!;
    if (!weekStart.isBefore(roshChodesh)) {
      expect(counts.week.friends, lessThanOrEqualTo(counts.month.friends));
      expect(counts.week.points, lessThanOrEqualTo(counts.month.points));
    }
  });

  test('a score is published for every window, weighted the same way', () {
    final CommunityMemberCounts counts = build(
      people: <Person>[person('today', now)],
      matches: <MatchIdea>[match('m', now)],
    );

    for (final CommunityPeriod period in CommunityPeriod.values) {
      expect(counts.pointsFor(period), 2, reason: period.name);
    }
  });

  test('a couple settles for a day before it is worth anything', () {
    MatchStatusEvent dating(String id, DateTime at) => MatchStatusEvent(
      id: id,
      matchId: id,
      fromStatus: MatchStatus.idea,
      toStatus: MatchStatus.dating,
      createdAt: at,
    );

    final CommunityMemberCounts counts = build(
      matches: <MatchIdea>[
        match('settled', DateTime(2025), status: MatchStatus.dating),
        match('fresh', DateTime(2025), status: MatchStatus.dating),
      ],
      events: <MatchStatusEvent>[
        dating('settled', now.subtract(const Duration(days: 2))),
        dating('fresh', now.subtract(const Duration(hours: 3))),
      ],
    );

    // A status set and undone within the hour is a correction, not a couple —
    // so the fresh one is not in any window yet.
    expect(counts.week.couples, 1);
    expect(counts.week.points, 5);
    expect(counts.allTime.couples, 1);
  });

  test('an empty database publishes zeroes rather than nothing', () {
    final CommunityMemberCounts counts = build();
    expect(counts.allTime.points, 0);
    expect(counts.forPeriod(CommunityPeriod.day).friends, 0);
  });
}
