import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;
  late PersonRepository personRepository;
  late MatchRepository matchRepository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('match_status_sync_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(MatchStatusAdapter());
    Hive.registerAdapter(CurrentHandlerAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    people = await Hive.openBox<Person>('people');
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    await people.clear();
    await matches.clear();
    await notes.clear();
    await Hive.box<dynamic>('settings').clear();

    personRepository = PersonRepository(people);
    matchRepository = MatchRepository(matches, notes)
      ..resolvePerson = personRepository.getById;
    personRepository.onPersonStatusChanged =
        matchRepository.syncMatchesForPerson;
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('global person status pauses and reopens relevant proposals', () async {
    final DateTime now = DateTime(2026, 7, 27);
    final Person male = _person('male', 'הלל', Gender.male, now);
    final Person female = _person('female', 'כרמל', Gender.female, now);
    await people.put(male.id, male);
    await people.put(female.id, female);
    final MatchIdea match = MatchIdea(
      id: 'match',
      personAId: male.id,
      personBId: female.id,
      status: MatchStatus.idea,
      currentHandler: CurrentHandler.me,
      createdAt: now,
      updatedAt: now,
    );
    await matches.put(match.id, match);

    await personRepository.updateProfileStatus(
      female.id,
      ProfileStatus.onBreak,
    );
    expect(matchRepository.getById(match.id)!.status, MatchStatus.unavailable);
    expect(matchRepository.getNotesForMatch(match.id), isEmpty);

    await personRepository.setPersonReminder(female.id, DateTime(2026, 8, 27));
    await personRepository.updateProfileStatus(
      female.id,
      ProfileStatus.available,
    );

    expect(matchRepository.getById(match.id)!.status, MatchStatus.idea);
    expect(personRepository.personReminderFor(female.id), isNull);
    expect(matchRepository.getNotesForMatch(match.id), isEmpty);
  });

  test(
    'every idea of a candidate who becomes available again reopens',
    () async {
      final DateTime now = DateTime(2026, 7, 27);
      final Person female = _person('female', 'כרמל', Gender.female, now);
      final Person first = _person('m1', 'הלל', Gender.male, now);
      final Person second = _person('m2', 'אליה', Gender.male, now);
      for (final Person person in <Person>[female, first, second]) {
        await people.put(person.id, person);
      }
      for (final String id in <String>['match1', 'match2']) {
        await matches.put(
          id,
          MatchIdea(
            id: id,
            personAId: id == 'match1' ? first.id : second.id,
            personBId: female.id,
            status: MatchStatus.idea,
            currentHandler: CurrentHandler.me,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // "תפוס" pauses both of her ideas at once...
      await personRepository.updateProfileStatus(female.id, ProfileStatus.busy);
      expect(
        matchRepository.getAll().map((MatchIdea m) => m.status),
        everyElement(MatchStatus.unavailable),
      );

      // ...and going back to "פנוי" hands both of them back as open ideas,
      // without the matchmaker touching either proposal.
      await personRepository.updateProfileStatus(
        female.id,
        ProfileStatus.available,
      );
      expect(
        matchRepository.getAll().map((MatchIdea m) => m.status),
        everyElement(MatchStatus.idea),
      );
    },
  );
}

Person _person(String id, String name, Gender gender, DateTime now) {
  return Person(
    id: id,
    firstName: name,
    lastName: '',
    gender: gender,
    createdAt: now,
    updatedAt: now,
  );
}
