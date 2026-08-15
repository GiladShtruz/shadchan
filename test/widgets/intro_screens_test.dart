import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/screens/intro_screens.dart';
import 'package:shadchan/utils/app_theme.dart';

/// The welcome exists to say one thing that cannot be discovered by using the
/// app: the database is private. These check that it actually says it, that it
/// ends, and that it can be skipped — a first-run screen that traps somebody is
/// worse than no first-run screen.
void main() {
  Widget wrap(VoidCallback onFinished) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: IntroScreens(onFinished: onFinished),
      ),
    );
  }

  testWidgets('it walks to the end and finishes exactly once', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int finished = 0;
    await tester.pumpWidget(wrap(() => finished++));
    await tester.pump();

    expect(find.text('האפליקציה הזו נבנתה בשבילך'), findsOneWidget);

    // Every page but the last carries on; the last one starts the app.
    for (int i = 0; i < IntroScreens.pages.length - 1; i++) {
      expect(find.text('המשך'), findsOneWidget, reason: 'page $i');
      await tester.tap(find.text('המשך'));
      await tester.pumpAndSettle();
    }

    expect(find.text('המשך'), findsNothing);
    expect(find.text('מתחילים'), findsOneWidget);
    expect(finished, 0);
    await tester.tap(find.text('מתחילים'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('privacy is stated, not implied', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(() {}));
    await tester.pump();

    final String all = IntroScreens.pages
        .map((IntroPage page) => '${page.title} ${page.body}')
        .join(' ');
    expect(all, contains('אף משתמש אחר לא יכול לראות'));
    expect(all, contains('בלי לבקש'));
    expect(all, contains('פרטי'));
    // Short by design: a first-run tour nobody reads is worse than none.
    for (final IntroPage page in IntroScreens.pages) {
      expect(page.body.length, lessThan(200), reason: page.title);
    }
  });

  testWidgets('it can always be skipped', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int finished = 0;
    await tester.pumpWidget(wrap(() => finished++));
    await tester.pump();

    await tester.tap(find.text('דילוג'));
    await tester.pump();
    expect(finished, 1);
  });
}
