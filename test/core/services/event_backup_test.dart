import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/utils/enums.dart';

/// The history ledgers, through the backup and out the other side.
///
/// **This is the safety net under signing out.** `PersonEvent` and
/// `MatchStatusEvent` were deliberately excluded from the backup for as long as
/// the local database was permanent — a trail of changes is worthless without
/// the records it describes, and these are the fastest-growing stores in the
/// app. The moment signing out began deleting the local copy, that reasoning
/// inverted: everything not in the backup is destroyed on the next account
/// switch, and these two carry every profile's history feed, every figure on
/// the activity screen, and through `CommunityCounts` the matchmaker's standing
/// in the community.
///
/// So the round trip is asserted rather than assumed.
void main() {
  late Directory hiveDirectory;
  int boxCounter = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('shadchan_events_');
    Hive.init(hiveDirectory.path);

    // Written out one by one rather than looped: `Hive.registerAdapter` is
    // generic, and a loop over a list of `Object` erases the type parameter —
    // which registers every adapter as `dynamic` and makes the first write
    // fail with "type 'Gender' is not a subtype of type 'Person'".
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MatchIdeaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(MatchNoteAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MatchStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(CurrentHandlerAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PersonNoteAdapter());
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(MaritalStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(MatchProgressAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MatchContactAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PersonEventAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PersonEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(RegionAdapter());
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(MatchStatusEventAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  Future<(PersonRepository, MatchRepository)> freshRepositories() async {
    final String suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${boxCounter++}';
    return (
      PersonRepository(
        await Hive.openBox<Person>('people_$suffix'),
        await Hive.openBox<PersonNote>('person_notes_$suffix'),
        await Hive.openBox<PersonEvent>('person_events_$suffix'),
      ),
      MatchRepository(
        await Hive.openBox<MatchIdea>('matches_$suffix'),
        await Hive.openBox<MatchNote>('match_notes_$suffix'),
        await Hive.openBox<MatchStatusEvent>('match_status_events_$suffix'),
      ),
    );
  }

  test('A backup carries the history feeds and the activity ledger', () async {
    final (PersonRepository people, MatchRepository matches) =
        await freshRepositories();

    final DateTime when = DateTime(2026, 3, 14, 9, 30);
    await people.addImported(
      Person(
        id: 'p1',
        firstName: 'רבקה',
        lastName: 'כהן',
        gender: Gender.female,
        createdAt: when,
        updatedAt: when,
      ),
    );
    await people.addImported(
      Person(
        id: 'p2',
        firstName: 'יוסף',
        lastName: 'לוי',
        gender: Gender.male,
        createdAt: when,
        updatedAt: when,
      ),
    );
    await matches.addImportedMatch(
      MatchIdea(
        id: 'm1',
        personAId: 'p1',
        personBId: 'p2',
        status: MatchStatus.checking,
        currentHandler: CurrentHandler.me,
        createdAt: when,
        updatedAt: when,
      ),
    );
    await people.addImportedEvent(
      PersonEvent(
        id: 'e1',
        personId: 'p1',
        type: PersonEventType.dated,
        text: 'יצאו לפגישה ראשונה',
        createdAt: when,
        relatedPersonId: 'p2',
        relatedMatchId: 'm1',
      ),
    );
    await matches.addImportedStatusEvent(
      MatchStatusEvent(
        id: 's1',
        matchId: 'm1',
        fromStatus: MatchStatus.checking,
        toStatus: MatchStatus.dating,
        createdAt: when,
      ),
    );

    final Map<String, Object?> payload = BackupService.buildPayload(
      people,
      matches,
    );

    // Present in the file at all — the whole point, and what was missing.
    expect(payload['personEvents'], hasLength(1));
    expect(payload['matchStatusEvents'], hasLength(1));

    // And back into an empty database.
    final (PersonRepository restoredPeople, MatchRepository restoredMatches) =
        await freshRepositories();
    final ImportResult result = await BackupService.importPayload(
      Map<String, dynamic>.from(payload),
      restoredPeople,
      restoredMatches,
    );

    expect(result.eventsAdded, 2);

    final List<PersonEvent> events = restoredPeople.getEventsForPerson('p1');
    expect(events, hasLength(1));
    // Every field, not merely the row: a history line that came back without
    // its text or its date would restore the count and lose the content.
    expect(events.single.id, 'e1');
    expect(events.single.type, PersonEventType.dated);
    expect(events.single.text, 'יצאו לפגישה ראשונה');
    expect(events.single.createdAt, when);
    expect(events.single.relatedPersonId, 'p2');
    expect(events.single.relatedMatchId, 'm1');

    final List<MatchStatusEvent> moves = restoredMatches.getAllStatusEvents();
    expect(moves, hasLength(1));
    expect(moves.single.id, 's1');
    expect(moves.single.fromStatus, MatchStatus.checking);
    expect(moves.single.toStatus, MatchStatus.dating);
    expect(moves.single.createdAt, when);
    expect(moves.single.automatic, isFalse);
  });

  test('History whose record did not survive the import is dropped', () async {
    final (PersonRepository people, MatchRepository matches) =
        await freshRepositories();

    // A backup describing history for a person and a proposal that are not in
    // it. Restoring these would leave the history screen drawing lines against
    // records that do not exist.
    final ImportResult result = await BackupService.importPayload(
      <String, dynamic>{
        'people': <Map<String, dynamic>>[],
        'matches': <Map<String, dynamic>>[],
        'personEvents': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'e9',
            'personId': 'ghost',
            'type': 'note',
            'text': 'על מישהו שלא קיים',
            'createdAt': '2026-03-14T09:30:00.000',
          },
        ],
        'matchStatusEvents': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 's9',
            'matchId': 'ghost',
            'toStatus': 'dating',
            'createdAt': '2026-03-14T09:30:00.000',
          },
        ],
      },
      people,
      matches,
    );

    expect(result.eventsAdded, 0);
    expect(result.skipped, 2);
    expect(people.getAllEvents(), isEmpty);
    expect(matches.getAllStatusEvents(), isEmpty);
  });

  test('A status event with an unreadable destination is skipped', () async {
    final (PersonRepository people, MatchRepository matches) =
        await freshRepositories();

    final DateTime when = DateTime(2026, 3, 14);
    await people.addImported(
      Person(
        id: 'p1',
        firstName: 'רבקה',
        lastName: 'כהן',
        gender: Gender.female,
        createdAt: when,
        updatedAt: when,
      ),
    );
    await people.addImported(
      Person(
        id: 'p2',
        firstName: 'יוסף',
        lastName: 'לוי',
        gender: Gender.male,
        createdAt: when,
        updatedAt: when,
      ),
    );
    await matches.addImportedMatch(
      MatchIdea(
        id: 'm1',
        personAId: 'p1',
        personBId: 'p2',
        status: MatchStatus.checking,
        currentHandler: CurrentHandler.me,
        createdAt: when,
        updatedAt: when,
      ),
    );

    final ImportResult result = await BackupService.importPayload(
      <String, dynamic>{
        'matchStatusEvents': <Map<String, dynamic>>[
          // `toStatus` is the one field with no sensible default — a move to
          // nowhere is not history, it is a broken record.
          <String, dynamic>{
            'id': 's1',
            'matchId': 'm1',
            'toStatus': 'somethingRemoved',
            'createdAt': '2026-03-14T00:00:00.000',
          },
          // Where it came *from* may legitimately be unknown.
          <String, dynamic>{
            'id': 's2',
            'matchId': 'm1',
            'toStatus': 'dating',
            'createdAt': '2026-03-14T00:00:00.000',
          },
        ],
      },
      people,
      matches,
    );

    expect(result.eventsAdded, 1);
    final List<MatchStatusEvent> moves = matches.getAllStatusEvents();
    expect(moves, hasLength(1));
    expect(moves.single.id, 's2');
    expect(moves.single.fromStatus, isNull);
  });
}
