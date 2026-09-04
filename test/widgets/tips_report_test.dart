import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/tips_list_screen.dart';

/// The flag on a published tip.
///
/// Play's user-generated-content policy asks for a way to report published
/// content *from where it is read*. The general support form has always been
/// reachable from the menu, but nothing on this page pointed at it — so what
/// matters here is that the flag is on a matchmaker's tip and is not on the
/// ones that ship with the app, which there is nobody to report.
///
/// **The cache is seeded in `setUp`, never inside a `testWidgets` body.**
/// `testWidgets` runs its body in a fake-async zone where Hive's disk write
/// never completes: awaiting one hangs the test, and leaving one unawaited
/// hangs the *next* test instead, when its `clear()` queues behind a write
/// that can no longer finish.
void main() {
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('shadchan_tips_report_test');
    Hive.init(p.join(temp.path, 'hive'));
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    await Hive.box<dynamic>('settings').clear();
  });

  Future<void> pumpTips(WidgetTester tester) async {
    // Tall enough that every card is built in one frame, so the assertions can
    // talk about the whole page instead of what happens to be on screen.
    tester.view.physicalSize = const Size(1200, 40000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Box<dynamic> settings = Hive.box<dynamic>('settings');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TipsProvider>(
            create: (_) => TipsProvider(settings, enabled: false),
          ),
          ChangeNotifierProvider<UserProfileProvider>(
            create: (_) => UserProfileProvider(settings),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: TipsListScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a tip a matchmaker published', () {
    setUp(() async {
      await Hive.box<dynamic>('settings').put(
        'tips.approvedCache',
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 't1',
            'text': 'תזמון הוא חלק מהשידוך.',
            'authorName': 'רבקה לוי',
            'authorUid': 'u1',
            'status': 'approved',
            'createdAt': 1,
          },
        ]),
      );
    });

    testWidgets('carries a report action, and it is the only one on the page', (
      WidgetTester tester,
    ) async {
      await pumpTips(tester);

      expect(find.text('תזמון הוא חלק מהשידוך.'), findsOneWidget);
      expect(find.byIcon(Icons.outlined_flag), findsOneWidget);
    });
  });

  testWidgets('the tips that ship with the app carry none', (
    WidgetTester tester,
  ) async {
    await pumpTips(tester);

    expect(find.byIcon(Icons.outlined_flag), findsNothing);
  });
}
