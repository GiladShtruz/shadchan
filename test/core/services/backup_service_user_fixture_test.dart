import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory =
        await Directory.systemTemp.createTemp('shadchan_user_fixture_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MatchIdeaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(MatchNoteAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(MatchStatusAdapter());
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(CurrentHandlerAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('imports user-provided backup fixture', () async {
    final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final Box<Person> peopleBox = await Hive.openBox<Person>('people_$suffix');
    final Box<MatchIdea> matchesBox =
        await Hive.openBox<MatchIdea>('matches_$suffix');
    final Box<MatchNote> notesBox =
        await Hive.openBox<MatchNote>('match_notes_$suffix');

    final PersonRepository personRepo = PersonRepository(peopleBox);
    final MatchRepository matchRepo = MatchRepository(matchesBox, notesBox);

    final File fixture = File('test/fixtures/user_backup.json');
    expect(await fixture.exists(), isTrue, reason: 'fixture missing');

    final ImportResult result =
        await BackupService.importData(fixture, personRepo, matchRepo);

    expect(result.peopleAdded, greaterThan(0));
    expect(result.matchesAdded, greaterThan(0));

    await peopleBox.deleteFromDisk();
    await matchesBox.deleteFromDisk();
    await notesBox.deleteFromDisk();
  });
}
