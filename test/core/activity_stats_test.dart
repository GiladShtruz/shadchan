import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/enums.dart';

/// What counts as activity, and what each thing is worth.
///
/// This is the number the home block puts in front of the matchmaker and the
/// number the leaderboard sorts on, so the definition matters more than the
/// arithmetic. Four things count — a friend added, an idea opened, a couple who
/// started going out, an engagement — and they are weighted 1 / 1 / 5 / 50. A
/// note does not count, and neither does a status update any more.
void main() {
  final DateTime now = DateTime(2026, 8, 14, 12);
  final DateTime start = DateTime(2026, 8, 1);
  final DateTime end = DateTime(2026, 9, 1);

  Person person(String id, DateTime created, {bool hidden = false}) {
    return Person(
      id: id,
      firstName: 'שם$id',
      lastName: 'משפחה',
      gender: Gender.male,
      createdAt: created,
      updatedAt: created,
      hidden: hidden,
    );
  }

  MatchIdea match(
    String id,
    DateTime created, {
    MatchStatus status = MatchStatus.idea,
    String personA = 'a',
    String personB = 'b',
    DateTime? updated,
  }) {
    return MatchIdea(
      id: id,
      personAId: personA,
      personBId: personB,
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: created,
      updatedAt: updated ?? created,
    );
  }

  MatchStatusEvent statusEvent(
    String id,
    String matchId,
    MatchStatus to,
    DateTime at,
  ) {
    return MatchStatusEvent(
      id: id,
      matchId: matchId,
      fromStatus: MatchStatus.idea,
      toStatus: to,
      createdAt: at,
    );
  }

  ActivityBreakdown count({
    List<Person> people = const <Person>[],
    List<MatchIdea> matches = const <MatchIdea>[],
    List<MatchStatusEvent> matchStatusEvents = const <MatchStatusEvent>[],
    DateTime? from,
    DateTime? to,
  }) {
    return ActivityStats.breakdownBetween(
      start: from ?? start,
      end: to ?? end,
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      now: now,
    );
  }

  group('the weights', () {
    test('a friend and an idea are one point each', () {
      final ActivityBreakdown result = count(
        people: <Person>[person('1', now)],
        matches: <MatchIdea>[match('m', now)],
      );

      expect(result.friends, 1);
      expect(result.ideas, 1);
      expect(result.points, 2);
    });

    test('a couple who started dating is five points', () {
      // Two days ago, so it is past the 24-hour settling period.
      final DateTime startedDating = now.subtract(const Duration(days: 2));
      final ActivityBreakdown result = count(
        matches: <MatchIdea>[
          match('m', DateTime(2025), status: MatchStatus.dating),
        ],
        matchStatusEvents: <MatchStatusEvent>[
          statusEvent('e', 'm', MatchStatus.dating, startedDating),
        ],
      );

      expect(result.couples, 1);
      expect(result.points, 5);
    });

    test('an engagement is fifty points on top of the couple', () {
      // Both inside the window: the five points and the fifty are earned in
      // the same month here, which is what makes the sum worth asserting.
      final DateTime startedDating = now.subtract(const Duration(days: 10));
      final DateTime married = now.subtract(const Duration(days: 2));
      final ActivityBreakdown result = count(
        matches: <MatchIdea>[
          match('m', DateTime(2025), status: MatchStatus.married),
        ],
        matchStatusEvents: <MatchStatusEvent>[
          statusEvent('e1', 'm', MatchStatus.dating, startedDating),
          statusEvent('e2', 'm', MatchStatus.married, married),
        ],
      );

      // The five for going out are not taken back when they marry.
      expect(result.couples, 1);
      expect(result.engagements, 1);
      expect(result.points, 55);
    });
  });

  group('what is no longer activity', () {
    test('a status change on an idea is worth nothing', () {
      // "בבדיקה" and back again is two rows in a ledger and no change in
      // anybody's life. Only the moves that mean something are weighted.
      expect(
        count(
          matches: <MatchIdea>[match('m', DateTime(2025))],
          matchStatusEvents: <MatchStatusEvent>[
            statusEvent('e', 'm', MatchStatus.checking, now),
          ],
        ).points,
        0,
      );
    });

    test('a candidate going on a break is worth nothing', () {
      expect(
        count(
          matches: <MatchIdea>[match('m', DateTime(2025))],
          matchStatusEvents: <MatchStatusEvent>[
            statusEvent('e', 'm', MatchStatus.unavailable, now),
          ],
        ).points,
        0,
      );
    });
  });

  group('the count cannot be inflated', () {
    test('a friend who arrives twice in one day is counted once', () {
      // An import run a second time, a contact added by hand as well, or a
      // record deleted and immediately re-added — the last of which comes back
      // with a *new* id, so nothing keyed on the id would catch it.
      Person named(String id, String first, String last) => Person(
        id: id,
        firstName: first,
        lastName: last,
        gender: Gender.male,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        count(
          people: <Person>[
            named('first', 'יעקב', 'רוזן'),
            named('again', ' יעקב  ', 'רוזן'),
          ],
        ).friends,
        1,
      );
    });

    test('the same pair opened twice in one day is one idea', () {
      expect(
        count(
          matches: <MatchIdea>[
            match('one', now),
            match('two', now.add(const Duration(hours: 3))),
          ],
        ).ideas,
        1,
      );
    });

    test('a hidden friend is not counted', () {
      expect(
        count(people: <Person>[person('1', now, hidden: true)]).friends,
        0,
      );
    });

    test('records outside the window are left out', () {
      expect(
        count(people: <Person>[person('1', DateTime(2026, 7, 20))]).friends,
        0,
      );
    });
  });

  group('a large import', () {
    test('thirty friends imported at once are thirty points', () {
      // Real work, counted in full. There is no longer any rule anywhere that
      // discounts a big import — the personal weekly record it used to protect
      // is gone, and it was the only thing that needed protecting.
      final List<Person> batch = <Person>[
        for (int i = 0; i < 30; i++) person('$i', now)..importBatchId = 'one',
      ];

      final ActivityBreakdown result = count(people: batch);
      expect(result.friends, 30);
      expect(result.points, 30);
    });
  });

  group('הנתונים שלך — the all-time breakdown', () {
    test('counts everything ever, whenever it happened', () {
      final ActivityBreakdown result = ActivityStats.allTime(
        people: <Person>[
          person('recent', now.subtract(const Duration(days: 2))),
          person('old', DateTime(2024, 1, 1)),
        ],
        matches: <MatchIdea>[
          match(
            'm',
            DateTime(2024, 2, 1),
            status: MatchStatus.married,
            updated: DateTime(2024, 6, 1),
          ),
        ],
        matchStatusEvents: const <MatchStatusEvent>[],
        now: now,
      );

      expect(result.friends, 2);
      expect(result.ideas, 1);
      // No status ledger existed in 2024, so the couple is read out of the
      // proposal's own status and dated from `updatedAt`. That they married is
      // certain; only the date is approximate.
      expect(result.couples, 1);
      expect(result.engagements, 1);
      expect(result.points, 2 + 1 + 5 + 50);
    });
  });
}
