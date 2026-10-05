import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/home_stage_panels.dart';

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
    // One wide row that opens a screen: a title and a chevron. The full-width
    // filled button it used to carry, and the line that used to sit under the
    // title, are both gone on purpose.
    expect(find.text('שווה הצצה, אולי מחכה שם חיבור'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('הוספת חברים'), findsOneWidget);
    expect(find.text('הוספת רעיון'), findsOneWidget);

    // Unemphasised, the two cards are exactly the same size, side by side.
    final double addPeople = tester
        .getSize(
          find
              .ancestor(
                of: find.text('הוספת חברים'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;
    final double addIdea = tester
        .getSize(
          find
              .ancestor(
                of: find.text('הוספת רעיון'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;
    expect(addPeople, closeTo(addIdea, 0.5));
    // Low: the icon beside the label rather than above it, so the pair takes
    // a strip of the page rather than a block of it.
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('הוספת חברים'),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .height,
      lessThan(80),
    );
    // The whole card is the button: no arrow drawn inside it.
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

  group('the two entry cards are illustrated', () {
    testWidgets('each carries its own picture, and the label stays text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(HomeActionCards(onAddPeople: () {}, onAddIdea: () {})),
      );
      await tester.pump();

      final List<String> assets = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(HomeActionCards),
              matching: find.byType(Image),
            ),
          )
          .map((Image image) => (image.image as AssetImage).assetName)
          .toList();
      // The notepad for adding friends, the heart-and-pencil for adding an
      // idea. Writing a person down is the more literal act and gets the more
      // literal drawing; the heart being drawn *is* the idea. The envelope
      // that used to be here heads "רעיונות שהמאגר מציע לך" now — see
      // [HomeHeroBand].
      expect(assets, <String>[
        'assets/add_friends_art.png',
        'assets/add_idea_art.png',
      ]);

      // The drawings keep their hand-drawn line: recoloured into the palette
      // by luminance (see `artTint`), never flattened through [HomeLineArt].
      expect(
        find.descendant(
          of: find.byType(HomeActionCards),
          matching: find.byType(HomeLineArt),
        ),
        findsNothing,
      );

      // The artwork these replaced had the Hebrew painted into it. If it ever
      // goes back to being part of the picture, it stops growing with the
      // system font and stops being readable to a screen reader — and this is
      // the assertion that would notice.
      expect(find.text('הוספת חברים'), findsOneWidget);
      expect(find.text('הוספת רעיון'), findsOneWidget);
    });

    testWidgets('each wears a wash and a rule of its own colour', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          HomeActionCards(
            onAddPeople: () {},
            onAddIdea: () {},
            emphasiseAddPeople: true,
          ),
        ),
      );
      await tester.pump();

      // `.first` is the card itself; the ancestors past it are the scaffold
      // and the app.
      Color? cardFor(String label) {
        final AnimatedContainer card = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        return (card.decoration as BoxDecoration?)?.color;
      }

      // Both are the page's main buttons now: each on a wash of its own
      // colour rather than plain paper, and not the same wash.
      expect(cardFor('הוספת חברים'), isNot(AppColors.surface));
      expect(cardFor('הוספת רעיון'), isNot(AppColors.surface));
      expect(cardFor('הוספת חברים'), isNot(cardFor('הוספת רעיון')));

      // The colour is all in the rule: the palette's light blue for friends,
      // the palette's brown for an idea, and no band behind the label.
      final List<Color> rules = tester
          .widgetList<AccentUnderline>(
            find.descendant(
              of: find.byType(HomeActionCards),
              matching: find.byType(AccentUnderline),
            ),
          )
          .map((AccentUnderline rule) => rule.color)
          .toList();
      // Each rule is its own drawing's ink.
      expect(rules, <Color>[
        AppColors.addPeopleAccent,
        AppColors.addIdeaAccent,
      ]);

      // The little heart and star that used to sit under the labels went with
      // the band they decorated.
      expect(
        find.descendant(
          of: find.byType(HomeActionCards),
          matching: find.byIcon(Icons.favorite),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(HomeActionCards),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('a tap on the picture counts, not only on the label', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int people = 0;
      int ideas = 0;
      await tester.pumpWidget(
        wrap(
          HomeActionCards(
            onAddPeople: () => people++,
            onAddIdea: () => ideas++,
          ),
        ),
      );
      await tester.pump();

      // The whole surface is the button, and the picture is most of the
      // surface. It sits above the `Material` that paints the ink, so without
      // the tap target stacked over it this is the half that does nothing.
      for (final ({Finder image, String label}) tile
          in <({Finder image, String label})>[
            (image: find.byType(Image).at(0), label: 'הוספת חברים'),
            (image: find.byType(Image).at(1), label: 'הוספת רעיון'),
          ]) {
        await tester.tapAt(tester.getCenter(tile.image));
        await tester.pump();
      }

      expect(people, 1);
      expect(ideas, 1);
    });
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
              sinceLabel: 'יוצאים כבר 3 חודשים',
              personA: contact('a', 'אלעד', Gender.male),
              personB: contact('b', 'תהילה', Gender.female),
            ),
            const HomeDatingCouple(
              matchId: 'm2',
              names: 'יאיר & שושנה',
              sinceLabel: 'יוצאים כבר שבועיים',
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
    expect(
      find.text('ממשיכים לשמור איתם על קשר עד החתונה! :)'),
      findsOneWidget,
    );
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
    // The tip is the sentence and nothing else: the mark is in the block's
    // heading, not an emoji glued to somebody's words.
    expect(find.text('אנשים משתנים.'), findsOneWidget);
    // No drawing, no bulb and no heart: the heading and the pink rule are
    // the block's only furniture.
    for (final Finder mark in <Finder>[
      find.byType(HomeLineArt),
      find.byIcon(Icons.lightbulb_outline_rounded),
      find.byIcon(Icons.favorite_rounded),
    ]) {
      expect(
        find.descendant(of: find.byType(HomeTipCarousel), matching: mark),
        findsNothing,
      );
    }
    // The author's name rides under the tip, small and quiet.
    expect(find.text('רבקה לוי'), findsOneWidget);
    // Tips are read here and written from the settings; no compose entry.
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    // And no watermark behind the sentence: exactly one mark, after the words.
    expect(find.byIcon(Icons.eco_rounded), findsNothing);

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
                    sinceLabel: 'יוצאים כבר שלושה חודשים',
                  ),
                ],
                onOpen: (_) {},
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
        'ממשיכים לשמור איתם על קשר עד החתונה! :)',
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

  testWidgets('the greeting is spoken on the page, not framed in a card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(const HomeGreeting(greeting: 'צהריים טובים', name: 'יצחק')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // One line, two spans: the greeting in the page's ink and the name in the
    // warm accent.
    final RichText line = tester.widget<RichText>(
      find.descendant(
        of: find.byType(HomeGreeting),
        matching: find.byType(RichText),
      ),
    );
    expect(line.text.toPlainText(), 'צהריים טובים, יצחק');

    // Nothing is drawn around it — that is the whole point of moving it out of
    // the app bar.
    for (final Type chrome in <Type>[Card, Material, DecoratedBox]) {
      expect(
        find.descendant(
          of: find.byType(HomeGreeting),
          matching: find.byType(chrome),
        ),
        findsNothing,
        reason: '$chrome',
      );
    }
  });

  testWidgets('the think block is a tile: the coffee cup and its line', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int opened = 0;
    await tester.pumpWidget(
      wrap(HomeThinkBanner(onTap: () => opened++), width: 390),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('עוצרים רגע לחשוב על החברים'), findsOneWidget);
    // Drawn like the home page's add cards: the drawing beside the words,
    // no button of its own.
    expect(find.byType(FilledButton), findsNothing);
    final Finder art = find.descendant(
      of: find.byType(HomeThinkBanner),
      matching: find.byType(Image),
    );
    expect(art, findsOneWidget);
    expect(
      (tester.widget<Image>(art).image as AssetImage).assetName,
      'assets/think_coffee_art.png',
    );

    await tester.tap(find.text('עוצרים רגע לחשוב על החברים'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('the think tile keeps its line on one row at large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(HomeThinkBanner(onTap: () {}), width: 320, textScale: 1.5),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.text('עוצרים רגע לחשוב על החברים'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

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
        for (final String label in <String>['הוספת חברים', 'הוספת רעיון']) {
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        }

        // Only the tiles themselves. Each one also carries a transparent
        // `Material` holding the tap target over its picture, and taking the
        // first two Materials would compare a tile with its own overlay and
        // pass however wrong the row was.
        final Iterable<Size> cards = tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: find.byType(HomeActionCards),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .map(
              (AnimatedContainer card) => tester.getSize(find.byWidget(card)),
            );
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
