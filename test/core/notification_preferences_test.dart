import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/notification_preferences.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('notif_prefs');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  group('notification kinds', () {
    test('every server kind belongs to a switch', () {
      expect(
        NotificationPreferences.categoryOf('reminder'),
        NotificationCategory.ideas,
      );
      expect(
        NotificationPreferences.categoryOf('cardCreated'),
        NotificationCategory.cardFriends,
      );
      expect(
        NotificationPreferences.categoryOf('matchmakerJoined'),
        NotificationCategory.newMatchmakers,
      );
      expect(
        NotificationPreferences.categoryOf('connectionRequest'),
        NotificationCategory.access,
      );
      expect(
        NotificationPreferences.categoryOf('birthday'),
        NotificationCategory.celebrations,
      );
      // A kind nobody mapped is a system notice, never unswitchable.
      expect(
        NotificationPreferences.categoryOf('somethingNew'),
        NotificationCategory.system,
      );
    });

    test('everything is on until switched off, and the choice is kept', () {
      final NotificationPreferences prefs = NotificationPreferences.instance;
      expect(prefs.wantsKind('cardCreated'), isTrue);
      final List<List<String>> published = <List<String>>[];
      NotificationPreferences.onChanged = published.add;
      prefs.set(NotificationCategory.cardFriends, enabled: false);
      expect(prefs.wantsKind('cardCreated'), isFalse);
      expect(prefs.wantsKind('cardUpdated'), isFalse);
      expect(prefs.wantsKind('accessRequest'), isTrue);
      expect(published.single, <String>['cardFriends']);
      prefs.set(NotificationCategory.cardFriends, enabled: true);
      expect(prefs.wantsKind('cardCreated'), isTrue);
      NotificationPreferences.onChanged = null;
    });
  });

  group('photos that may not leave the app', () {
    Person friend() => Person(
      id: 'f1',
      firstName: 'נועה',
      lastName: 'כהן',
      gender: Gender.female,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      photosPaths: <String>['/photos/card_owner1_a.jpg', '/photos/mine.jpg'],
    );

    test('a card that says so keeps the owner\'s photos out of a share', () {
      expect(CardPhotoPrivacy.privateIn(<String, dynamic>{}), isFalse);
      expect(
        CardPhotoPrivacy.privateIn(<String, dynamic>{'photosShareable': false}),
        isTrue,
      );
      expect(CardPhotoPrivacy.shareable(friend()), hasLength(2));
      CardPhotoPrivacy.set('f1', private: true);
      expect(CardPhotoPrivacy.holdsBack(friend()), isTrue);
      // The matchmaker's own photo of the friend is theirs to share.
      expect(CardPhotoPrivacy.shareable(friend()), <String>[
        '/photos/mine.jpg',
      ]);
      CardPhotoPrivacy.set('f1', private: false);
      expect(CardPhotoPrivacy.shareable(friend()), hasLength(2));
    });
  });
}
