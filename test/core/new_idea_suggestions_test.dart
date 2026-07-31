import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';

Person person({
  required String id,
  required String firstName,
  required Gender gender,
  int? age,
  ReligiousLevel? level,
  String? city,
  ProfileStatus status = ProfileStatus.available,
  bool hidden = false,
  bool needsReview = false,
}) {
  final DateTime now = DateTime.now();
  final Person result = Person(
    id: id,
    firstName: firstName,
    lastName: 'לוי',
    gender: gender,
    religiousLevel: level,
    city: city,
    profileStatus: status,
    hidden: hidden,
    needsReview: needsReview,
    createdAt: now,
    updatedAt: now,
  );
  result.setManualAge(age);
  return result;
}

MatchIdea idea({
  required String id,
  required String personAId,
  required String personBId,
  MatchStatus status = MatchStatus.idea,
}) {
  final DateTime now = DateTime.now();
  return MatchIdea(
    id: id,
    personAId: personAId,
    personBId: personBId,
    status: status,
    currentHandler: CurrentHandler.me,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('a fitting pair from the database becomes an idea', () {
    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: <Person>[
        person(
          id: 'm',
          firstName: 'אריאל',
          gender: Gender.male,
          age: 27,
          level: ReligiousLevel.datiLeumi,
          city: 'ירושלים',
        ),
        person(
          id: 'f',
          firstName: 'אסתר',
          gender: Gender.female,
          age: 24,
          level: ReligiousLevel.datiLeumi,
          city: 'ירושלים',
        ),
      ],
      matches: const <MatchIdea>[],
    );

    expect(ideas, hasLength(1));
    expect(ideas.single.male.id, 'm');
    expect(ideas.single.female.id, 'f');
    expect(ideas.single.reasons, contains('לשניהם אין רעיון פתוח'));
    expect(ideas.single.reasons, contains('אותה השקפה · דתי לאומי'));
  });

  test('a pair that already has any proposal is never offered again', () {
    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: <Person>[
        person(id: 'm', firstName: 'אריאל', gender: Gender.male),
        person(id: 'f', firstName: 'אסתר', gender: Gender.female),
      ],
      matches: <MatchIdea>[
        idea(
          id: 'x',
          personAId: 'f',
          personBId: 'm',
          status: MatchStatus.rejected,
        ),
      ],
    );

    expect(ideas, isEmpty);
  });

  test('a pair the matchmaker pushed aside stays away', () {
    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: <Person>[
        person(id: 'm', firstName: 'אריאל', gender: Gender.male),
        person(id: 'f', firstName: 'אסתר', gender: Gender.female),
      ],
      matches: const <MatchIdea>[],
      dismissedFor: (String personId) =>
          personId == 'm' ? <String>{'f'} : <String>{},
    );

    expect(ideas, isEmpty);
  });

  test('incompatible religious styles are not paired', () {
    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: <Person>[
        person(
          id: 'm',
          firstName: 'אריאל',
          gender: Gender.male,
          level: ReligiousLevel.haredi,
        ),
        person(
          id: 'f',
          firstName: 'אסתר',
          gender: Gender.female,
          level: ReligiousLevel.hiloni,
        ),
      ],
      matches: const <MatchIdea>[],
    );

    expect(ideas, isEmpty);
  });

  test('paused, hidden and pending people are left out', () {
    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: <Person>[
        person(id: 'm', firstName: 'אריאל', gender: Gender.male),
        person(
          id: 'f1',
          firstName: 'אסתר',
          gender: Gender.female,
          status: ProfileStatus.busy,
        ),
        person(
          id: 'f2',
          firstName: 'רותי',
          gender: Gender.female,
          hidden: true,
        ),
        person(
          id: 'f3',
          firstName: 'תמר',
          gender: Gender.female,
          needsReview: true,
        ),
      ],
      matches: const <MatchIdea>[],
    );

    expect(ideas, isEmpty);
  });

  test('no single person is allowed to fill the whole screen', () {
    final List<Person> people = <Person>[
      person(id: 'm', firstName: 'אריאל', gender: Gender.male),
      for (int i = 0; i < 8; i++)
        person(id: 'f$i', firstName: 'מועמדת $i', gender: Gender.female),
    ];

    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: people,
      matches: const <MatchIdea>[],
    );

    expect(ideas, hasLength(NewIdeaSuggestions.maxPairsPerPerson));
  });
}
