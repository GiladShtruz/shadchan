import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
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
  int? updatedDaysAgo,
}) {
  final DateTime now = DateTime.now();
  return MatchIdea(
    id: id,
    personAId: personAId,
    personBId: personBId,
    status: status,
    currentHandler: CurrentHandler.me,
    createdAt: now.subtract(Duration(days: createdDaysAgo)),
    updatedAt: now.subtract(Duration(days: updatedDaysAgo ?? createdDaysAgo)),
  );
}

PersonEvent statusEvent({
  required String personId,
  required ProfileStatus to,
  required int daysAgo,
}) {
  return PersonEvent(
    id: '$personId-${to.name}-$daysAgo',
    personId: personId,
    type: PersonEventType.statusChanged,
    text: 'הסטטוס שונה ל־${to.displayName}',
    createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
  );
}

void main() {
  test('someone who was never proposed to is told exactly that', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי')],
      matches: const <MatchIdea>[],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.noIdeaYet);
    expect(suggestions.single.reason, 'עוד לא נפתח לו רעיון — אולי זה הזמן');
  });

  test('the reason is worded for the person’s gender', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(id: 'a', firstName: 'שירה', gender: Gender.female),
      ],
      matches: const <MatchIdea>[],
    );

    expect(suggestions.single.reason, 'עוד לא נפתח לה רעיון — אולי זה הזמן');
  });

  test('a newcomer is surfaced as new in the database', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(id: 'a', firstName: 'דני', createdDaysAgo: 2, updatedDaysAgo: 2),
      ],
      matches: const <MatchIdea>[],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.newInDatabase);
    expect(suggestions.single.reason, 'חדש במאגר — שווה להתחיל לחשוב עליו');
  });

  test('a long silence after the last idea reads as neglect', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי')],
      matches: <MatchIdea>[
        idea(
          id: 'm1',
          personAId: 'a',
          personBId: 'z',
          status: MatchStatus.rejected,
          createdDaysAgo: 300,
          updatedDaysAgo: 300,
        ),
      ],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.notThoughtAbout);
    expect(
      suggestions.single.reason,
      'לא חשבת עליו לאחרונה — אולי הגיע הזמן לכיוון חדש',
    );
  });

  test('a proposal that just closed is the news about that person', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי')],
      matches: <MatchIdea>[
        idea(
          id: 'm1',
          personAId: 'a',
          personBId: 'z',
          status: MatchStatus.rejected,
          createdDaysAgo: 60,
          updatedDaysAgo: 20,
        ),
      ],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.lastIdeaClosed);
    expect(
      suggestions.single.reason,
      'הרעיון האחרון נסגר — אולי מתאים עכשיו כיוון חדש',
    );
  });

  test('coming back from a break beats every other reason', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(id: 'a', firstName: 'אבי', createdDaysAgo: 2, updatedDaysAgo: 1),
      ],
      matches: const <MatchIdea>[],
      events: <PersonEvent>[
        statusEvent(personId: 'a', to: ProfileStatus.onBreak, daysAgo: 30),
        statusEvent(personId: 'a', to: ProfileStatus.available, daysAgo: 1),
      ],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.returnedToAvailable);
    expect(suggestions.single.reason, 'חזר להיות פנוי — שווה לחשוב עליו מחדש');
  });

  test('a person who is simply available is never said to have returned', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי')],
      matches: const <MatchIdea>[],
    );

    expect(
      suggestions.single.kind,
      isNot(HomeSuggestionReason.returnedToAvailable),
    );
  });

  test('candidates found in the database are counted, not guessed', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[
        person(id: 'a', firstName: 'אבי'),
        person(id: 'b', firstName: 'רותי', gender: Gender.female),
        person(id: 'c', firstName: 'שירה', gender: Gender.female),
        person(id: 'd', firstName: 'תמר', gender: Gender.female),
      ],
      matches: const <MatchIdea>[],
    );

    final HomeSuggestion first = suggestions.first;
    expect(first.person.id, 'a');
    expect(first.kind, HomeSuggestionReason.matchesFound);
    expect(first.reason, 'יש במאגר 3 אנשים שעשויים להתאים לו');
  });

  test('open proposals are described with their real count', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי', updatedDaysAgo: 30)],
      matches: <MatchIdea>[
        idea(id: 'm1', personAId: 'a', personBId: 'y'),
        idea(id: 'm2', personAId: 'a', personBId: 'z'),
      ],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.severalOpenIdeas);
    expect(
      suggestions.single.reason,
      'יש לו כבר 2 רעיונות פתוחים — שווה לבדוק מה מתקדם',
    );
  });

  test('open proposals nobody touched are the ones waiting for an update', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי', updatedDaysAgo: 30)],
      matches: <MatchIdea>[
        idea(id: 'm1', personAId: 'a', personBId: 'y', createdDaysAgo: 40),
      ],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.openIdeasWaiting);
    expect(
      suggestions.single.reason,
      'הרעיונות שלו מחכים לעדכון — אולי הגיע הזמן לקדם',
    );
  });

  test('a hand-edited card is reported as new details', () {
    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: <Person>[person(id: 'a', firstName: 'אבי', updatedDaysAgo: 30)],
      matches: <MatchIdea>[
        idea(id: 'm1', personAId: 'a', personBId: 'y', createdDaysAgo: 40),
      ],
      activity: <HomeActivityEntry>[
        HomeActivityEntry(
          kind: HomeItemKind.person,
          targetId: 'a',
          action: HomeActivityAction.editedDetails,
          at: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ],
    );

    expect(suggestions.single.kind, HomeSuggestionReason.detailsAdded);
    expect(
      suggestions.single.reason,
      'נוספו פרטים חדשים — אולי הם יפתחו כיוון מתאים',
    );
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
