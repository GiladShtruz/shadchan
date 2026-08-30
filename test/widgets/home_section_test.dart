import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The board notes have a minimum paper size but grow naturally with content.
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
      actions: const HomeNoteActionsButton(),
      tintSeed: 'person:1',
      onTap: () {},
    );
  }

  testWidgets('the fullest note uses the base paper without a date', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(Center(child: fullestNote())));

    expect(tester.takeException(), isNull);
    final Size size = tester.getSize(find.byType(HomeBoardNote));
    expect(size.width, HomeConfig.cardWidth);
    expect(size.height, greaterThanOrEqualTo(HomeConfig.cardHeight));

    // The menu is a small clean arrow, without the old text label.
    expect(find.text('פעולות'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.text('12.08.26'), findsNothing);

    final Offset noteCenter = tester.getCenter(find.byType(HomeBoardNote));
    final Offset contentCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('home-board-note-content')),
    );
    // The whole paper is rotated by a fraction of a degree for the natural
    // board effect, so sub-pixel geometry can drift slightly.
    expect(contentCenter.dx, closeTo(noteCenter.dx, 1));
    expect(contentCenter.dy, closeTo(noteCenter.dy, 1));
    expect(
      tester.getCenter(find.text('ישראלה בת אברהם')).dx,
      closeTo(noteCenter.dx, 1),
    );
    expect(
      tester.getCenter(find.text('הערה ארוכה שנשברת לשתי שורות מלאות בפתק')).dx,
      closeTo(noteCenter.dx, 1),
    );
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

  testWidgets('the corkboard carries notes directly in a horizontal row', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        HomeNoteBoard(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (int index = 0; index < 4; index++) ...<Widget>[
                  if (index > 0) const SizedBox(width: HomeConfig.cardGap),
                  fullestNote(),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The cork surface runs wider than a note and does not constrain its
    // natural height.
    expect(
      tester.getSize(find.byType(HomeNoteBoard)).width,
      greaterThan(HomeConfig.cardWidth),
    );
  });

  testWidgets('a note carries the next step beside the note, not instead of '
      'it', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        Center(
          child: HomeBoardNote(
            leading: const HomeCardCoupleAvatars(personA: null, personB: null),
            title: 'יוסי & רבקה',
            subtitle: 'לחזור אליהם אחרי החג',
            footnote: 'השלב הבא: לשאול את יוסי',
            actions: const HomeNoteActionsButton(),
            tintSeed: 'idea:1',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // Both lines are on the note. The app's line never quietly replaces
    // somebody's own words.
    expect(find.text('לחזור אליהם אחרי החג'), findsOneWidget);
    expect(find.text('השלב הבא: לשאול את יוסי'), findsOneWidget);
    // And the paper is still the fixed board card, not a box that grew to fit
    // the extra line.
    expect(
      tester.getSize(find.byType(HomeBoardNote)).height,
      closeTo(HomeConfig.cardHeight, 1),
    );
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
