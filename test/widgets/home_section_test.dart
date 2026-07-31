import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The board's notes are fixed-size boxes on purpose, so the row reads as one
/// pinned board. That only holds if the fullest possible note still fits inside
/// the box — including at a larger system font, where the note grows with it.
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

  Widget fullestNote() {
    return HomeBoardNote(
      // The tallest leading block: two ringed avatars.
      leading: const HomeCardCoupleAvatars(personA: null, personB: null),
      title: 'ישראלה בת אברהם',
      subtitle: 'הערה ארוכה שנשברת לשתי שורות מלאות בפתק',
      footer: const HomeCardFooter(
        label: '12.08.26',
        icon: Icons.event_outlined,
      ),
      actions: const HomeNoteActionsButton(label: 'פעולות'),
      tintSeed: 'person:1',
      onTap: () {},
    );
  }

  testWidgets('the fullest note fits its fixed box', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(Center(child: fullestNote())));

    expect(tester.takeException(), isNull);
    final Size size = tester.getSize(find.byType(HomeBoardNote));
    expect(size.width, HomeConfig.cardWidth);
    expect(size.height, HomeConfig.cardHeight);

    // The actions button replaced the corner menu, so it is part of the note.
    expect(find.text('פעולות'), findsOneWidget);
  });

  testWidgets('the note grows with the system font instead of overflowing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(Center(child: fullestNote()), textScale: 1.6));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(HomeBoardNote)).height,
      greaterThan(HomeConfig.cardHeight),
    );
  });

  testWidgets('the board frames the notes running inside it', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        HomeNoteBoard(
          child: SizedBox(
            height: HomeConfig.cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: HomeConfig.cardGap),
              itemBuilder: (BuildContext context, int index) => fullestNote(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The frame runs wider than the notes it holds.
    expect(
      tester.getSize(find.byType(HomeNoteBoard)).width,
      greaterThan(HomeConfig.cardWidth),
    );
  });

  testWidgets('a carousel leaves the next card peeking in', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        HomeCarousel(
          itemCount: 6,
          itemBuilder: (BuildContext context, int index) => fullestNote(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // Two whole cards plus a visible slice of the third: that slice is the
    // only affordance telling the user the row scrolls.
    const double used =
        HomeConfig.carouselPadding +
        HomeConfig.cardWidth * 2 +
        HomeConfig.cardGap * 2;
    expect(used, lessThan(360));
    expect(used + HomeConfig.cardWidth, greaterThan(360));
  });
}
