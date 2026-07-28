import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_suggestions.dart';

Person person({
  required String id,
  required String firstName,
  Gender gender = Gender.male,
  ProfileStatus status = ProfileStatus.available,
  int createdDaysAgo = 200,
  int updatedDaysAgo = 200,
  bool hidden = false,
  bool needsReview = false,
}) {
  final DateTime now = DateTime.now();
  return Person(
    id: id,
    firstName: firstName,
    lastName: 'כהן',
    gender: gender,
    profileStatus: status,
    hidden: hidden,
    needsReview: needsReview,
    createdAt: now.subtract(Duration(days: createdDaysAgo)),
    updatedAt: now.subtract(Duration(days: updatedDaysAgo)),
  );
}

MatchIdea idea({
  required String id,
  required String personAId,
  required String personBId,
  MatchStatus status = MatchStatus.idea,
  int createdDaysAgo = 1,
}) {
  final DateTime now = DateTime.now();
  return MatchIdea(
    id: id,
    personAId: personAId,
    personBId: personBId,
    status: status,
    currentHandler: CurrentHandler.me,
    createdAt: now.subtract(Duration(days: createdDaysAgo)),
    updatedAt: now.subtract(Duration(days: createdDaysAgo)),
  );
}

void main() {
  test('someone with no idea for a long time leads the row', () {
    final Person forgotten = person(id: 'a', firstName: 'אבי');
    final Person busyLately = person(
      id: 'b',
      firstName: 'בני',
      gender: Gender.female,
    );

    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[busyLately, forgotten],
      matches: <MatchIdea>[
        idea(id: 'm1', personAId: 'b', personBId: 'z'),
      ],
    );

    expect(suggestions.first.person.id, 'a');
    expect(suggestions.first.reason, 'לא חשבת עליו לאחרונה');
  });

  test('the reason is worded for the person’s gender', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(id: 'a', firstName: 'שירה', gender: Gender.female),
      ],
      matches: const <MatchIdea>[],
    );

    expect(suggestions.single.reason, 'לא חשבת עליה לאחרונה');
  });

  test('a newcomer is surfaced as newly added, not as neglected', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(
          id: 'a',
          firstName: 'דני',
          createdDaysAgo: 2,
          updatedDaysAgo: 2,
        ),
      ],
      matches: const <MatchIdea>[],
    );

    expect(suggestions.single.reason, 'נוסף למאגר לאחרונה');
  });

  test('an archived idea does not count as an open one', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי')],
      matches: <MatchIdea>[
        idea(
          id: 'm1',
          personAId: 'a',
          personBId: 'z',
          status: MatchStatus.rejected,
          createdDaysAgo: HomeConfig.notThoughtAboutAfterDays + 10,
        ),
      ],
    );

    expect(suggestions.single.reason, 'לא חשבת עליו לאחרונה');
  });

  test('hidden, pending, paused and archived people are left out', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(id: 'a', firstName: 'א', hidden: true),
        person(id: 'b', firstName: 'ב', needsReview: true),
        person(id: 'c', firstName: 'ג', status: ProfileStatus.busy),
        person(id: 'd', firstName: 'ד', status: ProfileStatus.onBreak),
        person(id: 'e', firstName: 'ה', status: ProfileStatus.mazelTov),
        person(id: 'f', firstName: 'ו', gender: Gender.unknown),
      ],
      matches: const <MatchIdea>[],
    );

    expect(suggestions, isEmpty);
  });

  test('the row is capped at the configured length', () {
    final List<Person> many = <Person>[
      for (int i = 0; i < HomeConfig.worthThinkingCount + 8; i++)
        person(id: 'p$i', firstName: 'שם $i'),
    ];

    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: many,
      matches: const <MatchIdea>[],
    );

    expect(suggestions.length, HomeConfig.worthThinkingCount);
  });
}
