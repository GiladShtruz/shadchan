import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// A synced card becomes the matchmaker's own only when they edit the card and
/// save — never on a save that leaves the card alone.
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

  test('editing the card and saving detaches it', () async {
    final Person person = await seedSynced();
    person.description = 'כתבתי בעצמי';
    await repository.update(person);
    expect(person.cardSyncDetached, isTrue);
    expect(person.cardOwnerUid, 'owner');
  });

  test('a friend is found by any form of their number', () async {
    await seedSynced();
    expect(
      repository.findByPhoneHash(PhoneIdentity.hash('+972 50 123 4567')!)?.id,
      'p1',
    );
    expect(repository.findByCardOwner('owner')?.id, 'p1');
  });

  test('a status the matchmaker sets is put to the owner', () async {
    final Person person = await seedSynced();
    ProfileStatus? reported;
    repository.onStatusChangedForCardOwner = (Person p, ProfileStatus s) async {
      reported = s;
    };
    await repository.updateProfileStatus(person.id, ProfileStatus.busy);
    expect(reported, ProfileStatus.busy);
  });
}
