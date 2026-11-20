import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// `PersonRepository.getAll()` keeps its sorted list between calls (it was
/// re-sorted ~20 times per home rebuild). Whatever way a change arrives, the
/// next call must see it.
void main() {
  late Directory dir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('person_cache_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(RegionAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(MaritalStatusAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Person person(String id, String first) => Person(
    id: id,
    firstName: first,
    lastName: 'כהן',
    gender: Gender.male,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('sorted, and a caller cannot change the kept list', () async {
    final Box<Person> box = await Hive.openBox<Person>('cache_a');
    final PersonRepository repo = PersonRepository(box);
    await box.put('2', person('2', 'משה'));
    await box.put('1', person('1', 'אבי'));
    final List<Person> first = repo.getAll();
    expect(first.map((Person p) => p.firstName), <String>['אבי', 'משה']);
    first.clear();
    expect(repo.getAll(), hasLength(2));
  });

  test('a write straight into the box is seen on the next call', () async {
    final Box<Person> box = await Hive.openBox<Person>('cache_b');
    final PersonRepository repo = PersonRepository(box);
    await box.put('1', person('1', 'יוסי'));
    expect(repo.getAll(), hasLength(1));
    // Added without the repository hearing of it.
    await box.put('2', person('2', 'אבי'));
    expect(repo.getAll().map((Person p) => p.firstName), <String>[
      'אבי',
      'יוסי',
    ]);
    // An edit of an existing record arrives through the box's own event.
    await box.put('2', person('2', 'צבי'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.getAll().map((Person p) => p.firstName), <String>[
      'יוסי',
      'צבי',
    ]);
    // And anything the repository announces drops the kept list at once.
    await box.delete('1');
    repo.notifySyncChange();
    expect(repo.getAll().map((Person p) => p.firstName), <String>['צבי']);
  });
}
