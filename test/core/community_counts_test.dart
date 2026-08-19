import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/enums.dart';

/// The four windows this device publishes, built from the same ledgers.
///
/// The windows are Gregorian and Israel-timed on purpose: two matchmakers'
/// weeks have to be the same week before their scores can be added together,
/// and the leaderboard resets at midnight in Jerusalem wherever the phone is.
void main() {
  // A Wednesday. The Sunday-start week therefore begins on the 16th.
  final DateTime now = DateTime(2026, 8, 19, 12);

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

  test('the four windows nest inside each other', () {
    final CommunityMemberCounts counts = build(
      people: <Person>[
        person('today', now),
        person('monday', DateTime(2026, 8, 17)),
        person('lastWeek', DateTime(2026, 8, 10)),
        person('lastYear', DateTime(2025, 3, 3)),
      ],
    );

    expect(counts.day.friends, 1);
    // Sunday the 16th onwards: today and Monday.
    expect(counts.week.friends, 2);
    // August: everything but last year.
    expect(counts.month.friends, 3);
    expect(counts.allTime.friends, 4);
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
