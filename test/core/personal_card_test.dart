import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/personal_card_service.dart';
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

    test('a chosen home page wins over the area last used', () {
      WorkspaceStore.resetForTest();
      WorkspaceStore.setMatchmakerEnabled(true);
      WorkspaceStore.setLastArea(WorkArea.matchmaker);
      expect(WorkspaceStore.homeArea, isNull);
      expect(WorkspaceStore.launchArea, WorkArea.matchmaker);

      WorkspaceStore.setHomeArea(WorkArea.personal);
      expect(WorkspaceStore.launchArea, WorkArea.personal);

      // A card-only user has only one area, whatever was chosen before.
      WorkspaceStore.setMatchmakerEnabled(false);
      WorkspaceStore.setHomeArea(WorkArea.matchmaker);
      expect(WorkspaceStore.launchArea, WorkArea.personal);
      WorkspaceStore.setMatchmakerEnabled(true);
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
    test(
      'an older card with six photos keeps all six until the owner chooses',
      () async {
        final DateTime now = DateTime(2026, 1, 1);
        final List<String> six = <String>[
          for (int i = 0; i < 6; i++) 'p$i.jpg',
        ];
        final Person legacy = Person(
          id: PersonalCardProvider.cardId,
          firstName: 'נועה',
          lastName: 'כהן',
          gender: Gender.female,
          photosPaths: six,
          createdAt: now,
          updatedAt: now,
        );
        // Written as an older version wrote it: straight into the settings box.
        await settings.put(
          'personalCard.person',
          jsonEncode(BackupService.personToJson(legacy)),
        );

        final PersonalCardProvider cards = PersonalCardProvider(settings);
        expect(cards.card?.photosPaths, six);
        expect(cards.needsPhotoChoice, isTrue);

        // An unrelated save carries the six on: nothing chooses for the owner.
        await cards.setStatus(ProfileStatus.onBreak);
        expect(cards.card?.photosPaths, six);
        // Adding a seventh is still refused.
        expect(
          () => cards.save(
            cards.card!.copyWith(photosPaths: <String>[...six, 'x.jpg']),
          ),
          throwsArgumentError,
        );

        await cards.keepPhotos(const <String>['p5.jpg', 'p1.jpg', 'p2.jpg']);
        expect(cards.card?.photosPaths, const <String>[
          'p5.jpg',
          'p1.jpg',
          'p2.jpg',
        ]);
        expect(cards.needsPhotoChoice, isFalse);
      },
    );

    test('a draft from the old short card keeps every old photo', () async {
      final UserProfileProvider profile = UserProfileProvider(settings);
      await profile.saveProfile(
        name: 'דן',
        lastName: 'לוי',
        gender: Gender.male,
        isSingle: true,
      );
      await profile.setPersonalCardContent(
        text: 'טקסט',
        photoPaths: const <String>['1.jpg', '2.jpg', '3.jpg', '4.jpg', '5.jpg'],
      );
      final Person draft = PersonalCardProvider(settings).draftFrom(profile);
      expect(draft.photosPaths.length, 5);
    });
  });

  group('a live card', () {
    final DateTime now = DateTime(2026, 1, 1);
    Person card({List<String> photos = const <String>[], String? text}) =>
        Person(
          id: 'c',
          firstName: 'נועה',
          lastName: 'כהן',
          gender: Gender.female,
          photosPaths: photos,
          description: text,
          createdAt: now,
          updatedAt: now,
        );
    final String twenty = List<String>.generate(
      20,
      (int i) => 'מילה$i',
    ).join(' ');
    final String nineteen = List<String>.generate(
      19,
      (int i) => 'מילה$i',
    ).join(' ');

    test('needs a photo and twenty words, both', () {
      expect(PersonalCardCodec.isActive(card()), isFalse);
      expect(
        PersonalCardCodec.isActive(card(photos: <String>['a.jpg'])),
        isFalse,
      );
      expect(PersonalCardCodec.isActive(card(text: twenty)), isFalse);
      expect(
        PersonalCardCodec.isActive(
          card(photos: <String>['a.jpg'], text: nineteen),
        ),
        isFalse,
      );
      expect(
        PersonalCardCodec.isActive(
          card(photos: <String>['a.jpg'], text: twenty),
        ),
        isTrue,
      );
      // Long text with no spaces is one word, not a card.
      expect(
        PersonalCardCodec.isActive(
          card(photos: <String>['a.jpg'], text: 'א' * 300),
        ),
        isFalse,
      );
    });

    test('says what is still missing', () {
      expect(
        PersonalCardCodec.draftHint(
          card(photos: <String>['a.jpg'], text: twenty),
        ),
        isNull,
      );
      expect(
        PersonalCardCodec.draftHint(card(text: twenty)),
        contains('תמונה אחת'),
      );
      expect(
        PersonalCardCodec.draftHint(
          card(photos: <String>['a.jpg'], text: nineteen),
        ),
        contains('עוד מילה אחת'),
      );
      final String both = PersonalCardCodec.draftHint(card())!;
      expect(both, contains('תמונה אחת'));
      expect(both, contains('עוד 20 מילים'));
    });

    test('counts words the way the server does', () {
      expect(PersonalCardCodec.wordCount(null), 0);
      expect(PersonalCardCodec.wordCount('   '), 0);
      expect(PersonalCardCodec.wordCount('  אחת  שתיים\n\nשלוש '), 3);
    });
  });
}
