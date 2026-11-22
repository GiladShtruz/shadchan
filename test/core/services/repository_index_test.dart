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
import 'package:shadchan/services/self_identity.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// The repositories keep what every screen reads over the whole database
/// (2026-11-22, large databases): the readable people, the history lines by
/// friend, the ideas newest first and by friend, the status ledger. Whatever
/// way a change arrives — through the repository, straight into a box, or by
/// who the user is — the next read must see it.
void main() {
  late Directory dir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('repo_index_');
    Hive.init(dir.path);
    Hive
      ..registerAdapter(PersonAdapter())
      ..registerAdapter(RegionAdapter())
      ..registerAdapter(GenderAdapter())
      ..registerAdapter(ReligiousLevelAdapter())
      ..registerAdapter(ProfileStatusAdapter())
      ..registerAdapter(MaritalStatusAdapter())
      ..registerAdapter(PersonEventAdapter())
      ..registerAdapter(PersonEventTypeAdapter())
      ..registerAdapter(MatchIdeaAdapter())
      ..registerAdapter(MatchNoteAdapter())
      ..registerAdapter(MatchStatusAdapter())
      ..registerAdapter(CurrentHandlerAdapter())
      ..registerAdapter(MatchStatusEventAdapter());
  });

  tearDown(SelfIdentity.reset);

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Person person(String id, {String? phone}) => Person(
    id: id,
    firstName: 'שם$id',
    lastName: 'כהן',
    gender: Gender.male,
    phone: phone,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  PersonEvent event(String id, String personId) => PersonEvent(
    id: id,
    personId: personId,
    type: PersonEventType.cardSynced,
    text: 'x',
    createdAt: DateTime(2026),
  );

  MatchIdea idea(String id, String a, String b, DateTime updated) => MatchIdea(
    id: id,
    personAId: a,
    personBId: b,
    status: MatchStatus.idea,
    currentHandler: CurrentHandler.me,
    createdAt: DateTime(2026),
    updatedAt: updated,
  );

  test(
    'counts follow the box, and the user leaves their own list at once',
    () async {
      final Box<Person> box = await Hive.openBox<Person>('people_a');
      final PersonRepository repo = PersonRepository(box);
      await box.put('1', person('1', phone: '0521111111'));
      await box.put('2', person('2', phone: '0522222222'));
      expect(repo.count, 2);
      // Straight into the box, no announcement: the length tells.
      await box.put('3', person('3'));
      expect(repo.count, 3);
      // "המספר שלי" becomes known after the first frame.
      SelfIdentity.update(phone: '052-2222222');
      expect(repo.getAll().map((Person p) => p.id), <String>['1', '3']);
      expect(repo.count, 2);
    },
  );

  test('history lines by friend see new and removed lines', () async {
    final Box<Person> people = await Hive.openBox<Person>('people_b');
    final Box<PersonEvent> events = await Hive.openBox<PersonEvent>('ev_b');
    final PersonRepository repo = PersonRepository(people, null, events);
    await events.put('e1', event('e1', 'p1'));
    expect(repo.eventsOf('p1'), hasLength(1));
    expect(repo.eventsOf('p2'), isEmpty);
    await events.put('e2', event('e2', 'p2'));
    expect(repo.eventsOf('p2'), hasLength(1));
    await repo.logEvent('p1', PersonEventType.cardSynced, 'y');
    expect(repo.eventsOf('p1'), hasLength(2));
    expect(repo.getEventsForPerson('p1'), hasLength(2));
    await events.delete('e1');
    expect(repo.eventsOf('p1'), hasLength(1));
    expect(repo.getAllEvents(), hasLength(2));
    expect(
      () => repo.getAllEvents().add(event('x', 'p')),
      throwsUnsupportedError,
    );
  });

  test('ideas by friend and newest first follow every kind of write', () async {
    final Box<MatchIdea> box = await Hive.openBox<MatchIdea>('m_c');
    final Box<MatchStatusEvent> ledger = await Hive.openBox<MatchStatusEvent>(
      'ms_c',
    );
    final MatchRepository repo = MatchRepository(
      box,
      await Hive.openBox<MatchNote>('mn_c'),
      ledger,
    );
    await box.put('a', idea('a', 'p1', 'p2', DateTime(2026, 1)));
    await box.put('b', idea('b', 'p1', 'p3', DateTime(2026, 3)));
    expect(repo.getAll().map((MatchIdea m) => m.id), <String>['b', 'a']);
    expect(repo.getByPersonId('p1').map((MatchIdea m) => m.id), <String>[
      'b',
      'a',
    ]);
    expect(repo.getByPersonId('p3').map((MatchIdea m) => m.id), <String>['b']);
    // A caller cannot change the kept copy.
    repo.getByPersonId('p1').clear();
    repo.getAll().clear();
    expect(repo.getByPersonId('p1'), hasLength(2));

    // Edited in place and saved (the order changes): the box's own event.
    final MatchIdea a = box.get('a')!..updatedAt = DateTime(2026, 6);
    await a.save();
    await Future<void>.delayed(Duration.zero);
    expect(repo.getAll().map((MatchIdea m) => m.id), <String>['a', 'b']);
    expect(repo.getByPersonId('p1').first.id, 'a');

    await box.delete('b');
    expect(repo.getByPersonId('p3'), isEmpty);
    expect(repo.getAll(), hasLength(1));

    await ledger.put(
      's1',
      MatchStatusEvent(
        id: 's1',
        matchId: 'a',
        fromStatus: MatchStatus.idea,
        toStatus: MatchStatus.checking,
        createdAt: DateTime(2026),
      ),
    );
    expect(repo.getAllStatusEvents(), hasLength(1));
  });

  test('a phone number hashes the same every time', () {
    final String? first = PhoneIdentity.hash('050-1234567');
    expect(PhoneIdentity.hash('050-1234567'), first);
    expect(PhoneIdentity.hash('+972 50 123 4567'), first);
    expect(PhoneIdentity.hash('12'), isNull);
    expect(PhoneIdentity.hash(null), isNull);
  });
}
