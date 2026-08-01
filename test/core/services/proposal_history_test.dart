import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// What a proposal writes into each candidate's own history: opening it,
/// closing it, and why it closed — the "why" deliberately on its own line so
/// the history reads as separate events rather than one long sentence.
void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;
  late Box<PersonEvent> events;
  late PersonRepository personRepository;
  late MatchRepository matchRepository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('proposal_history_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(MatchStatusAdapter());
    Hive.registerAdapter(CurrentHandlerAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    Hive.registerAdapter(MaritalStatusAdapter());
    Hive.registerAdapter(MatchProgressAdapter());
    Hive.registerAdapter(PersonEventAdapter());
    Hive.registerAdapter(PersonEventTypeAdapter());
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    people = await Hive.openBox<Person>('people');
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    events = await Hive.openBox<PersonEvent>('person_events');
    await people.clear();
    await matches.clear();
    await notes.clear();
    await events.clear();
    await Hive.box<dynamic>('settings').clear();

    personRepository = PersonRepository(people, null, events);
    matchRepository = MatchRepository(matches, notes)
      ..resolvePerson = personRepository.getById
      ..logPersonEvent = personRepository.logEvent;
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  /// Oldest first — the reverse of the profile feed, so the expectations below
  /// read in the order the events actually happened.
  List<String> historyFor(String personId) {
    final List<PersonEvent> matching = events.values
        .where((PersonEvent event) => event.personId == personId)
        .toList();
    matching.sort(
      (PersonEvent a, PersonEvent b) => a.createdAt.compareTo(b.createdAt),
    );
    return matching.map((PersonEvent event) => event.text).toList();
  }

  Future<MatchIdea> openProposal() async {
    final DateTime now = DateTime(2026, 7, 27);
    await people.put('him', _person('him', 'אליהו', Gender.male, now));
    await people.put('her', _person('her', 'שושנה', Gender.female, now));
    final MatchIdea? match = await matchRepository.create('him', 'her');
    return match!;
  }

  test('opening a proposal is recorded on both candidates', () async {
    await openProposal();

    expect(historyFor('him'), <String>['נפתחה הצעה עם שושנה']);
    expect(historyFor('her'), <String>['נפתחה הצעה עם אליהו']);
  });

  test(
    'closing records the closing and the reason on separate lines',
    () async {
      final MatchIdea match = await openProposal();

      await matchRepository.recordOutcome(
        match.id,
        newStatus: MatchStatus.rejected,
        party: MatchOutcomeParty.her,
        note: 'הוא תורני מדי עבורה',
      );

      // On his page the other side is named and the reason follows it.
      expect(historyFor('him'), <String>[
        'נפתחה הצעה עם שושנה',
        'נסגרה הצעה עם שושנה',
        'שושנה דחתה כי הוא תורני מדי עבורה',
      ]);
      // On hers the same closing, phrased from her side.
      expect(historyFor('her'), <String>[
        'נפתחה הצעה עם אליהו',
        'נסגרה הצעה עם אליהו',
        'דחתה כי הוא תורני מדי עבורה',
      ]);
    },
  );

  test('without a reason the closing line still stands on its own', () async {
    final MatchIdea match = await openProposal();

    await matchRepository.recordOutcome(
      match.id,
      newStatus: MatchStatus.rejected,
      party: MatchOutcomeParty.him,
    );

    expect(historyFor('him'), <String>[
      'נפתחה הצעה עם שושנה',
      'נסגרה הצעה עם שושנה',
      'דחה את ההצעה',
    ]);
    expect(historyFor('her'), <String>[
      'נפתחה הצעה עם אליהו',
      'נסגרה הצעה עם אליהו',
      'אליהו דחה את ההצעה',
    ]);
  });

  test('an unknown ender adds nothing beyond the closing line', () async {
    final MatchIdea match = await openProposal();

    await matchRepository.recordOutcome(
      match.id,
      newStatus: MatchStatus.rejected,
      party: MatchOutcomeParty.unknown,
    );

    expect(historyFor('him'), <String>[
      'נפתחה הצעה עם שושנה',
      'נסגרה הצעה עם שושנה',
    ]);
  });

  test('a couple that went out and stopped reads as such', () async {
    final MatchIdea match = await openProposal();

    await matchRepository.recordOutcome(
      match.id,
      newStatus: MatchStatus.dated,
      party: MatchOutcomeParty.mutual,
      note: 'לא הרגישו חיבור',
    );

    expect(historyFor('him'), <String>[
      'נפתחה הצעה עם שושנה',
      'נסגרה הצעה עם שושנה',
      'יצאו ולא המשיכו כי לא הרגישו חיבור',
    ]);
  });
}

Person _person(String id, String firstName, Gender gender, DateTime now) {
  return Person(
    id: id,
    firstName: firstName,
    lastName: 'ישראלי',
    gender: gender,
    manualAge: 26,
    createdAt: now,
    updatedAt: now,
  );
}
