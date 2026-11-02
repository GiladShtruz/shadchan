import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  late Directory temp;
  late Box<Person> people;
  late Box<dynamic> settings;
  late Box<PersonEvent> events;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('personal_privacy_');
    Hive.init(temp.path);
    Hive.registerAdapter(PersonAdapter());
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    Hive.registerAdapter(PersonEventAdapter());
    Hive.registerAdapter(PersonEventTypeAdapter());
    people = await Hive.openBox<Person>('people');
    settings = await Hive.openBox<dynamic>('settings');
    events = await Hive.openBox<PersonEvent>('person_events');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() async {
    await people.clear();
    await settings.clear();
  });
  Person card() => Person(
    id: 'card',
    firstName: 'יעל',
    lastName: 'לוי',
    gender: Gender.female,
    description: 'א'.padRight(35, 'א'),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test(
    'unverified or revoked personal copies disappear from lists, search and direct lookup immediately',
    () async {
      final linked = card()..cardOwnerUid = 'owner-uid';
      await people.put(linked.id, linked);
      final repository = PersonRepository(people)..requireVerifiedCardAccess();
      expect(repository.getAll(), isEmpty);
      expect(repository.search('יעל'), isEmpty);
      expect(repository.filter(), isEmpty);
      expect(repository.getById(linked.id), isNull);
      repository.setVerifiedCardOwners({'owner-uid'});
      expect(repository.getById(linked.id), isNotNull);
      expect(repository.search('יעל'), hasLength(1));
      repository.setVerifiedCardOwners({});
      expect(repository.getById(linked.id), isNull);
      expect(repository.databaseCount, 0);
      // Revocation can still reach and clean the underlying local copy.
      expect(
        repository.findByCardOwner('owner-uid', forCardSync: true),
        isNotNull,
      );
      repository.dispose();
    },
  );

  test(
    'revocation removes owner-authored history while preserving the matchmaker notes',
    () async {
      final repository = PersonRepository(people, null, events);
      for (final entry in [
        (PersonEventType.cardSynced, 'remote'),
        (PersonEventType.cardSyncedMinor, 'remote-minor'),
        (PersonEventType.note, 'my-note'),
      ]) {
        await events.put(
          entry.$2,
          PersonEvent(
            id: entry.$2,
            personId: 'card',
            type: entry.$1,
            text: entry.$2,
            createdAt: DateTime.now(),
          ),
        );
      }
      await repository.forgetPersonalCardHistory('card');
      expect(events.values.map((e) => e.id), ['my-note']);
      repository.dispose();
    },
  );

  test(
    'three calendar months clamp month ends and review need not change status time',
    () {
      expect(
        PersonalAreaProvider.reviewDue(
          DateTime(2026, 1, 31),
          DateTime(2026, 4, 29),
        ),
        false,
      );
      expect(
        PersonalAreaProvider.reviewDue(
          DateTime(2026, 1, 31),
          DateTime(2026, 4, 30),
        ),
        true,
      );
      expect(
        PersonalAreaProvider.reviewDue(
          DateTime(2026, 11, 30),
          DateTime(2027, 2, 28),
        ),
        true,
      );
    },
  );

  test(
    'a no-op autosave does not move the last edit; real edits and status changes do',
    () async {
      final provider = PersonalCardProvider(settings);
      await provider.save(card());
      final first = provider.card!.updatedAt;
      await provider.save(provider.card!);
      expect(provider.editRevision, 1);
      expect(provider.card!.updatedAt, first);
      provider.card!.city = 'ירושלים';
      await provider.save(provider.card!);
      expect(provider.editRevision, 2);
      await provider.setStatus(ProfileStatus.busy);
      expect(provider.editRevision, 3);
      await provider.setStatus(ProfileStatus.busy);
      expect(provider.editRevision, 3);
      final json = BackupService.personToJson(provider.card!);
      expect(json.containsKey('privateLooking'), false);
      provider.dispose();
    },
  );

  test(
    'personal invitations preserve only a validated token and remain distinct from legacy invitations',
    () {
      const token =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final invite = InviteLinkService.parse(
        'shadchan-invite://join?from=owner123&personalInvite=$token&role=matchmaker',
      );
      expect(invite?.personalToken, token);
      expect(InviteLinkService.parse('from=owner123')?.personalToken, isNull);
      expect(
        InviteLinkService.parse('from=owner123&personalInvite=invalid'),
        isNull,
      );
    },
  );
}
