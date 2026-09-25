import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  late Directory dir;
  late Box<dynamic> settings;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('personal_card_test_');
    Hive.init(dir.path);
    settings = await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await settings.clear();
    WorkspaceStore.resetForTest();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('WorkspaceStore', () {
    test('an install from before the choice is a matchmaker', () {
      expect(WorkspaceStore.entryRoute, isNull);
      expect(WorkspaceStore.matchmakerEnabled, isTrue);
      expect(WorkspaceStore.lastArea, WorkArea.matchmaker);
    });

    test('a card-only user always opens on the personal area', () {
      WorkspaceStore.setMatchmakerEnabled(false);
      WorkspaceStore.setLastArea(WorkArea.matchmaker);
      expect(WorkspaceStore.lastArea, WorkArea.personal);
    });

    test('the last area is remembered once the matchmaker is on', () {
      WorkspaceStore.setLastArea(WorkArea.personal);
      expect(WorkspaceStore.lastArea, WorkArea.personal);
      WorkspaceStore.setLastArea(WorkArea.matchmaker);
      expect(WorkspaceStore.lastArea, WorkArea.matchmaker);
    });

    test('a value written as text reads back the same', () async {
      await settings.put('workspace.matchmakerEnabled', 'false');
      await settings.put('workspace.entry', 'cardOwner');
      WorkspaceStore.resetForTest();
      expect(WorkspaceStore.matchmakerEnabled, isFalse);
      expect(WorkspaceStore.entryRoute, EntryRoute.cardOwner);
    });
  });

  group('birth date', () {
    test('the age is whole years and turns on the birthday', () {
      final DateTime born = DateTime(2000, 5, 10);
      expect(Person.ageOn(born, DateTime(2026, 5, 9)), 25);
      expect(Person.ageOn(born, DateTime(2026, 5, 10)), 26);
    });

    test('it wins over a manual age and survives a backup', () {
      final DateTime now = DateTime(2026, 1, 1);
      final Person person = Person(
        id: 'p',
        firstName: 'דניאל',
        lastName: 'לוי',
        gender: Gender.male,
        manualAge: 40,
        birthDate: DateTime(2000, 1, 1),
        createdAt: now,
        updatedAt: now,
      );
      expect(person.age, Person.ageOn(DateTime(2000, 1, 1), DateTime.now()));

      final Person? back = BackupService.personFromJson(
        BackupService.personToJson(person),
      );
      expect(back?.birthDate, DateTime(2000, 1, 1));
    });
  });

  group('PersonalCardProvider', () {
    test('a first draft carries over the old short card and photos', () async {
      final UserProfileProvider profile = UserProfileProvider(settings);
      await profile.saveProfile(
        name: 'דניאל',
        lastName: 'לוי',
        gender: Gender.male,
        isSingle: true,
      );
      await profile.setPersonalCardContent(
        text: 'אוהב טיולים',
        photoPaths: const <String>['a.jpg', 'b.jpg'],
      );

      final PersonalCardProvider cards = PersonalCardProvider(settings);
      expect(cards.hasCard, isFalse);
      final Person draft = cards.draftFrom(profile);
      expect(draft.fullName, 'דניאל לוי');
      expect(draft.description, 'אוהב טיולים');
      expect(draft.photosPaths, const <String>['a.jpg', 'b.jpg']);
      expect(draft.maritalStatus, MaritalStatus.single);
    });

    test('a saved card reads back after a restart', () async {
      final PersonalCardProvider cards = PersonalCardProvider(settings);
      final DateTime now = DateTime(2026, 1, 1);
      await cards.save(
        Person(
          id: 'anything',
          firstName: 'נועה',
          lastName: 'כהן',
          gender: Gender.female,
          birthDate: DateTime(1998, 3, 3),
          religiousLevel: ReligiousLevel.datiLeumi,
          region: Region.jerusalem,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(cards.card?.id, PersonalCardProvider.cardId);

      // The write is scheduled on the root zone; let it land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final PersonalCardProvider reopened = PersonalCardProvider(settings);
      expect(reopened.card?.fullName, 'נועה כהן');
      expect(reopened.card?.birthDate, DateTime(1998, 3, 3));
      expect(reopened.card?.region, Region.jerusalem);

      await reopened.setStatus(ProfileStatus.onBreak);
      expect(reopened.card?.profileStatus, ProfileStatus.onBreak);
    });
  });
}
