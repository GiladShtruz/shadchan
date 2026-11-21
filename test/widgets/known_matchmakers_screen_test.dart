import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_share.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/known_matchmakers_screen.dart';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';

/// "שדכנים שאני מכיר": the two groups, the compact rows, the profile — and
/// that nothing on any of it says more than the matchmaker already knew.
void main() {
  late Directory directory;
  late Box<Person> people;
  late CardAccessProvider access;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('known_matchmakers_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(RegionAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    people = await Hive.openBox<Person>('people');
    await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await MatchmakerShares.stop();
  });

  tearDownAll(() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // A temp dir.
    }
  });

  final DateTime now = DateTime.now();
  final List<CardHelper> helpers = <CardHelper>[
    CardHelper(
      uid: 'a',
      name: 'אבי כהן',
      phoneHash: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      lastActiveAt: now,
      databaseCount: 40,
    ),
    CardHelper(
      uid: 'b',
      name: 'בתיה לוי',
      phoneHash: 'bbbbbbbbbbbbbbbbbbbbbbbb',
      lastActiveAt: now.subtract(const Duration(days: 3)),
      databaseCount: 12,
    ),
    const CardHelper(
      uid: 'c',
      name: 'כרמל',
      phoneHash: 'cccccccccccccccccccccccc',
      mutual: true,
    ),
  ];

  MatchmakerShare row(
    String owner,
    String reader,
    MatchmakerShareMode mode, {
    int count = 0,
    String ownerName = '',
  }) => MatchmakerShare(
    ownerUid: owner,
    readerUid: reader,
    mode: mode,
    count: count,
    ownerName: ownerName,
  );

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<PersonRepository>(
          create: (_) => PersonRepository(people),
        ),
        ChangeNotifierProvider<UserProfileProvider>(
          create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
        ),
        ChangeNotifierProvider<CardAccessProvider>(
          create: (BuildContext context) {
            access = CardAccessProvider(
              people: context.read<PersonRepository>(),
              enabled: false,
            )..debugSetHelpers(helpers);
            return access;
          },
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );
  }

  testWidgets('two groups, sharing first, compact rows, no numbers', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MatchmakerShares.debugSet('me', <MatchmakerShare>[
      row('b', 'me', MatchmakerShareMode.all, count: 7),
      row('me', 'x', MatchmakerShareMode.requested),
    ]);
    await tester.pumpWidget(wrap(const KnownMatchmakersScreen()));
    await tester.pump();

    expect(find.text('משתפים איתי / מחוברים · 1'), findsOneWidget);
    expect(
      find.text('עדיין לא משתפים · 1 ביקשו ממך שיתוף · 3'),
      findsOneWidget,
    );
    final double connected = tester
        .getTopLeft(find.text('משתפים איתי / מחוברים · 1'))
        .dy;
    final double others = tester
        .getTopLeft(find.text('עדיין לא משתפים · 1 ביקשו ממך שיתוף · 3'))
        .dy;
    expect(connected < others, isTrue);

    // A sharing matchmaker: activity and database size, and what each shares.
    expect(find.text('בתיה לוי'), findsOneWidget);
    expect(find.text('לפני 3 ימים · 12 חברים במאגר'), findsOneWidget);
    expect(find.text('משתף/ת איתך 7 · את/ה 0'), findsOneWidget);
    expect(find.text('למאגר'), findsOneWidget);
    // Not sharing yet: the database size is not shown, and the action is
    // to open a share — never a vague "connect".
    expect(find.text('פעיל היום'), findsOneWidget);
    expect(find.text('להתחבר'), findsNothing);
    expect(find.text('שיתוף מאגר'), findsNWidgets(2));
    // The one who asked me is answered with a share, never a yes/no.
    expect(find.text('לשתף בחזרה'), findsOneWidget);

    // No phone number anywhere on the screen.
    for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
      expect(
        RegExp(r'\d{7,}').hasMatch(text.data ?? ''),
        isFalse,
        reason: text.data,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('before sharing, the profile shows only who and how active', (
    WidgetTester tester,
  ) async {
    MatchmakerShares.debugSet('me', const <MatchmakerShare>[]);
    await tester.pumpWidget(wrap(const KnownMatchmakerProfileScreen(uid: 'a')));
    await tester.pump();
    expect(find.text('אבי כהן'), findsOneWidget);
    expect(find.text('פעיל היום'), findsOneWidget);
    expect(find.text('40 חברים במאגר'), findsNothing);
    expect(find.text('בקשת שיתוף מאבי'), findsOneWidget);
    expect(find.text('מה אני משתף/ת עם אבי'), findsOneWidget);
  });

  testWidgets('once they share, the profile adds the figures and the way in', (
    WidgetTester tester,
  ) async {
    MatchmakerShares.debugSet('me', <MatchmakerShare>[
      row('a', 'me', MatchmakerShareMode.selected, count: 5),
    ]);
    await tester.pumpWidget(wrap(const KnownMatchmakerProfileScreen(uid: 'a')));
    await tester.pump();
    expect(find.text('40 חברים במאגר'), findsOneWidget);
    expect(find.text('משתף/ת איתך 5 כרטיסים'), findsOneWidget);
    expect(find.text('למאגר של אבי · 5'), findsOneWidget);
  });

  testWidgets('a stranger\'s profile shows nothing about them', (
    WidgetTester tester,
  ) async {
    MatchmakerShares.debugSet('me', const <MatchmakerShare>[]);
    await tester.pumpWidget(
      wrap(const KnownMatchmakerProfileScreen(uid: 'stranger')),
    );
    await tester.pump();
    expect(find.text('השדכן/ית לא נמצא/ת באנשי הקשר שלך.'), findsOneWidget);
    expect(find.text('שיתוף מאגר'), findsNothing);
  });

  test(
    'matchmaker_contact_found counts only the new ones, as a band',
    () async {
      final List<(String, Map<String, Object>)> events =
          <(String, Map<String, Object>)>[];
      Analytics.debugSink = (String name, Map<String, Object> params) =>
          events.add((name, params));
      addTearDown(() => Analytics.debugSink = null);
      await Hive.box<dynamic>('settings').clear();

      MatchmakerShares.noteContactsFound(<String>['a', 'b']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      MatchmakerShares.noteContactsFound(<String>['a', 'b']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      MatchmakerShares.noteContactsFound(<String>['a', 'b', 'c']);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.map((e) => e.$1), <String>[
        'matchmaker_contact_found',
        'matchmaker_contact_found',
      ]);
      expect(events.first.$2, <String, Object>{
        'count': 'n1_4',
        'first_time': 1,
      });
      expect(events.last.$2, <String, Object>{
        'count': 'n1_4',
        'first_time': 0,
      });
    },
  );
}
