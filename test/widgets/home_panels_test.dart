import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The redesigned home page is a hierarchy of differently shaped blocks. These
/// cover the two things that can silently break on a phone: a block that does
/// not fit its width, and a compact card that no longer fits its own box.
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
    expect(find.text('כל חיבור מתחיל ברעיון טוב'), findsNothing);
    expect(find.text('הצגת רעיונות חדשים'), findsOneWidget);
    expect(find.text('הוספת חברים'), findsOneWidget);
    expect(find.text('הוספת רעיון'), findsOneWidget);
    expect(find.text('לא משאירים אף חבר/ה רווק/ה מאחור'), findsNothing);
    expect(find.text('שמירת רעיונות במקום אחד'), findsNothing);

    // On a narrow phone both actions get the same room and stay in one row.
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
    expect(addPeople, addIdea);
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
    // The blessing was dropped; the banner is the names and the duration.
    expect(find.text('מאחלים לכם המשך דרך יפה!'), findsNothing);
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

  testWidgets('the month card carries its three numbers, and the tip its link', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        Column(
          children: <Widget>[
            HomeStatsPanel(
              stats: const MonthStats(
                ideas: 12,
                people: 7,
                dating: 4,
                weddings: 2,
              ),
              previous: const MonthStats(
                ideas: 9,
                people: 7,
                dating: 2,
                weddings: 1,
              ),
              onTap: () {},
            ),
            const SizedBox(height: 16),
            HomeTipStrip(
              tip: 'אם עולה לך מישהו בראש — תעד מיד. אל תסמוך על הזיכרון.',
              onAnother: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('הנתונים שלך החודש'), findsOneWidget);
    expect(find.text('טיפ לשדכן'), findsOneWidget);
    expect(
      find.text('אם עולה לך מישהו בראש — תעד מיד. אל תסמוך על הזיכרון.'),
      findsOneWidget,
    );

    // Three of the four numbers fit the row; the weddings count stays on the
    // stats screen the card opens.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('רעיונות שנפתחו'), findsOneWidget);
    expect(find.text('זוגות שהתחילו לצאת'), findsOneWidget);
    expect(find.text('+3 מחודש שעבר'), findsOneWidget);
    expect(find.text('+2 מחודש שעבר'), findsOneWidget);
    expect(find.text('2'), findsNothing);

    // RTL order keeps the dating metric in the physical left-hand card.
    expect(
      tester
          .getCenter(find.byKey(const ValueKey<String>('home-stat-dating')))
          .dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey<String>('home-stat-ideas')))
            .dx,
      ),
    );

    // The arrow points the way the page reads — which in RTL means the mirrored
    // `chevron_right` — and the tip moves forward rather than reloading, so no
    // refresh icon is left anywhere.
    expect(
      find.descendant(
        of: find.byType(HomeStatsPanel),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.text('לטיפ נוסף'), findsOneWidget);
    expect(find.text('טיפ נוסף'), findsNothing);
  });

  testWidgets('the tip heading follows the matchmaker\'s own gender', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        HomeTipStrip(
          tip: 'אנשים משתנים.',
          onAnother: () {},
          userGender: Gender.female,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('טיפ לשדכנית'), findsOneWidget);
    expect(find.text('טיפ לשדכן'), findsNothing);
  });

  for (final double width in <double>[320, 360, 390, 430]) {
    testWidgets('the three closing banners fit ${width.toInt()}px at 1.5x text', (
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
              HomeStatsPanel(
                stats: const MonthStats(
                  ideas: 128,
                  people: 47,
                  dating: 14,
                  weddings: 3,
                ),
                previous: const MonthStats(
                  ideas: 27,
                  people: 5,
                  dating: 2,
                  weddings: 2,
                ),
                onTap: () {},
              ),
              const SizedBox(height: 14),
              HomeTipStrip(
                tip:
                    'לפעמים ההבדל בין הצעה שמתקבלת להצעה שנדחית הוא פשוט איך מציגים אותה.',
                onAnother: () {},
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
        'זוגות שהתחילו לצאת',
        '+101 מחודש שעבר',
        '+42 מחודש שעבר',
        '+12 מחודש שעבר',
        'לטיפ נוסף',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
    });
  }

  testWidgets('a long name wraps instead of being cut, and every card in the '
      'strip keeps the same box', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Long enough to need a second line at the strip's width.
    const String longName = 'אביה אברהם';
    await tester.pumpWidget(
      wrap(
        Column(
          children: <Widget>[
            HomeActivityCard(
              leading: const HomeCardAvatar(person: null, radius: 20),
              title: longName,
              action: 'ערכת פרטים',
              timeAgo: 'לפני יומיים',
              onTap: () {},
            ),
            const SizedBox(height: 10),
            HomeActivityCard(
              leading: const HomeCardAvatar(person: null, radius: 20),
              title: 'דנה',
              action: 'רעיון חדש',
              timeAgo: 'עכשיו',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // The name uses a second line rather than an ellipsis.
    final RenderParagraph name = tester.renderObject<RenderParagraph>(
      find.text(longName),
    );
    expect(name.didExceedMaxLines, isFalse);
    expect(name.size.height, greaterThan(20));

    // The action line under it gets the same treatment: a long "what happened"
    // is given a second line rather than one line and an ellipsis.
    expect(
      tester.widget<Text>(find.text('ערכת פרטים · לפני יומיים')).maxLines,
      2,
    );

    // A wrapped card is allowed to grow naturally; no fixed-height box clips
    // either line.
    final List<Size> sizes = tester
        .widgetList<HomeActivityCard>(find.byType(HomeActivityCard))
        .map((HomeActivityCard card) => tester.getSize(find.byWidget(card)))
        .toList();
    expect(sizes.first.height, greaterThanOrEqualTo(74));
    expect(sizes.last.height, greaterThanOrEqualTo(74));
  });

  testWidgets('the compact strip cards fit their own boxes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: <Widget>[
            HomeActivityCard(
              leading: const HomeCardAvatar(person: null, radius: 20),
              title: 'ישראלה בת אברהם',
              action: 'ערכת פרטים',
              timeAgo: 'לפני יומיים',
              onTap: () {},
            ),
            const SizedBox(height: 10),
            HomeIdeaCard(
              personA: null,
              personB: null,
              title: 'אריאל & אסתר',
              status: 'ממתין לתשובה',
              statusColor: Colors.teal,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            HomeSuggestionBubble(
              person: contact('c', 'מיכל', Gender.unknown),
              reason: 'הכרטיס שלה לא עודכן לאחרונה, שווה לבדוק מה חדש',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(HomeActivityCard)).height,
      greaterThan(70),
    );
    expect(tester.getSize(find.byType(HomeIdeaCard)).height, greaterThan(100));
    expect(
      tester.getSize(find.byType(HomeSuggestionBubble)).width,
      HomeConfig.suggestionBubbleWidth,
    );
  });

  testWidgets('open idea content is centred on both axes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Center(
          child: HomeIdeaCard(
            personA: null,
            personB: null,
            title: 'אריאל & אסתר',
            status: 'רעיון',
            statusColor: Colors.teal,
            onTap: () {},
          ),
        ),
      ),
    );

    final Finder card = find.byType(HomeIdeaCard);
    final Finder content = find
        .descendant(of: card, matching: find.byType(Column))
        .first;
    final Offset cardCenter = tester.getCenter(card);
    final Offset contentCenter = tester.getCenter(content);

    expect(contentCenter.dx, closeTo(cardCenter.dx, 0.5));
    expect(contentCenter.dy, closeTo(cardCenter.dy, 0.5));
    expect(
      tester.widget<Text>(find.text('אריאל & אסתר')).textAlign,
      TextAlign.center,
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
                HomeIdeaCard(
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
        expect(find.text('כל חיבור מתחיל ברעיון טוב'), findsNothing);
        expect(find.text('לא משאירים אף חבר/ה רווק/ה מאחור'), findsNothing);
        expect(find.text('שמירת רעיונות במקום אחד'), findsNothing);

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

        final double ideaWidth = tester
            .getSize(find.byType(HomeIdeaCard))
            .width;
        final double inset = width < 350 ? 10 : HomeConfig.carouselPadding;
        final double gap = width < 350 ? 8 : HomeConfig.cardGap;
        final double twoCardsEnd = inset + ideaWidth * 2 + gap;
        expect(twoCardsEnd, lessThan(width));
        // A third card begins with a small, deliberate slice; the second card
        // itself is always complete.
        expect(width - (twoCardsEnd + gap), inInclusiveRange(14, 28));
      });
    }
  }
}
