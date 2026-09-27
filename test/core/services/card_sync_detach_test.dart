import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// A matchmaker's edits of a synced card stay theirs and never detach it —
/// the owner's own changes keep arriving (see `card_sync_engine_test.dart`).
/// Nothing the matchmaker does is put to the owner.
void main() {
  late Directory directory;
  late Box<Person> people;
  late PersonRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('card_detach_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    Hive.registerAdapter(MaritalStatusAdapter());
    Hive.registerAdapter(MatchContactAdapter());
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

  Future<Person> seedSynced() async {
    final DateTime now = DateTime(2026, 1, 1);
    final Person person = Person(
      id: 'p1',
      firstName: 'דניאל',
      lastName: 'לוי',
      gender: Gender.male,
      phone: '050-1234567',
      description: 'מהכרטיס',
      cardOwnerUid: 'owner',
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveSynced(person);
    return person;
  }

  test('a save that does not touch the card keeps it synced', () async {
    final Person person = await seedSynced();
    person.isFavorite = true;
    await repository.update(person);
    expect(person.isCardSynced, isTrue);
  });

  test('editing the card and saving keeps it following its owner', () async {
    final Person person = await seedSynced();
    person.description = 'כתבתי בעצמי';
    await repository.update(person);
    expect(person.cardSyncDetached, isFalse);
    expect(person.isCardSynced, isTrue);
    expect(person.description, 'כתבתי בעצמי');
  });

  test('a friend is found by any form of their number', () async {
    await seedSynced();
    expect(
      repository.findByPhoneHash(PhoneIdentity.hash('+972 50 123 4567')!)?.id,
      'p1',
    );
    expect(repository.findByCardOwner('owner')?.id, 'p1');
  });

  test('a status the matchmaker sets stays on their own copy', () async {
    final Person person = await seedSynced();
    await repository.updateProfileStatus(person.id, ProfileStatus.busy);
    expect(repository.getById(person.id)?.profileStatus, ProfileStatus.busy);
    expect(person.isCardSynced, isTrue);
  });
}
