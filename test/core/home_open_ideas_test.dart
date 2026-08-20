import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_open_ideas.dart';

final DateTime _now = DateTime.now();

Person person({
  required String id,
  ProfileStatus status = ProfileStatus.available,
}) {
  return Person(
    id: id,
    firstName: id,
    lastName: 'כהן',
    gender: id.startsWith('m') ? Gender.male : Gender.female,
    profileStatus: status,
    createdAt: _now,
    updatedAt: _now,
  );
}

MatchIdea idea({
  required String id,
  MatchStatus status = MatchStatus.idea,
  int createdDaysAgo = 1,
  DateTime? reminder,
  String personAId = 'm1',
  String personBId = 'f1',
}) {
  return MatchIdea(
    id: id,
    personAId: personAId,
    personBId: personBId,
    status: status,
    currentHandler: CurrentHandler.me,
    createdAt: _now.subtract(Duration(days: createdDaysAgo)),
    updatedAt: _now.subtract(Duration(days: createdDaysAgo)),
    reminderDate: reminder,
  );
}

bool _isDue(DateTime? date) {
  if (date == null) {
    return false;
  }
  final DateTime today = DateTime(_now.year, _now.month, _now.day);
  return !DateTime(date.year, date.month, date.day).isAfter(today);
}

List<HomeOpenIdea> build(
  List<MatchIdea> matches, {
  Map<String, Person> people = const <String, Person>{},
  Set<String> alerting = const <String>{},
  Map<String, DateTime> reopenedAt = const <String, DateTime>{},
}) {
  return HomeOpenIdeas.build(
    matches: matches,
    personById: (String id) => people[id] ?? person(id: id),
    isAlerting: (MatchIdea match) => alerting.contains(match.id),
    isDue: _isDue,
    reopenedAt: reopenedAt,
  );
}

MatchStatusEvent statusEvent({
  required String matchId,
  required MatchStatus? from,
  required MatchStatus to,
  int daysAgo = 1,
}) {
  return MatchStatusEvent(
    id: '$matchId-$daysAgo-${to.name}',
    matchId: matchId,
    fromStatus: from,
    toStatus: to,
    createdAt: _now.subtract(Duration(days: daysAgo)),
  );
}

void main() {
  test('only proposals that can be moved forward today are shown', () {
    final List<HomeOpenIdea> ideas = build(<MatchIdea>[
      idea(id: 'open'),
      idea(id: 'checking', status: MatchStatus.checking),
      idea(id: 'waiting', status: MatchStatus.unavailable),
      idea(id: 'dating', status: MatchStatus.dating),
      idea(id: 'rejected', status: MatchStatus.rejected),
      idea(id: 'married', status: MatchStatus.married),
    ]);

    expect(ideas.map((HomeOpenIdea i) => i.match.id), <String>[
      'open',
      'checking',
    ]);
  });

  test('a proposal whose side is busy or on a break is not open', () {
    final Map<String, Person> people = <String, Person>{
      'm1': person(id: 'm1'),
      'f1': person(id: 'f1', status: ProfileStatus.onBreak),
      'm2': person(id: 'm2', status: ProfileStatus.busy),
      'f2': person(id: 'f2'),
      'm3': person(id: 'm3'),
      'f3': person(id: 'f3'),
    };

    final List<HomeOpenIdea> ideas = build(<MatchIdea>[
      idea(id: 'paused-her'),
      idea(id: 'paused-him', personAId: 'm2', personBId: 'f2'),
      idea(id: 'both-free', personAId: 'm3', personBId: 'f3'),
    ], people: people);

    expect(ideas.map((HomeOpenIdea i) => i.match.id), <String>['both-free']);
  });

  test('a due reminder leads the row, earliest first', () {
    final List<HomeOpenIdea> ideas = build(<MatchIdea>[
      idea(id: 'newest', createdDaysAgo: 0),
      idea(id: 'due-today', createdDaysAgo: 20, reminder: _now),
      idea(
        id: 'overdue',
        createdDaysAgo: 30,
        reminder: _now.subtract(const Duration(days: 4)),
      ),
      idea(
        id: 'future-reminder',
        createdDaysAgo: 10,
        reminder: _now.add(const Duration(days: 5)),
      ),
    ]);

    expect(ideas.map((HomeOpenIdea i) => i.match.id), <String>[
      'overdue',
      'due-today',
      'newest',
      'future-reminder',
    ]);
  });

  test('the badge follows the alert, not the reminder alone', () {
    final List<HomeOpenIdea> ideas = build(
      <MatchIdea>[
        idea(id: 'unseen', reminder: _now),
        idea(id: 'seen', reminder: _now, createdDaysAgo: 2),
      ],
      alerting: <String>{'unseen'},
    );

    expect(
      ideas.firstWhere((HomeOpenIdea i) => i.match.id == 'unseen').alerting,
      isTrue,
    );
    expect(
      ideas.firstWhere((HomeOpenIdea i) => i.match.id == 'seen').alerting,
      isFalse,
    );
  });

  test('a reopened proposal leads the row behind the due reminders', () {
    final List<HomeOpenIdea> ideas = build(
      <MatchIdea>[
        idea(id: 'newest', createdDaysAgo: 0),
        idea(id: 'reopened', createdDaysAgo: 40),
        idea(id: 'due', createdDaysAgo: 50, reminder: _now),
        idea(id: 'plain', createdDaysAgo: 5),
      ],
      reopenedAt: <String, DateTime>{
        'reopened': _now.subtract(const Duration(days: 2)),
      },
    );

    expect(ideas.map((HomeOpenIdea i) => i.match.id), <String>[
      'due',
      'reopened',
      'newest',
      'plain',
    ]);
  });

  test('coming back to an open status counts as reopening, recently', () {
    final Map<String, DateTime> reopened = HomeOpenIdeas.reopenedFromEvents(
      statusEvents: <MatchStatusEvent>[
        statusEvent(
          matchId: 'off-hold',
          from: MatchStatus.unavailable,
          to: MatchStatus.idea,
          daysAgo: 3,
        ),
        statusEvent(
          matchId: 'reconsidered',
          from: MatchStatus.rejected,
          to: MatchStatus.checking,
          daysAgo: 1,
        ),
        statusEvent(
          matchId: 'moved-along',
          from: MatchStatus.idea,
          to: MatchStatus.checking,
          daysAgo: 1,
        ),
        statusEvent(
          matchId: 'long-ago',
          from: MatchStatus.unavailable,
          to: MatchStatus.idea,
          daysAgo: 200,
        ),
      ],
      now: _now,
    );

    expect(reopened.keys.toSet(), <String>{'off-hold', 'reconsidered'});
  });

  test('the row is capped when a limit is given', () {
    final List<HomeOpenIdea> ideas = HomeOpenIdeas.build(
      matches: <MatchIdea>[
        for (int i = 0; i < 8; i++) idea(id: 'm$i', createdDaysAgo: i),
      ],
      personById: (String id) => person(id: id),
      isAlerting: (MatchIdea match) => false,
      isDue: _isDue,
      limit: 3,
    );

    expect(ideas, hasLength(3));
  });
}
