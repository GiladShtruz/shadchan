import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_next_actions.dart';
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The redesigned home page is a hierarchy of differently shaped blocks. These
/// cover the two things that can silently break on a phone: a block that does
/// not fit its width, and a fixed-size card that no longer fits its own box.
void main() {
  Widget wrap(Widget child, {double width = 360, double textScale = 1.0}) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(14), child: child),
            ),
          ),
        ),
      ),
    );
  }

  Person contact(String id, String name, Gender gender) {
    final DateTime now = DateTime.now();
    return Person(
      id: id,
      firstName: name,
      lastName: 'כהן',
      gender: gender,
      createdAt: now,
      updatedAt: now,
    );
  }

  HomeNextAction action(String title, String reason) {
    return HomeNextAction.person(
      kind: HomeActionKind.noIdeas,
      person: contact(title, title, Gender.female),
      title: title,
      reason: reason,
    );
  }

  testWidgets('the opening band and the two action cards fit a phone', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        Column(
          children: <Widget>[
            HomeHeroBand(onShowIdeas: () {}),
            const SizedBox(height: 12),
            HomeActionCards(onAddPeople: () {}, onAddIdea: () {}),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('רעיונות שהמאגר מציע לך'), findsOneWidget);
    expect(find.text('הצגת רעיונות חדשים'), findsOneWidget);
    expect(find.text('הוספת חברים'), findsOneWidget);
    expect(find.text('הוספת רעיון'), findsOneWidget);

    // Adding friends is deliberately the louder of the two at every width: it
    // is what makes everything else on the page possible. Both still sit in one
    // row, level with each other.
    final double addPeople = tester
        .getSize(
          find
              .ancestor(
                of: find.text('הוספת חברים'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    final double addIdea = tester
        .getSize(
          find
              .ancestor(
                of: find.text('הוספת רעיון'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    expect(addPeople, greaterThan(addIdea));
    // Neither tile carries a chevron any more: the whole surface is the button,
    // and an arrow inside it was one decoration too many.
    expect(
      find.descendant(
        of: find.byType(HomeActionCards),
        matching: find.byType(HomeArrowButton),
      ),
      findsNothing,
    );
    final double peopleTop = tester.getTopLeft(find.text('הוספת חברים')).dy;
    final double ideaTop = tester.getTopLeft(find.text('הוספת רעיון')).dy;
    expect(peopleTop, closeTo(ideaTop, 1));
  });

  testWidgets('the couples banner pages between couples and keeps its line', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        HomeDatingBanner(
          couples: <HomeDatingCouple>[
            HomeDatingCouple(
              matchId: 'm1',
              names: 'אלעד & תהילה',
              duration: '3 חודשים',
              personA: contact('a', 'אלעד', Gender.male),
              personB: contact('b', 'תהילה', Gender.female),
            ),
            const HomeDatingCouple(
              matchId: 'm2',
              names: 'יאיר & שושנה',
              duration: 'שבועיים',
            ),
          ],
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('אלעד & תהילה'), findsOneWidget);
    expect(find.text('יוצאים כבר 3 חודשים'), findsOneWidget);
    expect(find.text('ממשיכים לשמור על קשר עד החתונה! :)'), findsOneWidget);
    // Material mirrors the chevrons in RTL, so the arrow that renders pointing
    // left — the way this page reads forward — is `chevron_right`.
    expect(
      tester.widget<HomeArrowButton>(find.byType(HomeArrowButton)).icon,
      Icons.chevron_right,
    );

    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('יאיר & שושנה'), findsOneWidget);
  });

  testWidgets('the activity card shows one total for the window picked', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    HomeActivityRange picked = HomeActivityRange.week;
    int opened = 0;

    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return HomeActivityPanel(
              range: picked,
              total: switch (picked) {
                HomeActivityRange.week => 6,
                HomeActivityRange.month => 21,
                HomeActivityRange.allTime => 348,
              },
              onRangeChanged: (HomeActivityRange range) =>
                  setState(() => picked = range),
              onOpen: () => opened++,
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('הפעילות שלך'), findsOneWidget);
    expect(find.text('השבוע'), findsOneWidget);
    expect(find.text('החודש'), findsOneWidget);
    expect(find.text('כל הזמנים'), findsOneWidget);
    // One number, not a breakdown by kind of action.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('21'), findsNothing);

    // Picking a window changes the figure without opening the stats screen.
    await tester.tap(find.text('כל הזמנים'));
    await tester.pump();
    expect(find.text('348'), findsOneWidget);
    expect(opened, 0);
  });

  testWidgets('the tip carousel credits its author and follows gender', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        const HomeTipCarousel(
          userGender: Gender.female,
          tips: <HomeTip>[
            HomeTip(text: 'אנשים משתנים.', author: 'רבקה לוי'),
            HomeTip(text: 'תזמון הוא חלק מהשידוך.'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('טיפ לשדכנית'), findsOneWidget);
    expect(find.text('טיפ לשדכן'), findsNothing);
    expect(find.text('אנשים משתנים.'), findsOneWidget);
    // The author's name rides under the tip, small and quiet.
    expect(find.text('רבקה לוי'), findsOneWidget);
    // Tips are read here and written from the settings; no compose entry.
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);

    // Swiping moves to the next tip rather than reloading the same one.
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('תזמון הוא חלק מהשידוך.'), findsOneWidget);
  });

  testWidgets('the tip ring has no end to swipe off', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        const HomeTipCarousel(
          tips: <HomeTip>[
            HomeTip(text: 'ראשון'),
            HomeTip(text: 'שני'),
          ],
        ),
      ),
    );
    await tester.pump();

    // Backwards from the opening page is a legal move: the pages wrap by
    // modulo rather than stopping at a first tip.
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('שני'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every next-action card is exactly the same box', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        HomeNextActionsRow(
          actions: <HomeNextAction>[
            action('רבקה', 'אין לו כרגע אף רעיון פתוח'),
            action(
              'אלישבע-מרים',
              'הכרטיס לא עודכן כבר ארבעה חודשים, ויש בו כמה שדות חדשים '
                  'שעדיין ריקים לגמרי',
            ),
            action('דנה', 'חסר בכרטיס: גיל'),
            action('שירה', 'חסר בכרטיס: אזור בארץ'),
          ],
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('הפעולות הבאות שלך'), findsOneWidget);

    // Three at a time, and the long reason does not make its card taller or
    // wider than the short one beside it.
    final List<Size> sizes = tester
        .widgetList<Ink>(
          find.descendant(
            of: find.byType(HomeNextActionsRow),
            matching: find.byType(Ink),
          ),
        )
        .map((Ink card) => tester.getSize(find.byWidget(card)))
        .toList();
    expect(sizes.length, 3);
    for (final Size size in sizes) {
      expect(size.height, sizes.first.height);
      expect(size.width, sizes.first.width);
      expect(size.height, HomeConfig.nextActionCardHeight);
    }
    expect(find.text('שירה'), findsNothing);

    // "פעולות נוספות" swaps the whole trio rather than stepping one card, and
    // there is no per-card "next" button anywhere.
    expect(find.text('הבא'), findsNothing);
    await tester.tap(find.text('פעולות נוספות'));
    await tester.pump();
    expect(find.text('שירה'), findsOneWidget);
    expect(find.text('רבקה'), findsNothing);

    // The end of the list wraps back to the start; the control never dies.
    await tester.tap(find.text('פעולות נוספות'));
    await tester.pump();
    expect(find.text('רבקה'), findsOneWidget);
  });

  for (final double width in <double>[320, 360, 390, 430]) {
    testWidgets('the closing blocks fit ${width.toInt()}px at 1.5x text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          Column(
            children: <Widget>[
              HomeDatingBanner(
                couples: const <HomeDatingCouple>[
                  HomeDatingCouple(
                    matchId: 'm1',
                    names: 'אלישבע-מרים & יהונתן-יוסף',
                    duration: 'שלושה חודשים',
                  ),
                ],
                onOpen: (_) {},
              ),
              const SizedBox(height: 14),
              HomeActivityPanel(
                range: HomeActivityRange.allTime,
                total: 1284,
                onRangeChanged: (_) {},
                onOpen: () {},
              ),
              const SizedBox(height: 14),
              const HomeTipCarousel(
                tips: <HomeTip>[
                  HomeTip(
                    text:
                        'לפעמים ההבדל בין הצעה שמתקבלת להצעה שנדחית הוא פשוט '
                        'איך מציגים אותה.',
                    author: 'מרים בת־אברהם',
                  ),
                ],
              ),
            ],
          ),
          width: width,
          textScale: 1.5,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final String label in <String>[
        'ממשיכים לשמור על קשר עד החתונה! :)',
        'הפעילות שלך',
        'כל הזמנים',
        'מרים בת־אברהם',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
    });
  }

  testWidgets('an open idea reads as a bubble on the wave, not a white box', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Center(
          child: HomeOpenIdeaBubble(
            personA: null,
            personB: null,
            title: 'אריאל & אסתר',
            status: 'ממתין לתשובה',
            statusColor: Colors.teal,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('אריאל & אסתר'), findsOneWidget);
    expect(find.text('ממתין לתשובה'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('אריאל & אסתר')).textAlign,
      TextAlign.center,
    );
    // No card of its own: the bubble carries no bordered surface.
    expect(
      find.descendant(
        of: find.byType(HomeOpenIdeaBubble),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
  });

  for (final double width in <double>[320, 360, 390, 430]) {
    for (final double scale in <double>[1, 1.5]) {
      testWidgets('home lead blocks fit ${width.toInt()}px at ${scale}x text', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrap(
            Column(
              children: <Widget>[
                HomeHeroBand(onShowIdeas: () {}),
                const SizedBox(height: 12),
                HomeActionCards(onAddPeople: () {}, onAddIdea: () {}),
                const SizedBox(height: 12),
                HomeOpenIdeaBubble(
                  personA: null,
                  personB: null,
                  title: 'אלישבע-מרים & יהונתן-יוסף',
                  status: 'ממתין לתשובה',
                  statusColor: Colors.teal,
                  onTap: () {},
                ),
              ],
            ),
            width: width,
            textScale: scale,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final String label in <String>[
          'רעיונות שהמאגר מציע לך',
          'הצגת רעיונות חדשים',
          'הוספת חברים',
          'הוספת רעיון',
        ]) {
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        }

        final Iterable<Size> cards = tester
            .widgetList<Material>(
              find.descendant(
                of: find.byType(HomeActionCards),
                matching: find.byType(Material),
              ),
            )
            .take(2)
            .map((Material card) => tester.getSize(find.byWidget(card)));
        expect(cards.length, 2);
        expect(cards.first.height, closeTo(cards.last.height, 1));

        // Two whole bubbles plus a slice of the next always fit the row: that
        // slice is the only affordance saying it scrolls.
        final double bubbleWidth = tester
            .getSize(find.byType(HomeOpenIdeaBubble))
            .width;
        final double inset = width < 350 ? 10 : HomeConfig.carouselPadding;
        expect(inset + bubbleWidth * 2, lessThan(width));
      });
    }
  }
}
