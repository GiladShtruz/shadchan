import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_next_step.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/widgets/home_action_area.dart';

void main() {
  setUp(NextStepStore.reset);

  Widget wrap(Widget child, {double width = 390, double textScale = 1}) {
    final ThemeData base = AppTheme.lightTheme();
    return MaterialApp(
      theme: base.copyWith(
        textTheme: HomeTypography.scale(base.textTheme, dark: false),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  NextStepInputs inputs() => NextStepInputs(
    friends: 120,
    now: DateTime(2026, 11, 6),
    gender: Gender.female,
    requestableCardFriends: 3,
    weekStart: DateTime(2026, 11, 1),
  );

  for (final double width in <double>[320, 390]) {
    for (final double scale in <double>[1, 1.5]) {
      testWidgets('one recommendation over the actions, ${width}px @$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          wrap(
            HomeActionArea(
              openIdeas: const [],
              visit: 0,
              inputsOverride: inputs(),
            ),
            width: width,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('מה עושים עכשיו?'), findsOneWidget);
        expect(
          find.text('3 חברים שלך הוסיפו כרטיס אישי – אולי מתחילים מהם?'),
          findsOneWidget,
        );
        expect(find.text('הוסיפי חברים'), findsOneWidget);
        expect(find.text('הוסיפי רעיון'), findsOneWidget);
        // The recommendation sits above the actions.
        expect(
          tester.getCenter(find.text('מה עושים עכשיו?')).dy,
          lessThan(tester.getCenter(find.text('הוסיפי חברים')).dy),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('the weekly pace reads n/5 and congratulates at the target', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const WeeklyProgressBar(done: 3, target: 5)));
    await tester.pumpAndSettle();
    expect(find.text('השבוע 3/5 פעולות'), findsOneWidget);
    await tester.pumpWidget(wrap(const WeeklyProgressBar(done: 7, target: 5)));
    await tester.pumpAndSettle();
    expect(find.text('השבוע 7 פעולות – כל הכבוד!'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });
}
