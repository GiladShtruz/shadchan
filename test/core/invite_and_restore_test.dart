import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  late Directory dir;
  late Box<dynamic> settings;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('invite_restore_test_');
    Hive.init(dir.path);
    settings = await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await settings.clear();
    InviteLinkService.resetForTest();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('InviteLinkService.parse', () {
    test('reads the inviter out of the app link', () {
      final PendingInvite? invite = InviteLinkService.parse(
        'shadchan-invite://join?from=abcDEF123456&name=%D7%99%D7%A6%D7%97%D7%A7',
      );
      expect(invite?.fromUid, 'abcDEF123456');
      expect(invite?.name, 'יצחק');
    });

    test('reads the Play Store referrer, encoded or not', () {
      expect(
        InviteLinkService.parse('from%3DabcDEF123456%26name%3Dx')?.fromUid,
        'abcDEF123456',
      );
      expect(
        InviteLinkService.parse('from=abcDEF123456&name=x')?.fromUid,
        'abcDEF123456',
      );
    });

    test('ignores a link with no inviter, or a malformed one', () {
      expect(InviteLinkService.parse('utm_source=google-play'), isNull);
      expect(InviteLinkService.parse('from=../../x'), isNull);
      expect(InviteLinkService.parse(''), isNull);
    });

    test('nothing is pending until something arrives, and clearing clears', () {
      expect(InviteLinkService.pending, isNull);
      InviteLinkService.clear();
      expect(InviteLinkService.pending, isNull);
    });
  });

  group('deleting and restoring the card', () {
    Person card() {
      final DateTime now = DateTime(2026, 1, 1);
      return Person(
        id: 'x',
        firstName: 'נועה',
        lastName: 'כהן',
        gender: Gender.female,
        profileStatus: ProfileStatus.busy,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('a deleted card is kept, and is not a live card', () async {
      final PersonalCardProvider cards = PersonalCardProvider(settings);
      await cards.save(card());
      expect(cards.hasCard, isTrue);

      await cards.markDeleted();
      expect(cards.hasCard, isFalse);
      expect(cards.isDeleted, isTrue);
      expect(cards.card?.fullName, 'נועה כהן');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final PersonalCardProvider reopened = PersonalCardProvider(settings);
      expect(reopened.isDeleted, isTrue);
    });

    test('a restored card comes back as available', () async {
      final PersonalCardProvider cards = PersonalCardProvider(settings);
      await cards.save(card());
      await cards.markDeleted();
      final Person? restored = await cards.restore();
      expect(cards.hasCard, isTrue);
      expect(cards.isDeleted, isFalse);
      expect(restored?.profileStatus, ProfileStatus.available);
    });
  });
}
