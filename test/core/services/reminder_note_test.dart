import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// The note on a reminder is optional, and "optional" has to mean it all the
/// way down to the record.
void main() {
  late Directory directory;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('reminder_note_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
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
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await matches.clear();
    await notes.clear();
    final DateTime now = DateTime(2026, 8, 19);
    await matches.put(
      'm1',
      MatchIdea(
        id: 'm1',
        personAId: 'male',
        personBId: 'female',
        status: MatchStatus.idea,
        currentHandler: CurrentHandler.me,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows keeps the box files locked. Harmless — it is a temp dir.
    }
  });

  test('a reminder can be set with no note at all', () async {
    final MatchRepository repository = MatchRepository(matches, notes);

    await repository.setReminder('m1', DateTime(2026, 9, 1));

    expect(repository.getById('m1')!.reminderDate, DateTime(2026, 9, 1));
    expect(repository.getById('m1')!.reminderNote, isNull);
  });

  test('clearing the note leaves null, not an empty string', () async {
    final MatchRepository repository = MatchRepository(matches, notes);

    await repository.setReminder(
      'm1',
      DateTime(2026, 9, 1),
      note: 'לבדוק אם חזרה מההפסקה',
    );
    expect(repository.getById('m1')!.reminderNote, 'לבדוק אם חזרה מההפסקה');

    // What the dialog returns when somebody empties the field and confirms.
    await repository.setReminder('m1', DateTime(2026, 9, 1), note: '  ');

    // Null rather than '', because the notification body is written as
    // `reminderNote ?? 'יש לך תזכורת להצעת שידוך'` — an empty string is not
    // null, and it used to fire a notification with nothing in it.
    expect(repository.getById('m1')!.reminderNote, isNull);
  });

  test('clearing the reminder clears its note with it', () async {
    final MatchRepository repository = MatchRepository(matches, notes);

    await repository.setReminder('m1', DateTime(2026, 9, 1), note: 'לבדוק');
    await repository.setReminder('m1', null);

    expect(repository.getById('m1')!.reminderDate, isNull);
    expect(repository.getById('m1')!.reminderNote, isNull);
  });
}
