import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/utils/gender_text.dart';
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
        ChangeNotifierProvider<PersonalCardProvider>(
          create: (_) => PersonalCardProvider(Hive.box<dynamic>('settings')),
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

  testWidgets('"שתף הכל" asks once, in the agreed words, before opening', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    NetworkSharing.debugReset();
    NetworkSharing.finishOnboarding();
    await tester.pumpWidget(harness(const SharingSettingsScreen()));
    await tester.pump();
    await tester.tap(find.text('שתף הכל'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(SharingSettingsScreen.addWarning.forGender(null)),
      findsOneWidget,
    );
    // Declining changes nothing.
    await tester.tap(find.text('ביטול'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(NetworkSharing.mode, ShareMode.none);
    // Agreeing shares — from now on.
    await tester.tap(find.text('שתף הכל'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('לשתף'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(NetworkSharing.mode, ShareMode.all);
    expect(NetworkSharing.since, isNotNull);
    NetworkSharing.debugReset();
  });

  testWidgets(
    'the single has one general switch, on by default, and is told what off means',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(const OnwardShareSwitch()));
      await tester.pump();
      expect(find.text(OnwardShareSwitch.title), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      // The explanation: not public, not unlimited, view only, not onward.
      await tester.tap(find.text('מה זה אומר?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('אינו ציבורי או בלתי מוגבל'), findsOneWidget);
      expect(find.textContaining('לצפייה בלבד'), findsWidgets);
      expect(find.textContaining('אינו ממשיך'), findsOneWidget);
      await tester.tap(find.text('הבנתי'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Turning it off says what stays and what goes.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(OnwardShareSwitch.offExplanation), findsWidgets);
      await tester.tap(find.text('ביטול'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
