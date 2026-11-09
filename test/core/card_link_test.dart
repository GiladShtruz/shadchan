import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/dialogs/invite_card_friends_sheet.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/card_link_consent.dart';
import 'package:shadchan/services/notification_feed.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/sync_quiet.dart';

Person _person(
  String id,
  String first,
  String last, {
  Gender gender = Gender.male,
  String? phone,
  bool hidden = false,
  String? cardOwnerUid,
}) {
  final DateTime now = DateTime(2026, 11, 1);
  return Person(
    id: id,
    firstName: first,
    lastName: last,
    gender: gender,
    phone: phone,
    createdAt: now,
    updatedAt: now,
  )
    ..hidden = hidden
    ..cardOwnerUid = cardOwnerUid;
}

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<Person> peopleBox;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('card_link_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    settings = await Hive.openBox<dynamic>('settings');
    peopleBox = await Hive.openBox<Person>('people');
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await settings.clear();
    await peopleBox.clear();
    CardLinkConsent.forgetCache();
  });

  group('the new-card notice for a friend kept by hand', () {
    test('asks to sync, in the friend\'s gender', () {
      expect(
        NotificationFeed.newCardSyncQuestion(
          _person('a', 'יוסי', 'לוי'),
          'owner-a',
        ),
        'יוסי לוי הוסיף כרטיס אישי. רוצה לסנכרן עם הכרטיס הקיים?',
      );
      expect(
        NotificationFeed.newCardSyncQuestion(
          _person('b', 'נועה', 'כהן', gender: Gender.female),
          'owner-b',
        ),
        'נועה כהן הוסיפה כרטיס אישי. רוצה לסנכרן עם הכרטיס הקיים?',
      );
    });

    test('says nothing for a friend not in the database, hidden, or already '
        'following the card', () {
      expect(NotificationFeed.newCardSyncQuestion(null, 'o'), isNull);
      expect(
        NotificationFeed.newCardSyncQuestion(
          _person('c', 'דן', 'לוי', hidden: true),
          'o',
        ),
        isNull,
      );
      expect(
        NotificationFeed.newCardSyncQuestion(
          _person('d', 'דן', 'לוי', cardOwnerUid: 'o'),
          'o',
        ),
        isNull,
      );
    });
  });

  test('consent to link a card is kept per owner and can be withdrawn', () async {
    expect(CardLinkConsent.isConfirmed('owner-1'), isFalse);
    CardLinkConsent.confirm('owner-1');
    expect(CardLinkConsent.isConfirmed('owner-1'), isTrue);
    expect(CardLinkConsent.isConfirmed('owner-2'), isFalse);
    // Lands on disk and survives the in-memory copy being dropped.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    CardLinkConsent.forgetCache();
    expect(settings.get(CardLinkConsent.key), contains('owner-1'));
    expect(CardLinkConsent.isConfirmed('owner-1'), isTrue);
    CardLinkConsent.withdraw('owner-1');
    expect(CardLinkConsent.isConfirmed('owner-1'), isFalse);
  });

  test('the invitation list is the friends kept by hand that WhatsApp can '
      'reach, without anyone who already keeps a card', () {
    final List<Person> people = <Person>[
      _person('1', 'שרה', 'לוי', phone: '0521234567'),
      _person('2', 'אבי', 'כהן', phone: '0527654321'),
      _person('3', 'דנה', 'רז'), // no number
      _person('4', 'רון', 'גל', phone: '0529999999', hidden: true),
      _person('5', 'טל', 'בר', phone: '0528888888', cardOwnerUid: 'x'),
      _person('6', 'מור', 'שי', phone: '0527777777'),
    ];
    final List<Person> list = InviteCardFriendsSheet.candidates(
      people,
      withCard: <String>{PhoneIdentity.hash('0527777777')!},
    );
    expect(list.map((Person p) => p.id), <String>['2', '1']);
  });

  test('a card arriving by sync is reported as sync, never as work', () async {
    final PersonRepository people = PersonRepository(peopleBox);
    final List<bool> seen = <bool>[];
    people.addListener(() => seen.add(SyncQuiet.active));
    await people.saveSynced(
      _person('s', 'יעל', 'כהן', cardOwnerUid: 'owner-s'),
    );
    people.notifySyncChange();
    expect(seen, isNotEmpty);
    expect(seen.every((bool quiet) => quiet), isTrue);
    expect(SyncQuiet.active, isFalse);
  });
}
