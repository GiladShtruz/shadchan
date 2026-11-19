import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/screens/account_gate_screens.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/services/couple_recovery.dart';
import 'package:shadchan/services/couple_workspace_service.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/offline_banner.dart';

/// A sync whose first read never answers — a weak connection.
class _HangingSync extends SyncProvider {
  _HangingSync(super.settings) : super(enabled: false);

  @override
  Future<void> start() => Completer<void>().future;
}

/// A couple's connection must never leave a phone stuck: no endless spinner,
/// and an unfinished merge always offers a way back.
void main() {
  late Directory directory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('couple_recovery_');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() {
    ConnectivityStatus.debugSetOffline(false);
    CoupleWorkspaceService.clear();
    CoupleRecovery.reset();
  });

  tearDownAll(() async {
    CoupleWorkspaceService.clear();
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A temp dir.
    }
  });

  Widget harness(SyncProvider sync) =>
      ChangeNotifierProvider<SyncProvider>.value(
        value: sync,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          builder: (BuildContext context, Widget? child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
          home: const AccountLoadingScreen(),
        ),
      );

  testWidgets('a read that never answers ends in "ניסיון חוזר", not a spinner', (
    WidgetTester tester,
  ) async {
    final SyncProvider sync = _HangingSync(Hive.box<dynamic>('settings'));
    await tester.pumpWidget(harness(sync));
    await tester.pump();
    expect(find.text('ניסיון חוזר'), findsNothing);
    await tester.pump(
      AccountLoadingScreen.firstTimeout + const Duration(seconds: 1),
    );
    await tester.pump();
    expect(find.text('המאגר עדיין לא נטען'), findsOneWidget);
    expect(find.text('ניסיון חוזר'), findsOneWidget);
    expect(find.text('התנתקות'), findsOneWidget);
  });

  testWidgets('an unfinished couple connection says so and offers the way back', (
    WidgetTester tester,
  ) async {
    CoupleWorkspaceService.membership.value = <String, dynamic>{
      'databaseUid': 'a',
      'members': <String>['a', 'b'],
      'state': 'merging',
      'operation': 'code',
    };
    final SyncProvider sync = _HangingSync(Hive.box<dynamic>('settings'));
    await tester.pumpWidget(harness(sync));
    await tester.pump();
    expect(find.text('החיבור הזוגי עוד לא הושלם'), findsOneWidget);
    expect(find.textContaining('שום נתון לא נמחק'), findsOneWidget);
    expect(find.text('ביטול החיבור וחזרה למאגר שלי'), findsOneWidget);
    expect(find.text('ניסיון חוזר'), findsOneWidget);
    // Once it is undone (or finished) the screen follows.
    CoupleWorkspaceService.membership.value = null;
    await tester.pump();
    expect(find.text('החיבור הזוגי עוד לא הושלם'), findsNothing);
    await tester.pump(
      AccountLoadingScreen.firstTimeout + const Duration(seconds: 1),
    );
  });

  testWidgets('while the merge runs, a line says why edits wait', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? routed) => Directionality(
          textDirection: TextDirection.rtl,
          child: OfflineBanner(child: routed!),
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    expect(find.text(OfflineBanner.pairingText), findsNothing);
    CoupleWorkspaceService.membership.value = <String, dynamic>{
      'databaseUid': 'a',
      'state': 'merging',
      'operation': 'code',
    };
    await tester.pumpAndSettle();
    expect(find.text(OfflineBanner.pairingText), findsOneWidget);
    CoupleWorkspaceService.membership.value = <String, dynamic>{
      'databaseUid': 'a',
      'state': 'active',
      'operation': 'code',
    };
    await tester.pumpAndSettle();
    expect(find.text(OfflineBanner.pairingText), findsNothing);
  });
}
