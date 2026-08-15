import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// The ledger behind the activity figures.
///
/// Every place a proposal's status is written has to record it, and the whole
/// value of the record is that nothing downstream has to guess. These tests are
/// the guard on that: a fourth status-writing path added without a call to
/// `_logStatusChange` shows up here as a missing event, not as a quietly wrong
/// number on the home screen months later.
void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;
  late Box<PersonEvent> personEvents;
  late Box<MatchStatusEvent> statusEvents;
  late PersonRepository personRepository;
  late MatchRepository matchRepository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('match_status_events_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(MatchStatusEventAdapter());
    Hive.registerAdapter(PersonEventAdapter());
    Hive.registerAdapter(PersonEventTypeAdapter());
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
    personEvents = await Hive.openBox<PersonEvent>('person_events');
    statusEvents = await Hive.openBox<MatchStatusEvent>('match_status_events');
    await people.clear();
    await matches.clear();
    await notes.clear();
    await personEvents.clear();
    await statusEvents.clear();
    await Hive.box<dynamic>('settings').clear();

    personRepository = PersonRepository(people, null, personEvents);
    matchRepository = MatchRepository(matches, notes, statusEvents)
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

  Future<MatchIdea> openProposal() async {
    final DateTime now = DateTime.now();
    Person person(String id, Gender gender) => Person(
      id: id,
      firstName: 'שם$id',
      lastName: 'לוי',
      gender: gender,
      manualAge: 26,
      createdAt: now,
      updatedAt: now,
    );
    await personRepository.add(person('male', Gender.male));
    await personRepository.add(person('female', Gender.female));
    final MatchIdea? match = await matchRepository.create('male', 'female');
    return match!;
  }

  test('opening a proposal writes no status move', () async {
    await openProposal();
    // Creation is its own action, counted from `createdAt`. A "moved to רעיון"
    // record would be a second count of the same thing.
    expect(matchRepository.getAllStatusEvents(), isEmpty);
  });

  test('every hand-made transition is recorded, with both ends', () async {
    final MatchIdea match = await openProposal();

    await matchRepository.updateStatus(match.id, MatchStatus.checking);
    await matchRepository.setWaiting(match.id, reason: 'הוא בהפסקה');
    await matchRepository.updateStatus(match.id, MatchStatus.dating);

    final List<MatchStatusEvent> events = matchRepository
        .getStatusEventsForMatch(match.id);
    expect(
      events.map((MatchStatusEvent e) => e.toStatus).toList(),
      <MatchStatus>[
        MatchStatus.checking,
        MatchStatus.unavailable,
        MatchStatus.dating,
      ],
    );
    expect(events.first.fromStatus, MatchStatus.idea);
    expect(events[1].fromStatus, MatchStatus.checking);
    expect(events.every((MatchStatusEvent e) => !e.automatic), isTrue);
  });

  test('a status set to what it already is records nothing', () async {
    final MatchIdea match = await openProposal();
    await matchRepository.updateStatus(match.id, MatchStatus.idea);
    expect(matchRepository.getAllStatusEvents(), isEmpty);
  });

  test('a proposal the app moved itself is marked automatic', () async {
    final MatchIdea match = await openProposal();
    await statusEvents.clear();

    // Putting one side on a break pushes the proposal to "בהמתנה" — the app's
    // own move, not the matchmaker's.
    await personRepository.updateProfileStatus('male', ProfileStatus.onBreak);

    final List<MatchStatusEvent> events = matchRepository
        .getStatusEventsForMatch(match.id);
    expect(events, hasLength(1));
    expect(events.single.toStatus, MatchStatus.unavailable);
    expect(events.single.automatic, isTrue);
  });

  test('a couple starting to date leaves one countable act, not three', () async {
    final MatchIdea match = await openProposal();
    await matchRepository.updateStatus(match.id, MatchStatus.dating);

    // The proposal's own move.
    final List<MatchStatusEvent> moves = matchRepository
        .getAllStatusEvents()
        .where((MatchStatusEvent e) => !e.automatic)
        .toList();
    expect(moves, hasLength(1));

    // Both candidates were marked "תפוס" by the app, and both events point back
    // at the proposal that caused them — which is what keeps the count at one.
    final List<PersonEvent> statusChanges = personRepository
        .getAllEvents()
        .where((PersonEvent e) => e.type == PersonEventType.statusChanged)
        .toList();
    expect(statusChanges, hasLength(2));
    expect(
      statusChanges.every((PersonEvent e) => e.relatedMatchId == match.id),
      isTrue,
    );
  });

  test('a status the matchmaker sets by hand carries no proposal', () async {
    await openProposal();
    await personRepository.updateProfileStatus('male', ProfileStatus.onBreak);

    final PersonEvent change = personRepository.getAllEvents().firstWhere(
      (PersonEvent e) => e.type == PersonEventType.statusChanged,
    );
    expect(change.relatedMatchId, isNull);
  });

  test('deleting a proposal takes its ledger with it', () async {
    final MatchIdea match = await openProposal();
    await matchRepository.updateStatus(match.id, MatchStatus.checking);
    expect(matchRepository.getAllStatusEvents(), isNotEmpty);

    await matchRepository.deleteMatch(match.id);
    expect(matchRepository.getAllStatusEvents(), isEmpty);
  });

  test('without a ledger box everything still works', () async {
    final MatchRepository plain = MatchRepository(matches, notes);
    final MatchIdea match = await openProposal();
    await plain.updateStatus(match.id, MatchStatus.dating);

    expect(plain.getAllStatusEvents(), isEmpty);
    expect(plain.getById(match.id)?.status, MatchStatus.dating);
  });
}
