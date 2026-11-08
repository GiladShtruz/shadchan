import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/weekly_pace.dart';

/// Weeks are given newest first: index 0 is this week so far, 1 last week.
Map<PaceMetric, List<int>> history({
  List<int> friends = const <int>[0, 0, 0, 0, 0, 0, 0, 0, 0],
  List<int> ideas = const <int>[0, 0, 0, 0, 0, 0, 0, 0, 0],
  List<int> updates = const <int>[0, 0, 0, 0, 0, 0, 0, 0, 0],
  List<int> actions = const <int>[0, 0, 0, 0, 0, 0, 0, 0, 0],
}) => <PaceMetric, List<int>>{
  PaceMetric.friends: friends,
  PaceMetric.ideas: ideas,
  PaceMetric.ideaUpdates: updates,
  PaceMetric.actions: actions,
};

void main() {
  group('WeeklyPaces.choose', () {
    test('last week, plus one, is the bar when it is the best week', () {
      final WeeklyPace pace = WeeklyPaces.choose(
        history: history(friends: <int>[2, 4, 1, 0, 3, 0, 0, 0, 0]),
        weekNumber: 0,
      );
      expect(pace.metric, PaceMetric.friends);
      expect(pace.mode, PaceMode.lastWeek);
      expect(pace.target, 5);
      expect(pace.done, 2);
      expect(
        pace.headline(Gender.male),
        'בשבוע שעבר הוספת 4 חברים. השבוע שוברים את השיא?',
      );
    });

    test('a record within reach is the bar, in the record wording', () {
      final WeeklyPace pace = WeeklyPaces.choose(
        history: history(ideas: <int>[2, 1, 3, 0, 2, 0, 0, 0, 0]),
        weekNumber: 0,
      );
      expect(pace.metric, PaceMetric.ideas);
      expect(pace.mode, PaceMode.record);
      expect(pace.reference, 3);
      expect(pace.target, 4);
      expect(
        pace.headline(Gender.male),
        'השיא שלך הוא 3 רעיונות בשבוע. בוא נעבור אותו.',
      );
      expect(pace.headline(Gender.female), contains('בואי נעבור'));
    });

    test('a bulk import never becomes the bar', () {
      final WeeklyPace pace = WeeklyPaces.choose(
        // 250 friends imported once; a normal pace of 2–3.
        history: history(friends: <int>[0, 2, 250, 3, 0, 0, 0, 0, 0]),
        weekNumber: 0,
      );
      expect(pace.reference, lessThanOrEqualTo(PaceMetric.friends.ceiling));
      expect(pace.target, 4);
    });

    test('with too little history there is no record claimed', () {
      final WeeklyPace pace = WeeklyPaces.choose(
        history: history(actions: <int>[1, 0, 0, 0, 0, 0, 0, 0, 5]),
        weekNumber: 3,
      );
      expect(pace.mode, PaceMode.starter);
      expect(pace.target, WeeklyPaces.starterTarget);
      expect(pace.done, 1);
      expect(pace.headline(Gender.male), isNot(contains('שיא')));
    });

    test('the metric turns with the week, among those with history', () {
      final Map<PaceMetric, List<int>> h = history(
        friends: <int>[0, 3, 2, 0, 0, 0, 0, 0, 0],
        ideas: <int>[0, 2, 1, 0, 0, 0, 0, 0, 0],
      );
      final Set<PaceMetric> seen = <PaceMetric>{
        for (int week = 0; week < 4; week++)
          WeeklyPaces.choose(history: h, weekNumber: week).metric,
      };
      expect(seen, <PaceMetric>{PaceMetric.friends, PaceMetric.ideas});
      // And it stays put for the whole week.
      expect(
        WeeklyPaces.choose(history: h, weekNumber: 7).metric,
        WeeklyPaces.choose(history: h, weekNumber: 7).metric,
      );
    });

    test('reaching the target says so and keeps counting', () {
      final WeeklyPace pace = WeeklyPaces.choose(
        history: history(friends: <int>[7, 4, 2, 0, 0, 0, 0, 0, 0]),
        weekNumber: 0,
      );
      expect(pace.reached, isTrue);
      expect(pace.done, 7);
      expect(pace.progress, 1);
      expect(pace.headline(Gender.male), 'שברת את השיא האישי שלך 🎉');
    });
  });

  group('WeeklyPaces.history', () {
    final DateTime weekStart = DateTime(2026, 11, 8); // a Sunday
    final DateTime now = DateTime(2026, 11, 10, 12);

    Person person(String id, DateTime createdAt, {bool hidden = false}) =>
        Person(
          id: id,
          firstName: 'שם$id',
          lastName: 'משפחה',
          gender: Gender.male,
          createdAt: createdAt,
          updatedAt: createdAt,
          hidden: hidden,
        );

    test('counts each week apart, newest first', () {
      final Map<PaceMetric, List<int>> h = WeeklyPaces.history(
        weekStart: weekStart,
        now: now,
        people: <Person>[
          person('a', DateTime(2026, 11, 9)), // this week
          person('b', DateTime(2026, 11, 3)), // last week
          person('c', DateTime(2026, 11, 4)), // last week
          person('d', DateTime(2026, 10, 27)), // two weeks back
          person('e', DateTime(2026, 11, 4), hidden: true), // not counted
        ],
        matches: <MatchIdea>[
          MatchIdea(
            id: 'm1',
            personAId: 'a',
            personBId: 'b',
            status: MatchStatus.idea,
            currentHandler: CurrentHandler.me,
            createdAt: DateTime(2026, 11, 2, 10),
            updatedAt: DateTime(2026, 11, 2, 10),
          ),
        ],
        statusEvents: <MatchStatusEvent>[
          MatchStatusEvent(
            id: 'e1',
            matchId: 'm1',
            fromStatus: MatchStatus.idea,
            toStatus: MatchStatus.checking,
            createdAt: DateTime(2026, 11, 9, 9),
          ),
          // What the app did by itself is not an update.
          MatchStatusEvent(
            id: 'e2',
            matchId: 'm1',
            fromStatus: MatchStatus.checking,
            toStatus: MatchStatus.unavailable,
            createdAt: DateTime(2026, 11, 9, 10),
            automatic: true,
          ),
        ],
        notes: <MatchNote>[
          MatchNote(
            id: 'n1',
            matchId: 'm1',
            text: 'דיברתי עם אמא שלו',
            createdAt: DateTime(2026, 11, 9, 11), // same idea, same day
            isAutomatic: false,
          ),
        ],
      );
      expect(h[PaceMetric.friends]!.take(3), <int>[1, 2, 1]);
      expect(h[PaceMetric.ideas]!.take(2), <int>[0, 1]);
      expect(h[PaceMetric.ideaUpdates]!.take(2), <int>[1, 0]);
      expect(h[PaceMetric.actions]!.take(2), <int>[2, 3]);
      expect(h[PaceMetric.friends]!.length, WeeklyPaces.historyWeeks + 1);
    });
  });
}
