import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/known_matchmakers_screen.dart';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/matchmaker_connections.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';

/// "שדכנים שאני מכיר": the three groups, the compact rows, the basic profile
/// — and that nothing on any of it says more than the matchmaker already
/// knew.
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
    await MatchmakerConnections.stop();
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

  MatchmakerConnection row(
    String from,
    String to,
    MatchmakerConnectionStatus status,
  ) => MatchmakerConnection(
    id: MatchmakerConnection.idFor(from, to),
    fromUid: from,
    toUid: to,
    status: status,
    names: <String, String>{'x': 'יוסי'},
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

  testWidgets('three groups, connected first, compact rows, no numbers', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MatchmakerConnections.debugSet('me', <MatchmakerConnection>[
      row('me', 'b', MatchmakerConnectionStatus.approved),
      row('x', 'me', MatchmakerConnectionStatus.pending),
    ]);
    await tester.pumpWidget(wrap(const KnownMatchmakersScreen()));
    await tester.pump();

    expect(find.text('מחוברים · 1'), findsOneWidget);
    expect(find.text('בקשות חיבור · 1'), findsOneWidget);
    expect(find.text('שדכנים מאנשי הקשר · 2'), findsOneWidget);
    final double connected = tester.getTopLeft(find.text('מחוברים · 1')).dy;
    final double requests = tester.getTopLeft(find.text('בקשות חיבור · 1')).dy;
    final double contacts = tester
        .getTopLeft(find.text('שדכנים מאנשי הקשר · 2'))
        .dy;
    expect(connected < requests && requests < contacts, isTrue);

    // A compact row: name, then activity and database size.
    expect(find.text('בתיה לוי'), findsOneWidget);
    expect(find.text('מחוברים · לפני 3 ימים · 12 חברים במאגר'), findsOneWidget);
    expect(find.text('פעיל היום · 40 חברים במאגר'), findsOneWidget);
    // A request from somebody outside the contacts carries their own name.
    expect(find.text('יוסי'), findsOneWidget);
    expect(find.text('אישור'), findsOneWidget);
    // Two contacts to connect with — never connected without a yes.
    expect(find.text('להתחבר'), findsNWidgets(2));

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

  testWidgets('the basic profile offers "להתחבר" and shares nothing', (
    WidgetTester tester,
  ) async {
    MatchmakerConnections.debugSet('me', const <MatchmakerConnection>[]);
    await tester.pumpWidget(wrap(const KnownMatchmakerProfileScreen(uid: 'a')));
    await tester.pump();
    expect(find.text('אבי כהן'), findsOneWidget);
    expect(find.text('פעיל היום'), findsOneWidget);
    expect(find.text('40 חברים במאגר'), findsOneWidget);
    expect(find.text('להתחבר'), findsOneWidget);
    expect(
      find.textContaining('לא משתף כרטיסים או מידע מהמאגר'),
      findsOneWidget,
    );
  });

  testWidgets('a request waiting for me is answered from the profile', (
    WidgetTester tester,
  ) async {
    MatchmakerConnections.debugSet('me', <MatchmakerConnection>[
      row('a', 'me', MatchmakerConnectionStatus.pending),
    ]);
    await tester.pumpWidget(wrap(const KnownMatchmakerProfileScreen(uid: 'a')));
    await tester.pump();
    expect(find.text('אישור החיבור'), findsOneWidget);
    expect(find.text('לא עכשיו'), findsOneWidget);
    expect(find.text('להתחבר'), findsNothing);
  });

  testWidgets('a stranger\'s profile shows nothing about them', (
    WidgetTester tester,
  ) async {
    MatchmakerConnections.debugSet('me', const <MatchmakerConnection>[]);
    await tester.pumpWidget(
      wrap(const KnownMatchmakerProfileScreen(uid: 'stranger')),
    );
    await tester.pump();
    expect(find.text('השדכן/ית לא נמצא/ת באנשי הקשר שלך.'), findsOneWidget);
    expect(find.text('להתחבר'), findsNothing);
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

      MatchmakerConnections.noteContactsFound(<String>['a', 'b']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      MatchmakerConnections.noteContactsFound(<String>['a', 'b']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      MatchmakerConnections.noteContactsFound(<String>['a', 'b', 'c']);
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
