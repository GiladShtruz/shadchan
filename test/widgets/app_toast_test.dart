import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/app_toast.dart';

/// The thing that replaced the celebration dialogs.
///
/// The three rules worth a test are the three that made the old dialogs a
/// problem: it must not block the page, there must never be two of them, and it
/// must go away on its own.
void main() {
  Widget host(void Function(BuildContext) onReady) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => onReady(context),
              child: const Text('פעולה'),
            ),
          ),
        ),
      ),
    );
  }

  tearDown(AppToast.dismiss);

  testWidgets('it says its piece and disappears by itself', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host((BuildContext context) => AppToast.show(context, 'נוסף חבר למאגר')),
    );

    await tester.tap(find.text('פעולה'));
    await tester.pump();
    expect(find.text('נוסף חבר למאגר'), findsOneWidget);

    // Nothing to press, and nothing between the reader and the page: the
    // button underneath is still there and still live.
    expect(find.text('פעולה'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'פעולה'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );

    await tester.pump(AppToast.visibleFor);
    await tester.pump();
    expect(find.text('נוסף חבר למאגר'), findsNothing);
  });

  testWidgets('the mark rides at the end of the line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        (BuildContext context) =>
            AppToast.show(context, '30 חברים נוספו למאגר', emoji: '🙌'),
      ),
    );

    await tester.tap(find.text('פעולה'));
    await tester.pump();

    // One string, so the bidi algorithm puts the emoji where the sentence
    // finishes — which in Hebrew is its left-hand side.
    expect(find.text('30 חברים נוספו למאגר 🙌'), findsOneWidget);

    // Let the auto-dismiss timer run out; a pending timer fails the test.
    await tester.pump(AppToast.visibleFor);
  });

  testWidgets('a second message replaces the first, never queues behind it', (
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(host((BuildContext context) => ctx = context));

    await tester.tap(find.text('פעולה'));
    await tester.pump();

    AppToast.show(ctx, 'ראשון');
    await tester.pump();
    AppToast.show(ctx, 'שני');
    await tester.pump();

    expect(find.text('ראשון'), findsNothing);
    expect(find.text('שני'), findsOneWidget);

    await tester.pump(AppToast.visibleFor);
  });

  testWidgets('tapping it puts it away early', (WidgetTester tester) async {
    await tester.pumpWidget(
      host((BuildContext context) => AppToast.show(context, 'הרעיון נשמר')),
    );

    await tester.tap(find.text('פעולה'));
    await tester.pump();
    expect(find.text('הרעיון נשמר'), findsOneWidget);

    await tester.tap(find.text('הרעיון נשמר'));
    await tester.pump();
    expect(find.text('הרעיון נשמר'), findsNothing);
  });
}
