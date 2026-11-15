import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/widgets/home_add_hub.dart';

void main() {
  Widget wrap({
    Gender gender = Gender.male,
    VoidCallback? people,
    VoidCallback? idea,
    double textScale = 1,
    bool dark = false,
  }) {
    final ThemeData base = dark ? AppTheme.darkTheme() : AppTheme.lightTheme();
    return MaterialApp(
      theme: base.copyWith(
        textTheme: HomeTypography.scale(base.textTheme, dark: dark),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: HomeAddHub(
                gender: gender,
                onAddPeople: people ?? () {},
                onAddIdea: idea ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('two buttons, each starting its own flow, and no "+"', (
    tester,
  ) async {
    int people = 0;
    int ideas = 0;
    await tester.pumpWidget(wrap(people: () => people++, idea: () => ideas++));
    await tester.tap(find.text('הוספת חברים'));
    await tester.tap(find.text('הוספת רעיון'));
    expect(people, 1);
    expect(ideas, 1);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byTooltip('הוספת חברים או רעיון'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('both buttons keep their drawings and say nothing about points', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(gender: Gender.female));
    await tester.pumpAndSettle();
    expect(find.textContaining('נקודות'), findsNothing);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => (image.image as AssetImage).assetName),
      <String>['assets/add_friends_art.png', 'assets/add_idea_art.png'],
    );
  });

  for (final double width in <double>[320, 390, 600]) {
    for (final bool dark in <bool>[false, true]) {
      for (final double scale in <double>[1, 1.5]) {
        testWidgets('fits ${width}px @$scale, dark=$dark — large, equal, '
            'friends at the start', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            wrap(gender: Gender.female, textScale: scale, dark: dark),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final Rect people = tester.getRect(
            find.ancestor(
              of: find.text('הוספת חברים'),
              matching: find.byType(InkWell),
            ),
          );
          final Rect idea = tester.getRect(
            find.ancestor(
              of: find.text('הוספת רעיון'),
              matching: find.byType(InkWell),
            ),
          );
          // RTL: friends on the right, the idea on the left.
          expect(people.center.dx, greaterThan(idea.center.dx));
          expect(people.width, closeTo(idea.width, 1));
          expect(people.height, greaterThanOrEqualTo(58));
          expect(people.width, greaterThan((width - 20) / 2 - 10));
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
