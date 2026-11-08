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
    bool reducedMotion = false,
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
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
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

  testWidgets('both side actions work and the central plus offers both flows', (
    tester,
  ) async {
    int people = 0;
    int ideas = 0;
    await tester.pumpWidget(wrap(people: () => people++, idea: () => ideas++));
    await tester.tap(find.text('הוספת חברים'));
    await tester.tap(find.text('הוספת רעיון'));
    expect(people, 1);
    expect(ideas, 1);

    await tester.tap(find.byTooltip('הוספת חברים או רעיון'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('מה נוסיף היום?'), findsOneWidget);
    await tester.tap(find.text('הוספת רעיון').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(ideas, 2);
    expect(find.text('מה נוסיף היום?'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the two actions are named plainly, carry no captions, keep both drawings',
    (tester) async {
      await tester.pumpWidget(wrap(gender: Gender.female, reducedMotion: true));
      await tester.pumpAndSettle();
      expect(find.text('הוספת חברים'), findsOneWidget);
      expect(find.text('הוספת רעיון'), findsOneWidget);
      // On the bare page: no card is drawn around the row.
      expect(
        find.descendant(
          of: find.byType(HomeAddHub),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      // No "צבור נקודות" on the buttons: what to do, nothing about scoring.
      expect(find.textContaining('נקודות'), findsNothing);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => (image.image as AssetImage).assetName),
        <String>['assets/add_friends_art.png', 'assets/add_idea_art.png'],
      );
    },
  );

  testWidgets(
    'the plus pulses gently and stops when reduced motion is enabled',
    (tester) async {
      await tester.pumpWidget(wrap());
      final Finder pulse = find.descendant(
        of: find.byType(HomeAddHub),
        matching: find.byType(ScaleTransition),
      );
      final Animation<double> scale = tester
          .widget<ScaleTransition>(pulse)
          .scale;
      await tester.pump(const Duration(milliseconds: 900));
      expect(scale.value, greaterThan(1));
      expect(scale.value, lessThanOrEqualTo(1.045));
      await tester.pumpWidget(wrap(reducedMotion: true));
      await tester.pumpAndSettle();
      expect(tester.widget<ScaleTransition>(pulse).scale.value, 1);
    },
  );

  for (final double width in <double>[320, 390, 600]) {
    for (final bool dark in <bool>[false, true]) {
      testWidgets('fits ${width}px, large Hebrew type, dark=$dark', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          wrap(gender: Gender.female, textScale: 1.5, dark: dark),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        final Offset plus = tester.getCenter(find.byIcon(Icons.add_rounded));
        expect(plus.dx, closeTo(width / 2, 1));
        expect(
          tester.getCenter(find.text('הוספת חברים')).dx,
          greaterThan(plus.dx),
        );
        expect(
          tester.getCenter(find.text('הוספת רעיון')).dx,
          lessThan(plus.dx),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
