import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/person_migrations.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  late Directory hiveDirectory;
  late int boxCounter;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    hiveDirectory = await Directory.systemTemp.createTemp(
      'shadchan_migration_test_',
    );
    Hive.init(hiveDirectory.path);
    boxCounter = 0;

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GenderAdapter());
    }
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
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  Future<(Box<Person>, Box<dynamic>)> openBoxes() async {
    boxCounter++;
    return (
      await Hive.openBox<Person>('people_$boxCounter'),
      await Hive.openBox<dynamic>('settings_$boxCounter'),
    );
  }

  Person buildPerson({
    required String id,
    DateTime? legacyBirthDate,
    int? manualAge,
    int? legacyHebrewBirthYear,
  }) {
    final DateTime now = DateTime(2026, 7, 21);
    return Person(
      id: id,
      firstName: 'דוד',
      lastName: 'כהן',
      gender: Gender.male,
      legacyBirthDate: legacyBirthDate,
      manualAge: manualAge,
      legacyHebrewBirthYear: legacyHebrewBirthYear,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('converts a stored birth date into an age', () async {
    final (Box<Person> people, Box<dynamic> settings) = await openBoxes();
    final Person person = buildPerson(
      id: 'a',
      legacyBirthDate: DateTime(2000, 1, 2),
    );
    await people.put(person.id, person);

    await PersonMigrations.convertBirthDatesToAges(
      people: people,
      settings: settings,
    );

    final Person stored = people.get('a')!;
    final int expectedAge = DateTime.now().year - 2000;
    expect(stored.manualAge, anyOf(expectedAge, expectedAge - 1));
    expect(stored.manualAgeUpdatedAt, isNotNull);
    expect(stored.age, stored.manualAge);
    expect(stored.legacyBirthDate, isNull);
  });

  test('keeps an age that was already entered by hand', () async {
    final (Box<Person> people, Box<dynamic> settings) = await openBoxes();
    final Person person = buildPerson(
      id: 'b',
      legacyBirthDate: DateTime(2000, 1, 2),
      manualAge: 31,
    );
    await people.put(person.id, person);

    await PersonMigrations.convertBirthDatesToAges(
      people: people,
      settings: settings,
    );

    final Person stored = people.get('b')!;
    expect(stored.manualAge, 31);
    expect(stored.legacyBirthDate, isNull);
  });

  test('clears a leftover hebrew date even without a gregorian one', () async {
    final (Box<Person> people, Box<dynamic> settings) = await openBoxes();
    final Person person = buildPerson(id: 'c', legacyHebrewBirthYear: 5760);
    await people.put(person.id, person);

    await PersonMigrations.convertBirthDatesToAges(
      people: people,
      settings: settings,
    );

    expect(people.get('c')!.legacyHebrewBirthYear, isNull);
  });

  test('runs only once', () async {
    final (Box<Person> people, Box<dynamic> settings) = await openBoxes();
    await people.put('d', buildPerson(id: 'd'));

    await PersonMigrations.convertBirthDatesToAges(
      people: people,
      settings: settings,
    );
    expect(settings.get(PersonMigrations.birthDateMigrationKey), isTrue);

    // A birth date that somehow appears afterwards is left alone, proving the
    // pass is skipped rather than repeated on every launch.
    final Person late = people.get('d')!
      ..legacyBirthDate = DateTime(1990, 5, 5);
    await late.save();

    await PersonMigrations.convertBirthDatesToAges(
      people: people,
      settings: settings,
    );

    expect(people.get('d')!.legacyBirthDate, isNotNull);
  });
}
