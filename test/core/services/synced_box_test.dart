import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/hive_adapters.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/utils/enums.dart';

/// The sync is handed the boxes exactly as `main.dart` opens them — typed.
/// Asking Hive for one of them as `Box<dynamic>` throws, and that HiveError is
/// what kept the sync from ever starting on a phone.
void main() {
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('synced_box_test_');
    Hive.init(root.path);
    registerHiveAdapters();
    await Hive.openBox<Person>('people');
    await Hive.openBox<PersonNote>('person_notes');
    await Hive.openBox<PersonEvent>('person_events');
    await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
    await Hive.openBox<MatchStatusEvent>('match_status_events');
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('asking for a typed box as dynamic is what used to fail', () {
    expect(() => Hive.box<dynamic>('people'), throwsA(isA<HiveError>()));
  });

  test('every synced collection resolves to its open box', () {
    for (final SyncCollection collection in SyncCollection.values) {
      final Box<dynamic> box = SyncProvider.syncedBox(collection);
      expect(box.name, collection.box);
      expect(box.isOpen, isTrue);
    }
  });

  test('the engine can write records through the shared map', () async {
    final Box<dynamic> people = SyncProvider.syncedBox(SyncCollection.people);
    final DateTime at = DateTime(2026, 1, 1);
    await people.put(
      'p1',
      Person(
        id: 'p1',
        firstName: 'דוד',
        lastName: 'כהן',
        gender: Gender.male,
        createdAt: at,
        updatedAt: at,
      ),
    );
    expect(Hive.box<Person>('people').get('p1')!.firstName, 'דוד');
    await SyncProvider.syncedBox(SyncCollection.people).clear();
    expect(Hive.box<Person>('people').isEmpty, isTrue);
  });
}
