import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/services/match_migrations.dart';
import 'package:shadchan/utils/enums.dart';

/// An update must not arm a monthly reminder on every old idea at once: the
/// default reminders an earlier version handed out with no activity behind
/// them are taken back, once; the ones activity earned stay.
void main() {
  late Directory directory;
  late Box<MatchIdea> matches;
  late Box<dynamic> settings;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('unearned_');
    Hive.init(directory.path);
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(MatchContactAdapter());
    Hive.registerAdapter(MatchStatusAdapter());
    Hive.registerAdapter(MatchProgressAdapter());
    Hive.registerAdapter(CurrentHandlerAdapter());
    matches = await Hive.openBox<MatchIdea>('matches');
    settings = await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  MatchIdea idea(
    String id,
    DateTime last,
    DateTime? reminder, {
    String? note,
  }) => MatchIdea(
    id: id,
    personAId: 'a$id',
    personBId: 'b$id',
    status: MatchStatus.idea,
    currentHandler: CurrentHandler.me,
    createdAt: last,
    updatedAt: last,
    reminderDate: reminder,
    reminderNote: note ?? MatchRepository.defaultReminderNote,
  );

  test('only the reminders no activity earned are cleared, once', () async {
    final DateTime old = DateTime(2026, 3, 1);
    final DateTime migratedAt = DateTime(2026, 11, 1);
    await matches.putAll(<String, MatchIdea>{
      // Handed out by the old launch backfill, months after the idea.
      'old': idea('old', old, MatchRepository.defaultReminderFrom(migratedAt)),
      // A month after its own last act: earned.
      'earned': idea(
        'earned',
        DateTime(2026, 11, 10),
        MatchRepository.defaultReminderFrom(DateTime(2026, 11, 10)),
      ),
      // Set by hand: a decision, never touched.
      'hand': idea('hand', old, DateTime(2026, 12, 24), note: 'להתקשר לאמא'),
    });
    await MatchMigrations.retireUnearnedMonthlyReminders(
      matches: matches,
      notes: <MatchNote>[
        // A journal line is activity too.
        MatchNote(
          id: 'n',
          matchId: 'none',
          text: 'x',
          createdAt: DateTime(2026, 11, 10),
          isAutomatic: true,
        ),
      ],
      settings: settings,
    );
    expect(matches.get('old')!.reminderDate, isNull);
    expect(matches.get('earned')!.reminderDate, isNotNull);
    expect(matches.get('hand')!.reminderDate, DateTime(2026, 12, 24));
    expect(settings.get(MatchMigrations.unearnedRemindersKey), isTrue);
  });
}
