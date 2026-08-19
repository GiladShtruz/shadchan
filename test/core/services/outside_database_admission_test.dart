import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// "הוספת שם מחוץ למאגר" writes a card with `hidden: true`. Nothing used to
/// clear that flag, so a card the matchmaker went on to fill in never appeared
/// in המאגר שלי.
void main() {
  late Directory directory;
  late Box<Person> people;
  late PersonRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('outside_db_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    people = await Hive.openBox<Person>('people');
    await people.clear();
    await Hive.box<dynamic>('settings').clear();
    repository = PersonRepository(people);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<Person> seedOutsideDatabase() async {
    final Person person = _outsidePerson();
    await people.put(person.id, person);
    return person;
  }

  test('a name and a gender alone stay out of the database', () {
    final Person person = _outsidePerson();
    expect(PersonRepository.hasDetailsBeyondName(person), isFalse);
  });

  test('a phone number alone is enough to join the database', () async {
    final Person person = await seedOutsideDatabase();

    person.phone = '0501234567';
    await repository.update(person);

    expect(repository.getById(person.id)!.hidden, isFalse);
    // `filter` is what המאגר שלי reads, and it drops every hidden record.
    expect(repository.filter().map((Person p) => p.id), contains(person.id));
  });

  test('so is an age, a city, a description or a photo', () async {
    for (final void Function(Person) fill in <void Function(Person)>[
      (Person p) => p.setManualAge(27),
      (Person p) => p.city = 'ירושלים',
      (Person p) => p.description = 'בחור מקסים',
      (Person p) => p.photosPaths = <String>['/tmp/a.jpg'],
      (Person p) => p.heightCm = 180,
      (Person p) => p.inquiryContactPhone = '0501234567',
    ]) {
      await people.clear();
      final Person person = await seedOutsideDatabase();
      fill(person);
      await repository.update(person);
      expect(
        repository.getById(person.id)!.hidden,
        isFalse,
        reason: 'a filled detail should admit the card',
      );
    }
  });

  test('an edit that fills in nothing leaves the card outside', () async {
    final Person person = await seedOutsideDatabase();

    // Renaming is not "filling in details" — the name is all the card ever had.
    person.firstName = 'הילל';
    await repository.update(person);

    expect(repository.getById(person.id)!.hidden, isTrue);
  });

  test('admitToDatabase lets an empty card in on request', () async {
    final Person person = await seedOutsideDatabase();

    await repository.admitToDatabase(person.id);

    final Person stored = repository.getById(person.id)!;
    expect(stored.hidden, isFalse);
    expect(stored.needsReview, isFalse);
  });

  test('admitToDatabase does nothing to a card already in it', () async {
    final Person person = _outsidePerson()..hidden = false;
    await people.put(person.id, person);
    final DateTime before = person.updatedAt;

    await repository.admitToDatabase(person.id);

    expect(repository.getById(person.id)!.updatedAt, before);
  });
}

Person _outsidePerson() {
  final DateTime now = DateTime(2026, 8, 18);
  return Person(
    id: 'outside-person',
    firstName: 'הלל',
    lastName: '',
    gender: Gender.male,
    hidden: true,
    needsReview: true,
    createdAt: now,
    updatedAt: now,
  );
}
