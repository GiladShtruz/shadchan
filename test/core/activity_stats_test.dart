import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/enums.dart';

/// What counts as a *pealah* — an action — and what does not.
///
/// This is the number the home screen puts in front of the matchmaker, so the
/// definition matters more than the arithmetic. Three things count: a friend
/// added, an idea opened, a status updated. A note does not, and a couple who
/// moved to "יוצאים" counts once even though the move writes three records.
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

  MatchIdea match(String id, DateTime created) {
    return MatchIdea(
      id: id,
      personAId: 'a',
      personBId: 'b',
      status: MatchStatus.idea,
      currentHandler: CurrentHandler.me,
      createdAt: created,
      updatedAt: created,
    );
  }

  MatchStatusEvent matchStatus(
    String id,
    DateTime at, {
    bool automatic = false,
  }) {
    return MatchStatusEvent(
      id: id,
      matchId: 'm',
      fromStatus: MatchStatus.idea,
      toStatus: MatchStatus.dating,
      createdAt: at,
      automatic: automatic,
    );
  }

  PersonEvent statusEvent(String id, DateTime at, {String? causedByMatch}) {
    return PersonEvent(
      id: id,
      personId: 'a',
      type: PersonEventType.statusChanged,
      text: 'הסטטוס שונה ל־תפוס',
      createdAt: at,
      relatedMatchId: causedByMatch,
    );
  }

  int count({
    List<Person> people = const <Person>[],
    List<MatchIdea> matches = const <MatchIdea>[],
    List<MatchStatusEvent> matchStatusEvents = const <MatchStatusEvent>[],
    List<PersonEvent> events = const <PersonEvent>[],
  }) {
    return ActivityStats.countBetween(
      start: start,
      end: end,
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      events: events,
    );
  }

  test('adding a friend and opening an idea are each one action', () {
    expect(
      count(
        people: <Person>[person('1', now)],
        matches: <MatchIdea>[match('m', now)],
      ),
      2,
    );
  });

  test('a status change on an idea is an action', () {
    expect(
      count(matchStatusEvents: <MatchStatusEvent>[matchStatus('e', now)]),
      1,
    );
  });

  test('a move the app made itself is history, not work', () {
    // A candidate going on a break pushes their open proposals to "בהמתנה".
    // That is one decision about a person, counted as that person's own status
    // change — not as one action per proposal it touched.
    expect(
      count(
        matchStatusEvents: <MatchStatusEvent>[
          matchStatus('e1', now, automatic: true),
          matchStatus('e2', now, automatic: true),
        ],
      ),
      0,
    );
  });

  test('a status change on a friend is an action', () {
    expect(count(events: <PersonEvent>[statusEvent('e', now)]), 1);
  });

  test('a couple who started dating counts once, not three times', () {
    // One call writes the proposal's own record and an automatic "תפוס" on
    // each candidate. The two person events carry the proposal's id, which is
    // what marks them as the same act rather than two more.
    expect(
      count(
        matchStatusEvents: <MatchStatusEvent>[matchStatus('e', now)],
        events: <PersonEvent>[
          statusEvent('a', now, causedByMatch: 'm'),
          statusEvent('b', now, causedByMatch: 'm'),
        ],
      ),
      1,
    );
  });

  test('a status set by hand in the same second is still its own action', () {
    // The old rule dropped anything within five seconds of a proposal's move.
    // Nothing is inferred from timing any more, so a real decision made at the
    // same instant is counted — which it always should have been.
    expect(
      count(
        matchStatusEvents: <MatchStatusEvent>[matchStatus('e', now)],
        events: <PersonEvent>[statusEvent('byHand', now)],
      ),
      2,
    );
  });

  test('a hidden friend is not counted', () {
    expect(count(people: <Person>[person('1', now, hidden: true)]), 0);
  });

  test('records outside the window are left out', () {
    expect(count(people: <Person>[person('1', DateTime(2026, 7, 20))]), 0);
  });

  group('the count cannot be inflated', () {
    // The figure stopped being private the moment it fed the community total
    // and the leaderboard. A number anybody can raise by flipping a status back
    // and forth is not a number worth showing to other people.

    test('the same idea moved twice in one day is one action', () {
      expect(
        count(
          matchStatusEvents: <MatchStatusEvent>[
            matchStatus('there', DateTime(2026, 8, 14, 9)),
            matchStatus('back', DateTime(2026, 8, 14, 17)),
          ],
        ),
        1,
      );
    });

    test('but the same idea moved again the next day is a second action', () {
      expect(
        count(
          matchStatusEvents: <MatchStatusEvent>[
            matchStatus('day1', DateTime(2026, 8, 14, 9)),
            matchStatus('day2', DateTime(2026, 8, 15, 9)),
          ],
        ),
        2,
      );
    });

    test('the same friend moved twice in one day is one action', () {
      expect(
        count(
          events: <PersonEvent>[
            statusEvent('there', DateTime(2026, 8, 14, 9)),
            statusEvent('back', DateTime(2026, 8, 14, 17)),
          ],
        ),
        1,
      );
    });

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
        ),
        1,
      );
    });

    test('two friends who really are different both count', () {
      expect(count(people: <Person>[person('1', now), person('2', now)]), 2);
    });

    test('the same friend added again next month counts again', () {
      // A month apart is not a duplicate; it is somebody re-entered after a
      // restore, or a second real act of adding them.
      Person named(DateTime at) => Person(
        id: at.toIso8601String(),
        firstName: 'יעקב',
        lastName: 'רוזן',
        gender: Gender.male,
        createdAt: at,
        updatedAt: at,
      );

      expect(
        count(
          people: <Person>[
            named(DateTime(2026, 8, 2)),
            named(DateTime(2026, 8, 20)),
          ],
        ),
        2,
      );
    });
  });

  test('the three windows are all counted from the same records', () {
    final ActivityTotals totals = ActivityStats.totals(
      people: <Person>[
        person('recent', now.subtract(const Duration(days: 2))),
        person('old', DateTime(2024, 1, 1)),
      ],
      matches: const <MatchIdea>[],
      matchStatusEvents: const <MatchStatusEvent>[],
      events: const <PersonEvent>[],
      now: now,
    );

    expect(totals.week, 1);
    expect(totals.allTime, 2);
    // "החודש" is the Hebrew month, which begins at Rosh Chodesh — so it is not
    // always the longer window. Two days ago can already belong to the month
    // before, and that is correct rather than a rounding slip.
    expect(totals.allTime, greaterThanOrEqualTo(totals.month));
  });

  /// A file with hundreds of cards in it is real work and counts everywhere.
  /// The single thing it may not do is set the personal weekly record, because
  /// a record nobody can beat stops being encouragement.
  group('a large import counts everywhere except towards the record', () {
    List<Person> batch(String batchId, int size) => <Person>[
      for (int i = 0; i < size; i++)
        person('$batchId-$i', now)..importBatchId = batchId,
    ];

    test('by default every import counts, however large', () {
      expect(count(people: batch('big', 40)), 40);
    });

    test('an import over the limit is dropped when the limit is asked for', () {
      expect(
        ActivityStats.countBetween(
          start: start,
          end: end,
          people: batch('big', 40),
          matches: const <MatchIdea>[],
          matchStatusEvents: const <MatchStatusEvent>[],
          events: const <PersonEvent>[],
          bulkImportLimit: 30,
        ),
        0,
      );
    });

    test('an import at the limit still counts — the rule is *more than*', () {
      expect(
        ActivityStats.countBetween(
          start: start,
          end: end,
          people: batch('exactly', 30),
          matches: const <MatchIdea>[],
          matchStatusEvents: const <MatchStatusEvent>[],
          events: const <PersonEvent>[],
          bulkImportLimit: 30,
        ),
        30,
      );
    });

    test('only the oversized batch goes; hand-added friends stay', () {
      expect(
        ActivityStats.countBetween(
          start: start,
          end: end,
          people: <Person>[
            ...batch('big', 40),
            ...batch('small', 5),
            person('byHand', now),
          ],
          matches: const <MatchIdea>[],
          matchStatusEvents: const <MatchStatusEvent>[],
          events: const <PersonEvent>[],
          bulkImportLimit: 30,
        ),
        6,
      );
    });

    test('a batch clipped by the window is still judged at its full size', () {
      // Thirty-five arrived in one import, five of them inside this window. The
      // batch is a batch of thirty-five, not of five, so none of it may set a
      // record.
      final List<Person> people = <Person>[
        for (int i = 0; i < 30; i++)
          person('outside-$i', DateTime(2024, 5, 5))..importBatchId = 'one',
        for (int i = 0; i < 5; i++)
          person('inside-$i', now)..importBatchId = 'one',
      ];

      expect(
        ActivityStats.countBetween(
          start: start,
          end: end,
          people: people,
          matches: const <MatchIdea>[],
          matchStatusEvents: const <MatchStatusEvent>[],
          events: const <PersonEvent>[],
          bulkImportLimit: 30,
        ),
        0,
      );
    });

    test('weekForRecord is the only figure the limit reaches', () {
      final ActivityTotals totals = ActivityStats.totals(
        people: batch('big', 40),
        matches: const <MatchIdea>[],
        matchStatusEvents: const <MatchStatusEvent>[],
        events: const <PersonEvent>[],
        now: now,
        recordBulkImportLimit: 30,
      );

      expect(totals.week, 40);
      expect(totals.allTime, 40);
      expect(totals.weekForRecord, 0);
    });

    test('weekForRecord equals week when no limit is asked for', () {
      final ActivityTotals totals = ActivityStats.totals(
        people: batch('big', 40),
        matches: const <MatchIdea>[],
        matchStatusEvents: const <MatchStatusEvent>[],
        events: const <PersonEvent>[],
        now: now,
      );

      expect(totals.weekForRecord, totals.week);
    });
  });
}
