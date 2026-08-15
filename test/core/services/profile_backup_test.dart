import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/profile_backup.dart';
import 'package:shadchan/utils/enums.dart';

/// The profile is the one part of the backup that merges *field by field*
/// rather than by id, and the failure that matters is silent in both
/// directions: too eager and a restore overwrites what the matchmaker typed
/// during onboarding minutes earlier, too shy and the personal card — the only
/// thing here worth restoring — never comes back.
void main() {
  late Directory directory;
  late Box<dynamic> box;
  late UserProfileProvider profile;

  /// Stands in for the Cloud Storage download. Returns a path for anything in
  /// [available] and null for everything else, which is how a photo that
  /// failed to download is reported.
  Future<String?> Function(String) resolver(Set<String> available) {
    return (String basename) async =>
        available.contains(basename) ? '/photos/$basename' : null;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('shadchan_profile_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await box.clear();
    profile = UserProfileProvider(box);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  group('toJson', () {
    test('Writes photos as basenames, not device paths', () async {
      await profile.saveProfile(
        name: 'גילה',
        gender: Gender.female,
        isSingle: true,
        photoPath:
            '/data/user/0/com.gilad.shadchan/app_flutter/photos/me_1.jpg',
      );
      await profile.setPersonalCardContent(
        text: 'בת 27 מירושלים',
        photoPaths: <String>[
          '/data/user/0/com.gilad.shadchan/app_flutter/photos/card_1.jpg',
          '/data/user/0/com.gilad.shadchan/app_flutter/photos/card_2.jpg',
        ],
      );

      final Map<String, Object?> json = ProfileBackup.toJson(profile);

      // An absolute path is meaningless on another phone, and on iOS it even
      // changes after a reinstall — which would also mark the profile as
      // changed on every launch and re-upload it forever.
      expect(json['photo'], 'me_1.jpg');
      expect(json['personalCardPhotos'], <String>['card_1.jpg', 'card_2.jpg']);
      expect(json['name'], 'גילה');
      expect(json['gender'], 'female');
      expect(json['isSingle'], isTrue);
    });

    test('An empty profile round-trips without inventing values', () {
      final Map<String, Object?> json = ProfileBackup.toJson(profile);

      expect(json['name'], isNull);
      expect(json['gender'], isNull);
      expect(json['photo'], isNull);
      expect(json['personalCard'], isNull);
      expect(json['personalCardPhotos'], isEmpty);
      expect(json['hasMaritalStatus'], isFalse);
    });

    test('photoNames collects the profile picture and the card photos', () {
      expect(
        ProfileBackup.photoNames(<String, Object?>{
          'photo': 'me_1.jpg',
          'personalCardPhotos': <String>['card_1.jpg', 'card_2.jpg'],
        }),
        <String>['me_1.jpg', 'card_1.jpg', 'card_2.jpg'],
      );

      // The uploader asks this for every profile, including empty ones.
      expect(
        ProfileBackup.photoNames(<String, Object?>{
          'photo': null,
          'personalCardPhotos': <String>[],
        }),
        isEmpty,
      );
    });
  });

  group('applyMissing', () {
    test(
      'Never overwrites a name, gender or card that already exist',
      () async {
        await profile.saveProfile(
          name: 'גילה',
          gender: Gender.female,
          isSingle: true,
        );
        await profile.setPersonalCardContent(
          text: 'הכרטיס שכתבתי כאן',
          photoPaths: const <String>[],
        );

        final int filled = await ProfileBackup.applyMissing(
          profile,
          <String, Object?>{
            'name': 'שם אחר לגמרי',
            'gender': 'male',
            'isSingle': false,
            'personalCard': 'כרטיס ישן מהענן',
            'personalCardPhotos': <String>['old.jpg'],
          },
          resolvePhoto: resolver(<String>{'old.jpg'}),
        );

        // Onboarding already asked for these on this phone. A restore that
        // answered them again from an older backup would silently undo what the
        // matchmaker typed minutes ago.
        expect(filled, 0);
        expect(profile.name, 'גילה');
        expect(profile.gender, Gender.female);
        expect(profile.isSingle, isTrue);
        expect(profile.personalCard, 'הכרטיס שכתבתי כאן');
        expect(profile.personalCardPhotos, isEmpty);
      },
    );

    test('Restores the card onto a profile that has none', () async {
      await profile.saveProfile(
        name: 'גילה',
        gender: Gender.female,
        isSingle: true,
      );

      final int filled = await ProfileBackup.applyMissing(
        profile,
        <String, Object?>{
          'name': 'גילה',
          'gender': 'female',
          'isSingle': true,
          'personalCard': 'בת 27 מירושלים',
          'personalCardPhotos': <String>['card_1.jpg'],
        },
        resolvePhoto: resolver(<String>{'card_1.jpg'}),
      );

      // This is the case the whole feature exists for: onboarding never asks
      // for the card, so it is exactly what is still empty after a reinstall.
      expect(filled, 1);
      expect(profile.personalCard, 'בת 27 מירושלים');
      expect(profile.personalCardPhotos, <String>['/photos/card_1.jpg']);
    });

    test('Rebuilds the profile picture as a local path', () async {
      await profile.saveProfile(
        name: 'גילה',
        gender: Gender.female,
        isSingle: false,
      );

      final int filled = await ProfileBackup.applyMissing(
        profile,
        <String, Object?>{'photo': 'me_1.jpg'},
        resolvePhoto: resolver(<String>{'me_1.jpg'}),
      );

      expect(filled, 1);
      expect(profile.photoPath, '/photos/me_1.jpg');
    });

    test(
      'A photo that will not download is left out, not stored broken',
      () async {
        await profile.saveProfile(
          name: 'גילה',
          gender: Gender.female,
          isSingle: true,
        );

        final int filled = await ProfileBackup.applyMissing(
          profile,
          <String, Object?>{
            'photo': 'gone.jpg',
            'personalCard': 'בת 27 מירושלים',
            'personalCardPhotos': <String>['here.jpg', 'gone.jpg'],
          },
          resolvePhoto: resolver(<String>{'here.jpg'}),
        );

        // A path to a file that is not there is worse than no path — dangling
        // paths in the JSON export are the whole reason photos went to Storage.
        expect(profile.photoPath, isNull);
        expect(profile.personalCardPhotos, <String>['/photos/here.jpg']);
        // The card itself still lands; one missing image does not cost the text.
        expect(profile.personalCard, 'בת 27 מירושלים');
        expect(filled, 1);
      },
    );

    test(
      'Fills name and gender only into a profile that has neither',
      () async {
        final int filled = await ProfileBackup.applyMissing(
          profile,
          <String, Object?>{
            'name': 'גילה',
            'gender': 'female',
            'isSingle': true,
          },
          resolvePhoto: resolver(const <String>{}),
        );

        expect(filled, 1);
        expect(profile.name, 'גילה');
        expect(profile.gender, Gender.female);
        expect(profile.isSingle, isTrue);
        expect(profile.isOnboarded, isTrue);
      },
    );

    test('An empty cloud profile changes nothing', () async {
      await profile.saveProfile(
        name: 'גילה',
        gender: Gender.female,
        isSingle: true,
      );

      final int filled =
          await ProfileBackup.applyMissing(profile, <String, Object?>{
            'name': null,
            'gender': null,
            'photo': null,
            'personalCard': null,
            'personalCardPhotos': <String>[],
          }, resolvePhoto: resolver(const <String>{}));

      expect(filled, 0);
      expect(profile.name, 'גילה');
    });

    test('A malformed document is survived rather than thrown on', () async {
      final int filled = await ProfileBackup.applyMissing(
        profile,
        <String, Object?>{
          'name': 42,
          'gender': 'not a gender',
          'isSingle': 'yes',
          'photo': <String>['not a string'],
          'personalCardPhotos': 'not a list',
        },
        resolvePhoto: resolver(const <String>{}),
      );

      expect(filled, 0);
      expect(profile.name, isNull);
      expect(profile.gender, isNull);
    });
  });
}
