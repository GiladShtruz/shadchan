import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';

void main() {
  late Directory hiveDirectory;
  late int boxCounter;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    hiveDirectory = await Directory.systemTemp.createTemp(
      'shadchan_backup_test_',
    );
    Hive.init(hiveDirectory.path);
    boxCounter = 0;

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MatchIdeaAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MatchNoteAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GenderAdapter());
    }
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
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(MaritalStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(MatchProgressAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MatchContactAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('importData skips matches and notes with missing references', () async {
    final String suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${boxCounter++}';
    final Box<Person> peopleBox = await Hive.openBox<Person>('people_$suffix');
    final Box<MatchIdea> matchesBox = await Hive.openBox<MatchIdea>(
      'matches_$suffix',
    );
    final Box<MatchNote> notesBox = await Hive.openBox<MatchNote>(
      'match_notes_$suffix',
    );

    final PersonRepository personRepo = PersonRepository(peopleBox);
    final MatchRepository matchRepo = MatchRepository(matchesBox, notesBox);
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'shadchan_backup_json_',
    );
    final File jsonFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}import.json',
    );

    const String timestamp = '2026-04-14T12:00:00.000Z';
    await jsonFile.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'exportDate': timestamp,
        'people': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'person_a',
            'firstName': 'דוד',
            'lastName': 'כהן',
            'gender': 'male',
            'birthDate': null,
            'manualAge': 25,
            'religiousLevel': 'datiLeumi',
            'city': null,
            'phone': null,
            'source': null,
            'notes': null,
            'photos': <String>[],
            'isFavorite': false,
            'createdAt': timestamp,
            'updatedAt': timestamp,
          },
          <String, Object?>{
            'id': 'person_b',
            'firstName': 'שרה',
            'lastName': 'לוי',
            'gender': 'female',
            'birthDate': null,
            'manualAge': 24,
            'religiousLevel': 'datiOpen',
            'city': null,
            'phone': null,
            'source': null,
            'notes': null,
            'photos': <String>[],
            'isFavorite': false,
            'createdAt': timestamp,
            'updatedAt': timestamp,
          },
        ],
        'matches': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'match_valid',
            'personAId': 'person_a',
            'personBId': 'person_b',
            'status': 'idea',
            'currentHandler': 'me',
            'handlerName': null,
            'createdAt': timestamp,
            'updatedAt': timestamp,
          },
          <String, Object?>{
            'id': 'match_missing_person',
            'personAId': 'person_a',
            'personBId': 'person_missing',
            'status': 'checking',
            'currentHandler': 'personB',
            'handlerName': null,
            'createdAt': timestamp,
            'updatedAt': timestamp,
          },
        ],
        'matchNotes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'note_valid',
            'matchId': 'match_valid',
            'text': 'הצעה טובה',
            'createdAt': timestamp,
            'isAutomatic': false,
          },
          <String, Object?>{
            'id': 'note_for_skipped_match',
            'matchId': 'match_missing_person',
            'text': 'לא אמור להיכנס',
            'createdAt': timestamp,
            'isAutomatic': false,
          },
          <String, Object?>{
            'id': 'note_missing_match',
            'matchId': 'missing_match',
            'text': 'גם זה לא',
            'createdAt': timestamp,
            'isAutomatic': false,
          },
        ],
      }),
    );

    final ImportResult result = await BackupService.importData(
      jsonFile,
      personRepo,
      matchRepo,
    );

    expect(result.peopleAdded, 2);
    expect(result.matchesAdded, 1);
    expect(result.notesAdded, 1);
    expect(result.skipped, 3);
    expect(personRepo.getAll(), hasLength(2));
    expect(matchRepo.getAll(), hasLength(1));
    expect(matchRepo.getAllNotes(), hasLength(1));
    expect(matchRepo.getById('match_valid'), isNotNull);
    expect(matchRepo.getById('match_missing_person'), isNull);

    await peopleBox.deleteFromDisk();
    await matchesBox.deleteFromDisk();
    await notesBox.deleteFromDisk();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'importData restores hidden/needsReview/height/marital and reminders',
    () async {
      final String suffix =
          '${DateTime.now().microsecondsSinceEpoch}_${boxCounter++}';
      final Box<Person> peopleBox = await Hive.openBox<Person>(
        'people_$suffix',
      );
      final Box<MatchIdea> matchesBox = await Hive.openBox<MatchIdea>(
        'matches_$suffix',
      );
      final Box<MatchNote> notesBox = await Hive.openBox<MatchNote>(
        'match_notes_$suffix',
      );

      final PersonRepository personRepo = PersonRepository(peopleBox);
      final MatchRepository matchRepo = MatchRepository(matchesBox, notesBox);
      final Directory tempDirectory = await Directory.systemTemp.createTemp(
        'shadchan_backup_json_',
      );
      final File jsonFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}import.json',
      );

      const String timestamp = '2026-04-14T12:00:00.000Z';
      const String reminder = '2026-08-01T09:00:00.000Z';
      await jsonFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 2,
          'exportDate': timestamp,
          'people': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'person_a',
              'firstName': 'דוד',
              'lastName': 'כהן',
              'gender': 'male',
              'manualAge': 30,
              'heightCm': 178,
              'avatarIndex': 3,
              'maritalStatus': 'divorced',
              'profileStatus': 'available',
              'needsReview': true,
              'hidden': false,
              'photos': <String>[],
              'isFavorite': false,
              'createdAt': timestamp,
              'updatedAt': timestamp,
            },
            <String, Object?>{
              'id': 'person_b',
              'firstName': 'שרה',
              'lastName': 'לוי',
              'gender': 'female',
              'manualAge': 27,
              'profileStatus': 'available',
              'needsReview': false,
              'hidden': true,
              'photos': <String>[],
              'isFavorite': false,
              'createdAt': timestamp,
              'updatedAt': timestamp,
            },
          ],
          'matches': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'match_1',
              'personAId': 'person_a',
              'personBId': 'person_b',
              'status': 'idea',
              'currentHandler': 'me',
              'reminderDate': reminder,
              'reminderNote': 'להתקשר לצד הבחורה',
              'waitingReason': 'מחכים לתשובה ממנה',
              'progress': 'waitingHer',
              'progressOther': null,
              'relatedContacts': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'רותי כהן',
                  'phone': '0501234567',
                  'description': 'אמא של כרמל',
                },
              ],
              'createdAt': timestamp,
              'updatedAt': timestamp,
            },
          ],
        }),
      );

      final ImportResult result = await BackupService.importData(
        jsonFile,
        personRepo,
        matchRepo,
      );

      expect(result.peopleAdded, 2);
      expect(result.matchesAdded, 1);

      final Person personA = personRepo.getById('person_a')!;
      expect(personA.needsReview, isTrue);
      expect(personA.hidden, isFalse);
      expect(personA.heightCm, 178);
      expect(personA.avatarIndex, 3);
      expect(personA.maritalStatus, MaritalStatus.divorced);

      final Person personB = personRepo.getById('person_b')!;
      expect(personB.hidden, isTrue);

      final MatchIdea match = matchRepo.getById('match_1')!;
      expect(match.reminderDate, DateTime.parse(reminder));
      expect(match.reminderNote, 'להתקשר לצד הבחורה');
      expect(match.waitingReason, 'מחכים לתשובה ממנה');
      expect(match.progress, MatchProgress.waitingHer);
      expect(match.relatedContacts, hasLength(1));
      expect(match.relatedContacts.single.name, 'רותי כהן');
      expect(match.relatedContacts.single.description, 'אמא של כרמל');

      await peopleBox.deleteFromDisk();
      await matchesBox.deleteFromDisk();
      await notesBox.deleteFromDisk();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test('importData skips malformed records without aborting the rest', () async {
    final String suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${boxCounter++}';
    final Box<Person> peopleBox = await Hive.openBox<Person>('people_$suffix');
    final Box<MatchIdea> matchesBox = await Hive.openBox<MatchIdea>(
      'matches_$suffix',
    );
    final Box<MatchNote> notesBox = await Hive.openBox<MatchNote>(
      'match_notes_$suffix',
    );

    final PersonRepository personRepo = PersonRepository(peopleBox);
    final MatchRepository matchRepo = MatchRepository(matchesBox, notesBox);
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'shadchan_backup_json_',
    );
    final File jsonFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}import.json',
    );

    const String timestamp = '2026-04-14T12:00:00.000Z';
    await jsonFile.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 2,
        'people': <Object?>[
          // Valid, but with an unknown gender and a garbage date — both should
          // degrade to defaults rather than dropping the record.
          <String, Object?>{
            'id': 'good',
            'firstName': 'טוב',
            'lastName': 'תקין',
            'gender': 'alien',
            'profileStatus': 'available',
            'photos': <String>[],
            'createdAt': 'not-a-date',
            'updatedAt': timestamp,
          },
          // No id — unrecoverable, skipped.
          <String, Object?>{'firstName': 'בלי', 'lastName': 'מזהה'},
          // Not even a map.
          'garbage',
        ],
      }),
    );

    final ImportResult result = await BackupService.importData(
      jsonFile,
      personRepo,
      matchRepo,
    );

    expect(result.peopleAdded, 1);
    expect(result.skipped, greaterThanOrEqualTo(1));

    final Person good = personRepo.getById('good')!;
    expect(good.gender, Gender.unknown);
    // A garbage createdAt falls back to "now", so it must still be a real date.
    expect(good.createdAt, isNotNull);

    await peopleBox.deleteFromDisk();
    await matchesBox.deleteFromDisk();
    await notesBox.deleteFromDisk();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });
}
