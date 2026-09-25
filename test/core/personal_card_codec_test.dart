import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

Person _card() {
  final DateTime now = DateTime(2026, 1, 1);
  return Person(
    id: 'personal-card',
    firstName: 'דניאל',
    lastName: 'לוי',
    gender: Gender.male,
    birthDate: DateTime(1999, 4, 7),
    religiousLevel: ReligiousLevel.datiLeumi,
    city: 'מודיעין',
    description: 'אוהב טיולים',
    heightCm: 180,
    maritalStatus: MaritalStatus.single,
    region: Region.center,
    preferredMinAge: 22,
    preferredMaxAge: 28,
    preferredRegions: const <Region>[Region.center, Region.jerusalem],
    preferredReligiousLevels: const <ReligiousLevel>[ReligiousLevel.datiLeumi],
    profileStatus: ProfileStatus.onBreak,
    // Things that must never travel.
    phone: '050-1111111',
    notes: 'הערה פרטית',
    inquiryContactName: 'אמא',
    inquiryContactPhone: '050-2222222',
    additionalContacts: const <MatchContact>[
      MatchContact(name: 'דודה', phone: '050-3333333'),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('PhoneIdentity', () {
    test('local and international forms are one number', () {
      expect(PhoneIdentity.hash('050-1234567'), isNotNull);
      expect(
        PhoneIdentity.hash('050-1234567'),
        PhoneIdentity.hash('+972 50 123 4567'),
      );
      expect(
        PhoneIdentity.hash('0501234567'),
        PhoneIdentity.hash('00972501234567'),
      );
      expect(
        PhoneIdentity.hash('0501234567'),
        isNot(PhoneIdentity.hash('0501234568')),
      );
    });

    test('a number too short to identify anybody has no identity', () {
      expect(PhoneIdentity.hash(''), isNull);
      expect(PhoneIdentity.hash('1234'), isNull);
      expect(PhoneIdentity.hash(null), isNull);
    });
  });

  group('PersonalCardCodec', () {
    test('only the card travels — never the matchmaker-private fields', () {
      final Map<String, Object?> remote = PersonalCardCodec.toRemote(
        _card(),
        ownerUid: 'u1',
        photoPaths: const <String>['personalCards/u1/a.jpg'],
      );
      for (final String private in <String>[
        'phone',
        'notes',
        'inquiryContactName',
        'inquiryContactPhone',
        'additionalContacts',
        'source',
        'isFavorite',
        'importBatchId',
      ]) {
        expect(remote.containsKey(private), isFalse, reason: private);
      }
      expect(remote['dateOfBirth'], '1999-04-07');
      expect(remote['status'], 'onBreak');
    });

    test('the fields written are exactly the ones the rules allow', () {
      final Map<String, Object?> remote = PersonalCardCodec.toRemote(
        _card(),
        ownerUid: 'u1',
        photoPaths: const <String>[],
      );
      final String rules = File('firestore.rules').readAsStringSync();
      final String block = rules.substring(
        rules.indexOf('match /personalCards/{ownerUid}'),
      );
      final String list = block.substring(
        block.indexOf('hasOnly(['),
        block.indexOf('])'),
      );
      final Set<String> allowed = RegExp(
        r"'([A-Za-z]+)'",
      ).allMatches(list).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(remote.keys.toSet(), allowed);
    });

    test('applying a card keeps what the matchmaker wrote', () {
      final Map<String, Object?> remote = PersonalCardCodec.toRemote(
        _card(),
        ownerUid: 'u1',
        photoPaths: const <String>[],
      );
      final DateTime now = DateTime(2026, 1, 1);
      final Person local = Person(
        id: 'local',
        firstName: 'דני',
        lastName: '',
        gender: Gender.male,
        manualAge: 30,
        phone: '050-9999999',
        notes: 'הערה שלי',
        inquiryContactName: 'השכן',
        createdAt: now,
        updatedAt: now,
      );
      PersonalCardCodec.applyTo(local, Map<String, dynamic>.from(remote));

      expect(local.fullName, 'דניאל לוי');
      expect(local.birthDate, DateTime(1999, 4, 7));
      expect(local.manualAge, isNull);
      expect(local.region, Region.center);
      expect(local.preferredRegions, <Region>[Region.center, Region.jerusalem]);
      // The matchmaker's own.
      expect(local.phone, '050-9999999');
      expect(local.notes, 'הערה שלי');
      expect(local.inquiryContactName, 'השכן');
      expect(
        PersonalCardCodec.statusOf(Map<String, dynamic>.from(remote)),
        ProfileStatus.onBreak,
      );
    });
  });
}
