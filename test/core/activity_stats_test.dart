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
}
