import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/partner_space_screen.dart';
import 'package:shadchan/services/partner_space.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// The couple space (2026-11-20): two personal databases and one tie.
void main() {
  late Directory dir;
  late Box<dynamic> settings;
  late Box<Person> peopleBox;
  late PersonRepository people;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('partner_space_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(MaritalStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(RegionAdapter());
    settings = await Hive.openBox<dynamic>('settings');
    peopleBox = await Hive.openBox<Person>('people');
    people = PersonRepository(peopleBox);
  });

  tearDownAll(() async {
    await PartnerSpace.stop();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app(Widget home) => MultiProvider(
    providers: <ChangeNotifierProvider<ChangeNotifier>>[
      ChangeNotifierProvider<PersonRepository>.value(value: people),
      ChangeNotifierProvider<UserProfileProvider>(
        create: (_) => UserProfileProvider(settings),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    ),
  );

  Partnership pair(String status, {String from = 'partner'}) => Partnership(
    id: 'me_partner',
    uids: const <String>['me', 'partner'],
    fromUid: from,
    toUid: from == 'me' ? 'partner' : 'me',
    status: status,
    names: const <String, String>{'me': 'גלעד', 'partner': 'שירה לוי'},
  );

  test(
    'the one tie shown: active before an invitation, never one that ended',
    () {
      final Partnership ended = pair('ended');
      final Partnership pending = pair('pending');
      final Partnership active = pair('active');
      expect(Partnership.currentOf(<Partnership>[ended]), isNull);
      expect(Partnership.currentOf(<Partnership>[pending, active]), active);
      expect(Partnership.idFor('b', 'a'), 'a_b');
    },
  );

  test(
    'the partner sees the database, not drafts, hidden records or the married',
    () {
      final DateTime now = DateTime(2026);
      Person p(String id, {bool hidden = false, ProfileStatus? status}) =>
          Person(
            id: id,
            firstName: id,
            lastName: '',
            gender: Gender.male,
            createdAt: now,
            updatedAt: now,
            hidden: hidden,
          )..profileStatus = status ?? ProfileStatus.available;
      final List<Person> out = PartnerSpace.publishable(<Person>[
        p('a'),
        p('hidden', hidden: true),
        p('married', status: ProfileStatus.mazelTov),
        p('busy', status: ProfileStatus.busy),
      ]);
      expect(out.map((Person x) => x.id), <String>['a', 'busy']);
    },
  );

  testWidgets('an invitation is answered on the phone it was sent to', (
    tester,
  ) async {
    PartnerSpace.debugSet(uid: 'me', partnership: pair('pending'));
    await tester.pumpWidget(app(const PartnerSpaceScreen()));
    await tester.pump();
    expect(find.text('שירה לוי מזמין/ה אותך למרחב זוגי'), findsOneWidget);
    expect(find.text('אישור ופתיחת המרחב הזוגי'), findsOneWidget);
    expect(find.textContaining('ההערות האישיות, ההיסטוריה'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the open space: both, and the three ways in', (tester) async {
    PartnerSpace.debugSet(uid: 'me', partnership: pair('active'));
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(const PartnerSpaceScreen()));
    await tester.pump();
    expect(find.text('המרחב הזוגי שלנו'), findsOneWidget);
    expect(find.text('המאגר של שירה'), findsOneWidget);
    expect(find.text('הצ\'אט הזוגי'), findsOneWidget);
    expect(find.text('הרעיונות המשותפים'), findsOneWidget);
    expect(find.text('ביטול המרחב הזוגי'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    "the partner's database: a friend known to both appears once, marked",
    (tester) async {
      final DateTime now = DateTime(2026);
      final Person mineShared = Person(
        id: 'm1',
        firstName: 'נועה',
        lastName: 'כהן',
        gender: Gender.female,
        phone: '0501234567',
        createdAt: now,
        updatedAt: now,
      );
      final Person mineOnly = Person(
        id: 'm2',
        firstName: 'דנה',
        lastName: 'לוי',
        gender: Gender.female,
        createdAt: now,
        updatedAt: now,
      );
      await tester.runAsync(() async {
        await peopleBox.put(mineShared.id, mineShared);
        await peopleBox.put(mineOnly.id, mineOnly);
      });
      SharedCard card(String id, String first, {String? identity}) {
        final Map<String, dynamic> data = <String, dynamic>{
          'ownerUid': 'partner',
          'ownerName': 'שירה לוי',
          'personId': id,
          'firstName': first,
          'lastName': 'כהן',
          'gender': 'female',
          'description': '',
          'photoPaths': <String>[],
          'tags': <String>[],
          'status': 'available',
          'identity': identity,
        };
        return SharedCard.fromMap(data)!;
      }

      PartnerSpace.debugSet(
        uid: 'me',
        partnership: pair('active'),
        cards: <SharedCard>[
          card('p1', 'נועה', identity: PhoneIdentity.hash('0501234567')),
          card('p2', 'אורית'),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(const PartnerDatabaseScreen()));
      await tester.pump();
      // The partner's database by default.
      expect(find.text('אורית כהן'), findsOneWidget);
      expect(find.text('נועה כהן'), findsOneWidget);
      expect(find.textContaining('מוכר לשניכם'), findsOneWidget);
      expect(find.text('דנה לוי'), findsNothing);
      // Both together: Noa once, Dana from mine.
      await tester.tap(find.text('שניהם'));
      await tester.pump();
      expect(find.text('נועה כהן'), findsOneWidget);
      expect(find.text('דנה לוי'), findsOneWidget);
      expect(find.text('אורית כהן'), findsOneWidget);
      // Searching narrows both.
      await tester.enterText(find.byType(TextField), 'דנה');
      await tester.pump();
      expect(find.text('דנה לוי'), findsOneWidget);
      expect(find.text('אורית כהן'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
