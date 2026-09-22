import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/home_section.dart';

/// What is left of the home page's shared building blocks once the corkboard
/// and its paper notes are gone.
void main() {
  Widget wrap(Widget child, {double textScale = 1.0}) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('a section can be folded from its title, not only its chevron', (
    WidgetTester tester,
  ) async {
    bool toggled = false;
    await tester.pumpWidget(
      wrap(
        HomeSectionHeader(
          title: 'הלוח שלי',
          subtitle: 'הרעיונות הפתוחים, התזכורות ומה שהצמדתי',
          expanded: true,
          onToggle: () => toggled = true,
        ),
      ),
    );

    expect(find.text('הרעיונות הפתוחים, התזכורות ומה שהצמדתי'), findsOneWidget);
    await tester.tap(find.text('הלוח שלי'));
    expect(toggled, isTrue);
  });

  testWidgets('a line drawing is clipped to its own box', (
    WidgetTester tester,
  ) async {
    // The recolouring turns transparent pixels opaque, so an unclipped filter
    // layer paints the whole card. This is the guard: the drawing occupies its
    // 60x60 box and the red ground around it survives.
    await tester.pumpWidget(
      wrap(
        Center(
          child: ColoredBox(
            color: const Color(0xFFFF0000),
            child: const SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: HomeLineArt(
                    asset: 'assets/shadchan-tip.png',
                    ink: Color(0xFF5C84A3),
                    paper: Color(0xFFFBF5EA),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HomeLineArt)), const Size(60, 60));
  });
}
