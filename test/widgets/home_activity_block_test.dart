import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/home_activity_block.dart';

/// The home screen's activity area.
///
/// Two figures, one switch and a way into the rule. Everything that used to sit
/// here — three windows at once, a community meter, a shared weekly target —
/// is gone on purpose: this is a workspace, and the numbers screen is one tap
/// away.
void main() {
  Widget wrap(Widget child, {double width = 360, double textScale = 1.0}) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CommunityProvider>(
            create: (_) => CommunityProvider(),
          ),
          // `connect: () async {}` keeps `Firebase.initializeApp` out of the
          // fake-async zone, where it never completes. `isSignedIn` is false
          // either way, which is the signed-out state under test.
          ChangeNotifierProvider<AccountProvider>(
            create: (_) => AccountProvider(connect: () async {}),
          ),
        ],
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(14), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('it shows your activity, the community, and nothing else', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int opened = 0;
    await tester.pumpWidget(wrap(HomeActivityBlock(onOpen: () => opened++)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('נתונים'), findsOneWidget);
    expect(find.text('הפעילות שלך'), findsOneWidget);
    // No account in a widget test, so the community column is the invitation
    // rather than a figure. See the signed-out test below.
    expect(find.text('הצטרפו לקהילת השדכנים'), findsOneWidget);

    // The three windows are a switch, not three columns.
    for (final String label in <String>['השבוע', 'החודש', 'כל הזמנים']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('היום'), findsNothing);

    // Nothing that belongs on the full screen leaks onto the home page.
    expect(find.textContaining('טבלת הדירוג'), findsNothing);
    expect(find.textContaining('יעד'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('נתונים'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('the scoring rule is reachable without leaving the page', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int opened = 0;
    await tester.pumpWidget(wrap(HomeActivityBlock(onOpen: () => opened++)));
    await tester.pump();

    await tester.tap(find.text(ActivityPoints.howItIsCountedTitle));
    await tester.pumpAndSettle();

    // The sheet, not the activity screen: the explanation must not be a way
    // into somewhere else by accident.
    expect(opened, 0);
    expect(find.text('שיטת הניקוד:'), findsOneWidget);
    for (final String line in ActivityPoints.scoringLines) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
  });

  testWidgets('the switch changes the window without opening the screen', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int opened = 0;
    await tester.pumpWidget(wrap(HomeActivityBlock(onOpen: () => opened++)));
    await tester.pump();

    await tester.tap(find.text('כל הזמנים'));
    await tester.pump();

    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without an account the community half is an invitation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(HomeActivityBlock(onOpen: () {})));
    await tester.pump();

    // Their own numbers are untouched — the gate withholds the community, not
    // anything that was ever theirs.
    expect(find.text('הפעילות שלך'), findsOneWidget);
    expect(find.text('פעילות הקהילה'), findsNothing);

    expect(find.text('הצטרפו לקהילת השדכנים'), findsOneWidget);
    expect(find.text('התחברות'), findsOneWidget);
  });

  for (final double width in <double>[320, 360, 430]) {
    testWidgets('it fits ${width.toInt()}px at 1.5x text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(HomeActivityBlock(onOpen: () {}), width: width, textScale: 1.5),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('הפעילות שלך'), findsOneWidget);
    });
  }
}
