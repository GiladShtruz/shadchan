import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// A notice with an undo answers something just done with a thumb: it sits at
/// the bottom of the screen and leaves after two and a half seconds, whatever
/// the caller asked for. A plain notice keeps its place at the top.
void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('an undo notice sits at the bottom and leaves after 2.5s', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await pumpHost(tester);
    final double screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    AppNotice.show(
      context,
      'הרעיון נמחק',
      actionLabel: 'ביטול',
      onAction: () {},
      duration: const Duration(seconds: 10),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('הרעיון נמחק'), findsOneWidget);
    expect(
      tester.getCenter(find.text('הרעיון נמחק')).dy,
      greaterThan(screenHeight / 2),
    );

    // Still up just before 2.5s from when it was drawn…
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('הרעיון נמחק'), findsOneWidget);
    // …and gone just after, although ten seconds were asked for.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('הרעיון נמחק'), findsNothing);
  });

  testWidgets('a notice without an undo stays at the top', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await pumpHost(tester);
    final double screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    AppNotice.show(context, 'נשמר');
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getCenter(find.text('נשמר')).dy, lessThan(screenHeight / 2));
    await tester.pump(const Duration(seconds: 5));
  });
}
