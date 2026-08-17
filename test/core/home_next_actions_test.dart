import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_next_actions.dart';

/// "הפעולות הבאות שלך" is the app's own reading of the database, and the whole
/// value of it is the *order*. A list that puts a card nobody has edited in
/// eight months above a reminder that came due this morning is worse than no
/// list at all, so the ranking is asserted here rather than left to whatever
/// order the records happen to come back in.
void main() {
  final DateTime now = DateTime(2026, 8, 14);

  Person person({
    required String id,
    Gender gender = Gender.male,
    DateTime? created,
    DateTime? updated,
    int? age = 27,
    ReligiousLevel? level = ReligiousLevel.datiLeumi,
    MaritalStatus? marital = MaritalStatus.single,
    Region? region = Region.center,
    ProfileStatus status = ProfileStatus.available,
  }) {
    return Person(
      id: id,
      firstName: 'שם$id',
      lastName: 'משפחה',
      gender: gender,
      manualAge: age,
      religiousLevel: level,
      maritalStatus: marital,
      region: region,
      profileStatus: status,
      createdAt: created ?? now.subtract(const Duration(days: 200)),
      updatedAt: updated ?? now,
    );
  }

  MatchIdea match({
    required String id,
    required String a,
    required String b,
    MatchStatus status = MatchStatus.idea,
    DateTime? updated,
    DateTime? reminder,
    String? reminderNote,
  }) {
    return MatchIdea(
      id: id,
      personAId: a,
      personBId: b,
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: now.subtract(const Duration(days: 300)),
      updatedAt: updated ?? now,
      reminderDate: reminder,
      reminderNote: reminderNote,
    );
  }

  List<HomeNextAction> build({
    List<Person> people = const <Person>[],
    List<MatchIdea> matches = const <MatchIdea>[],
    DateTime? Function(String id)? reminders,
  }) {
    final Map<String, Person> byId = <String, Person>{
      for (final Person p in people) p.id: p,
    };
    return HomeNextActions.build(
      people: people,
      matches: matches,
      personById: (String id) => byId[id],
      personReminder: reminders,
      now: now,
    );
  }

  test('a due reminder outranks everything the app worked out itself', () {
    final Person a = person(id: 'a');
    final Person b = person(id: 'b', gender: Gender.female);
    final List<HomeNextAction> actions = build(
      people: <Person>[a, b],
      matches: <MatchIdea>[
        // Idle for months — a strong reason, but not a dated one.
        match(
          id: 'stale',
          a: 'a',
          b: 'b',
          updated: now.subtract(const Duration(days: 200)),
        ),
      ],
      reminders: (String id) =>
          id == 'b' ? now.subtract(const Duration(days: 1)) : null,
    );

    expect(actions.first.kind, HomeActionKind.reminderDue);
    expect(actions.first.person?.id, 'b');
  });

  test('a reminder that has not arrived yet is not an action', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[person(id: 'a')],
      reminders: (String id) => now.add(const Duration(days: 3)),
    );
    expect(
      actions.where((HomeNextAction a) => a.kind == HomeActionKind.reminderDue),
      isEmpty,
    );
  });

  test('a couple out for about a month is asked after', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(id: 'a'),
        person(id: 'b', gender: Gender.female),
      ],
      matches: <MatchIdea>[
        match(
          id: 'm',
          a: 'a',
          b: 'b',
          status: MatchStatus.dating,
          updated: now.subtract(const Duration(days: 31)),
        ),
      ],
    );
    final HomeNextAction dating = actions.firstWhere(
      (HomeNextAction a) => a.kind == HomeActionKind.datingCheckIn,
    );
    expect(dating.reason, contains('יוצאים כבר'));
    expect(dating.match?.id, 'm');
  });

  test('a couple who started dating this week is left alone', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(id: 'a'),
        person(id: 'b', gender: Gender.female),
      ],
      matches: <MatchIdea>[
        match(
          id: 'm',
          a: 'a',
          b: 'b',
          status: MatchStatus.dating,
          updated: now.subtract(const Duration(days: 3)),
        ),
      ],
    );
    expect(actions.where((HomeNextAction a) => a.match?.id == 'm'), isEmpty);
  });

  test(
    'an old card missing the newer fields names exactly what is missing',
    () {
      final List<HomeNextAction> actions = build(
        people: <Person>[
          person(
            id: 'old',
            created: now.subtract(const Duration(days: 400)),
            age: null,
            level: null,
          ),
        ],
      );
      final HomeNextAction missing = actions.firstWhere(
        (HomeNextAction a) => a.kind == HomeActionKind.missingDetails,
      );
      expect(missing.reason, contains('גיל'));
      expect(missing.reason, contains('סגנון דתי'));
    },
  );

  test('a missing marital status or region is not worth asking about', () {
    // These are not basics. Plenty of perfectly usable cards never carry
    // either, and treating them as gaps turned this row into a list of the
    // whole database.
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(
          id: 'old',
          created: now.subtract(const Duration(days: 400)),
          marital: null,
          region: null,
        ),
      ],
    );
    expect(
      actions.where(
        (HomeNextAction a) => a.kind == HomeActionKind.missingDetails,
      ),
      isEmpty,
    );
  });

  test('a card added this week is unfinished, not neglected', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(
          id: 'new',
          created: now.subtract(const Duration(days: 2)),
          marital: null,
          region: null,
        ),
      ],
    );
    expect(
      actions.where(
        (HomeNextAction a) => a.kind == HomeActionKind.missingDetails,
      ),
      isEmpty,
    );
  });

  test('every action carries a title and a reason', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(id: 'a'),
        person(id: 'b', gender: Gender.female),
        person(
          id: 'c',
          updated: now.subtract(const Duration(days: 300)),
          gender: Gender.female,
        ),
      ],
      matches: <MatchIdea>[
        match(
          id: 'm',
          a: 'a',
          b: 'b',
          updated: now.subtract(const Duration(days: 40)),
        ),
      ],
    );

    expect(actions, isNotEmpty);
    for (final HomeNextAction action in actions) {
      expect(action.title.trim(), isNotEmpty, reason: action.id);
      expect(action.reason.trim(), isNotEmpty, reason: action.id);
    }
  });

  test('the same database always ranks the same way', () {
    final List<Person> people = <Person>[
      for (int i = 0; i < 12; i++)
        person(id: '$i', gender: i.isEven ? Gender.male : Gender.female),
    ];
    List<String> ids() =>
        build(people: people).map((HomeNextAction a) => a.id).toList();

    expect(ids(), equals(ids()));
  });

  test('an archived person is never an action', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[person(id: 'gone', status: ProfileStatus.mazelTov)],
    );
    expect(
      actions.where((HomeNextAction a) => a.person?.id == 'gone'),
      isEmpty,
    );
  });

  // --- the mix ------------------------------------------------------------

  test('the kinds are dealt out one at a time, not in blocks', () {
    // Three stale proposals and three friends with nothing open. Sorting purely
    // by kind would put all three proposals first and only then reach the
    // people, which reads as two lists glued together — and means the second
    // one is never seen.
    final List<Person> paired = <Person>[
      for (final String id in <String>['a', 'b', 'c', 'd', 'e', 'f'])
        person(id: id),
    ];
    final List<Person> lonely = <Person>[
      for (final String id in <String>['g', 'h', 'i']) person(id: id),
    ];
    final List<HomeNextAction> actions = build(
      people: <Person>[...paired, ...lonely],
      matches: <MatchIdea>[
        match(
          id: 'm1',
          a: 'a',
          b: 'b',
          updated: now.subtract(const Duration(days: 60)),
        ),
        match(
          id: 'm2',
          a: 'c',
          b: 'd',
          updated: now.subtract(const Duration(days: 50)),
        ),
        match(
          id: 'm3',
          a: 'e',
          b: 'f',
          updated: now.subtract(const Duration(days: 40)),
        ),
      ],
    );

    final List<HomeActionKind> kinds = actions
        .map((HomeNextAction a) => a.kind)
        .toList();
    expect(
      kinds.where((HomeActionKind k) => k == HomeActionKind.staleIdea),
      hasLength(3),
    );
    expect(
      kinds.where((HomeActionKind k) => k == HomeActionKind.noIdeas),
      hasLength(3),
    );
    // At least one friend appears before the last proposal does.
    expect(
      kinds.indexOf(HomeActionKind.noIdeas),
      lessThan(kinds.lastIndexOf(HomeActionKind.staleIdea)),
    );
  });

  test(
    'due reminders still lead the whole list, however mixed the rest is',
    () {
      final List<HomeNextAction> actions = build(
        people: <Person>[
          person(id: 'a'),
          person(id: 'b', gender: Gender.female),
          person(id: 'c'),
        ],
        matches: <MatchIdea>[
          match(
            id: 'm',
            a: 'a',
            b: 'b',
            updated: now.subtract(const Duration(days: 90)),
          ),
        ],
        reminders: (String id) =>
            id == 'c' ? now.subtract(const Duration(days: 2)) : null,
      );

      expect(actions.first.kind, HomeActionKind.reminderDue);
      expect(
        actions
            .skip(1)
            .where((HomeNextAction a) => a.kind == HomeActionKind.reminderDue),
        isEmpty,
      );
    },
  );

  // --- the quiet-stretch prompts ------------------------------------------

  test('a week without a friend or an idea is itself an action', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(id: 'a', created: now.subtract(const Duration(days: 40))),
        person(id: 'b', created: now.subtract(const Duration(days: 30))),
      ],
    );

    final HomeNextAction friends = actions.firstWhere(
      (HomeNextAction a) => a.kind == HomeActionKind.addFriendNudge,
    );
    final HomeNextAction ideas = actions.firstWhere(
      (HomeNextAction a) => a.kind == HomeActionKind.newIdeaNudge,
    );
    expect(friends.reason, 'כבר שבוע לא הוספת חבר למאגר');
    expect(ideas.reason, 'כבר שבוע לא חשבת על רעיון חדש');
    // Neither has a record behind it, so the screen routes them by kind.
    expect(friends.isPrompt, isTrue);
    expect(ideas.isPrompt, isTrue);
    expect(friends.person, isNull);
    expect(friends.match, isNull);
  });

  test('a friend added this week silences the friends prompt', () {
    final List<HomeNextAction> actions = build(
      people: <Person>[
        person(id: 'a', created: now.subtract(const Duration(days: 40))),
        person(id: 'b', created: now.subtract(const Duration(days: 2))),
      ],
    );
    expect(
      actions.where(
        (HomeNextAction a) => a.kind == HomeActionKind.addFriendNudge,
      ),
      isEmpty,
    );
  });

  test('an idea opened this week silences the ideas prompt', () {
    final List<Person> people = <Person>[
      person(id: 'a', created: now.subtract(const Duration(days: 40))),
      person(id: 'b', created: now.subtract(const Duration(days: 40))),
    ];
    final Map<String, Person> byId = <String, Person>{
      for (final Person p in people) p.id: p,
    };
    final List<HomeNextAction> actions = HomeNextActions.build(
      people: people,
      matches: <MatchIdea>[
        MatchIdea(
          id: 'fresh',
          personAId: 'a',
          personBId: 'b',
          status: MatchStatus.idea,
          currentHandler: CurrentHandler.me,
          createdAt: now.subtract(const Duration(days: 1)),
          updatedAt: now,
        ),
      ],
      personById: (String id) => byId[id],
      now: now,
    );
    expect(
      actions.where(
        (HomeNextAction a) => a.kind == HomeActionKind.newIdeaNudge,
      ),
      isEmpty,
    );
  });

  test('an empty database is never told off for a quiet week', () {
    // "You have not added a friend in a week" to somebody with no friends is
    // not a nudge, it is a scolding for not having started.
    expect(build(), isEmpty);
  });
}
