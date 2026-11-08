import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/weekly_pace.dart';
import 'package:shadchan/widgets/home_action_area.dart';
import 'package:shadchan/widgets/home_add_hub.dart';

void main() {
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

  for (final double width in <double>[320, 390]) {
    for (final double scale in <double>[1, 1.5]) {
      testWidgets('the title on the bare page over the add row, '
          '${width}px @$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          wrap(const HomeActionArea(), width: width, textScale: scale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('מה עושים עכשיו?'), findsOneWidget);
        expect(find.byType(HomeAddHub), findsOneWidget);
        expect(find.text('הוספת חברים'), findsOneWidget);
        expect(find.text('הוספת רעיון'), findsOneWidget);
        // No standing recommendation any more.
        expect(find.textContaining('הוסיפו כרטיס אישי'), findsNothing);
        expect(
          tester.getCenter(find.text('מה עושים עכשיו?')).dy,
          lessThan(tester.getCenter(find.text('הוספת חברים')).dy),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('under a hundred friends: the milestone, as it always was', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(MilestoneProgressLine(milestone: HomeMilestone.forCount(34))),
    );
    await tester.pumpAndSettle();
    expect(find.text('34/50'), findsOneWidget);
    expect(find.text('עוד 16 חברים ליעד של 50.'), findsOneWidget);
  });

  testWidgets('from a hundred: the personal record, then the celebration', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const PersonalPaceLine(
          gender: Gender.male,
          pace: WeeklyPace(
            metric: PaceMetric.friends,
            mode: PaceMode.lastWeek,
            reference: 4,
            target: 5,
            done: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('בשבוע שעבר הוספת 4 חברים. השבוע שוברים את השיא?'),
      findsOneWidget,
    );
    expect(find.text('2/5'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        const PersonalPaceLine(
          gender: Gender.male,
          pace: WeeklyPace(
            metric: PaceMetric.friends,
            mode: PaceMode.lastWeek,
            reference: 4,
            target: 5,
            done: 6,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('שברת את השיא האישי שלך 🎉'), findsOneWidget);
    expect(find.text('6/5'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });
}
