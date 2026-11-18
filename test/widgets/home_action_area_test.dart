import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/home_typography.dart';
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
      testWidgets('the two buttons with no title over them, '
          '${width}px @$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          wrap(const HomeActionArea(), width: width, textScale: scale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('מה עושים עכשיו?'), findsNothing);
        expect(find.byType(HomeAddHub), findsOneWidget);
        expect(find.text('הוספת חברים'), findsOneWidget);
        expect(find.text('הוספת רעיון'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('the buttons stay pinned while the page above them scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ThemeData base = AppTheme.lightTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: base,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (BuildContext context) => CustomScrollView(
                slivers: <Widget>[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 200, child: Text('נתונים')),
                  ),
                  HomeActionArea.pinnedSliver(context, inset: 14),
                  const SliverToBoxAdapter(child: HomeNextStepTitle()),
                  const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('הפעולה הבאה שלך'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('נתונים').hitTestable(), findsNothing);
    expect(find.text('הוספת חברים').hitTestable(), findsOneWidget);
    expect(find.text('הוספת רעיון').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.byType(HomeAddHub)).dy, lessThan(20));
  });
}
