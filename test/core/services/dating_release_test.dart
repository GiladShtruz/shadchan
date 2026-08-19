import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// "מתחילים לצאת" marks both sides "תפוס". Leaving that state has to put them
/// back — the couple who are no longer out are available to everybody else,
/// and nothing else in the app ever cleared the flag this proposal set.
void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;
  late PersonRepository personRepository;
  late MatchRepository matchRepository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('dating_release_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
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
    // The same wiring `main.dart` sets up, so a status written here travels the
    // route it does in the app.
    matchRepository = MatchRepository(matches, notes)
      ..resolvePerson = personRepository.getById
      ..markPersonBusy = ((String personId, String matchId) =>
          personRepository.updateProfileStatus(
            personId,
            ProfileStatus.busy,
            causedByMatchId: matchId,
          ))
      ..markPersonMazelTov = ((String personId, String matchId) =>
          personRepository.updateProfileStatus(
            personId,
            ProfileStatus.mazelTov,
            causedByMatchId: matchId,
          ))
      ..restorePersonStatus =
          ((String personId, ProfileStatus status, String matchId) =>
              personRepository.updateProfileStatus(
                personId,
                status,
                causedByMatchId: matchId,
              ));
    personRepository.onPersonStatusChanged =
        matchRepository.syncMatchesForPerson;
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  ProfileStatus statusOf(String id) =>
      personRepository.getById(id)!.profileStatus;

  test('"הפסיקו לצאת" returns both sides to פנוי', () async {
    await _seedPair(people, matches, matchId: 'm1');

    await matchRepository.updateStatus('m1', MatchStatus.dating);
    expect(statusOf('male'), ProfileStatus.busy);
    expect(statusOf('female'), ProfileStatus.busy);

    await matchRepository.updateStatus('m1', MatchStatus.dated);
    expect(statusOf('male'), ProfileStatus.available);
    expect(statusOf('female'), ProfileStatus.available);
  });

  test('reopening a proposal that had been dating frees both sides', () async {
    await _seedPair(people, matches, matchId: 'm1');

    await matchRepository.updateStatus('m1', MatchStatus.dating);
    await matchRepository.updateStatus('m1', MatchStatus.idea);

    expect(statusOf('male'), ProfileStatus.available);
    expect(statusOf('female'), ProfileStatus.available);
  });

  test('a wedding still leaves both sides on מזל טוב', () async {
    await _seedPair(people, matches, matchId: 'm1');

    await matchRepository.updateStatus('m1', MatchStatus.dating);
    await matchRepository.updateStatus('m1', MatchStatus.married);

    expect(statusOf('male'), ProfileStatus.mazelTov);
    expect(statusOf('female'), ProfileStatus.mazelTov);
  });

  test('a side who is out with somebody else stays תפוס', () async {
    await _seedPair(people, matches, matchId: 'm1');
    final Person second = _person('female2', 'אביגיל', Gender.female);
    await people.put(second.id, second);
    await matches.put(
      'm2',
      MatchIdea(
        id: 'm2',
        personAId: 'male',
        personBId: second.id,
        status: MatchStatus.idea,
        currentHandler: CurrentHandler.me,
        createdAt: DateTime(2026, 8, 18),
        updatedAt: DateTime(2026, 8, 18),
      ),
    );

    await matchRepository.updateStatus('m1', MatchStatus.dating);
    await matchRepository.updateStatus('m2', MatchStatus.dating);

    // The first proposal ends. He is still out with the second one.
    await matchRepository.updateStatus('m1', MatchStatus.dated);

    expect(statusOf('male'), ProfileStatus.busy);
    expect(statusOf('female'), ProfileStatus.available);
  });

  test('a side deliberately put on בהפסקה is not overruled', () async {
    await _seedPair(people, matches, matchId: 'm1');

    await matchRepository.updateStatus('m1', MatchStatus.dating);
    await personRepository.updateProfileStatus('female', ProfileStatus.onBreak);

    await matchRepository.updateStatus('m1', MatchStatus.dated);

    expect(statusOf('male'), ProfileStatus.available);
    expect(statusOf('female'), ProfileStatus.onBreak);
  });

  test('freeing a side reopens their other paused proposals', () async {
    await _seedPair(people, matches, matchId: 'm1');
    final Person second = _person('female2', 'אביגיל', Gender.female);
    await people.put(second.id, second);
    await matches.put(
      'm2',
      MatchIdea(
        id: 'm2',
        personAId: 'male',
        personBId: second.id,
        status: MatchStatus.idea,
        currentHandler: CurrentHandler.me,
        createdAt: DateTime(2026, 8, 18),
        updatedAt: DateTime(2026, 8, 18),
      ),
    );

    await matchRepository.updateStatus('m1', MatchStatus.dating);
    expect(matchRepository.getById('m2')!.status, MatchStatus.unavailable);

    await matchRepository.updateStatus('m1', MatchStatus.dated);

    expect(matchRepository.getById('m1')!.status, MatchStatus.dated);
    expect(matchRepository.getById('m2')!.status, MatchStatus.idea);
  });
}

Future<void> _seedPair(
  Box<Person> people,
  Box<MatchIdea> matches, {
  required String matchId,
}) async {
  final DateTime now = DateTime(2026, 8, 18);
  final Person male = _person('male', 'הלל', Gender.male);
  final Person female = _person('female', 'כרמל', Gender.female);
  await people.put(male.id, male);
  await people.put(female.id, female);
  await matches.put(
    matchId,
    MatchIdea(
      id: matchId,
      personAId: male.id,
      personBId: female.id,
      status: MatchStatus.idea,
      currentHandler: CurrentHandler.me,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Person _person(String id, String name, Gender gender) {
  return Person(
    id: id,
    firstName: name,
    lastName: '',
    gender: gender,
    createdAt: DateTime(2026, 8, 18),
    updatedAt: DateTime(2026, 8, 18),
  );
}
