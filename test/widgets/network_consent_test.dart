import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/sharing_settings_screen.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/onward_share_switch.dart';

/// The two moments a card is let out to the connected matchmakers: the
/// matchmaker choosing "share the whole database", and the single letting
/// their matchmaker show their own card. Both are asked, in words, first.
void main() {
  late Directory directory;
  late Box<Person> people;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('network_consent_');
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

  tearDownAll(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A temp dir.
    }
  });

  Widget harness(Widget child) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<PersonRepository>(
          create: (_) => PersonRepository(people),
        ),
        ChangeNotifierProvider<CardAccessProvider>(
          create: (BuildContext context) => CardAccessProvider(
            people: context.read<PersonRepository>(),
            enabled: false,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('"share the whole database" asks first, in the agreed words', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    NetworkSharing.setMode(ShareMode.none);
    await tester.pumpWidget(harness(const SharingSettingsScreen()));
    await tester.pump();
    await tester.tap(find.text('לשתף את כל המאגר'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(SharingSettingsScreen.allConfirmation), findsOneWidget);
    // Declining changes nothing.
    await tester.tap(find.text('ביטול'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(NetworkSharing.mode, ShareMode.none);
    // Agreeing shares.
    await tester.tap(find.text('לשתף את כל המאגר'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('לשתף'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(NetworkSharing.mode, ShareMode.all);
    NetworkSharing.setMode(ShareMode.none);
  });

  testWidgets(
    'the single is told it is not public, and that the control stays theirs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const CardAccess row = CardAccess(
        ownerUid: 'single1',
        matchmakerUid: 'mm1',
        status: CardAccessStatus.approved,
        requestedBy: 'matchmaker',
        shareOnwardRequested: true,
      );
      await tester.pumpWidget(
        harness(const OnwardShareSwitch(row: row, name: 'יונתן')),
      );
      await tester.pump();
      expect(find.textContaining('מבקש/ת את האישור שלך'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('לא נפתח לציבור'), findsOneWidget);
      expect(find.textContaining('השליטה נשארת אצלך'), findsOneWidget);
      expect(find.textContaining('כל פנייה תעבור דרך יונתן'), findsOneWidget);
      await tester.tap(find.text('לא עכשיו'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
