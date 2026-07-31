import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The redesigned home page is a hierarchy of differently shaped blocks. These
/// cover the two things that can silently break on a phone: a block that does
/// not fit its width, and a compact card that no longer fits its own box.
void main() {
  Widget wrap(Widget child, {double textScale = 1.0}) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
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
            HomeActionCards(
              stacked: false,
              onAddPeople: () {},
              onAddIdea: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('כל חיבור מתחיל ברעיון טוב'), findsOneWidget);
    expect(find.text('הצג רעיונות חדשים'), findsOneWidget);
    expect(find.text('הוסף חברים'), findsOneWidget);
    expect(find.text('הוסף רעיון'), findsOneWidget);

    // The pair must not read as two identical squares: the filled call to
    // action is the wider of the two.
    final double addPeople = tester
        .getSize(
          find
              .ancestor(
                of: find.text('הוסף חברים'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    final double addIdea = tester
        .getSize(
          find
              .ancestor(
                of: find.text('הוסף רעיון'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    expect(addPeople, greaterThan(addIdea));
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
    expect(
      find.text('שומרים על קשר :) כל זוג צריך חבר אחד שיאמין בו'),
      findsOneWidget,
    );

    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('יאיר & שושנה'), findsOneWidget);
  });

  testWidgets('the month opens as a button, without its numbers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: <Widget>[
            HomeStatsButton(onTap: () {}),
            const SizedBox(height: 12),
            HomeTipStrip(
              tip: 'אם עולה לכם מישהו בראש — תתעדו מיד. אל תסמכו על הזיכרון.',
              onAnother: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('הנתונים שלך החודש'), findsOneWidget);
    expect(find.text('טיפ לחודש'), findsOneWidget);
    expect(
      find.text('אם עולה לכם מישהו בראש — תתעדו מיד. אל תסמכו על הזיכרון.'),
      findsOneWidget,
    );
  });

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

    // Wrapping must not make one card taller than its neighbour.
    final List<Size> sizes = tester
        .widgetList<HomeActivityCard>(find.byType(HomeActivityCard))
        .map((HomeActivityCard card) => tester.getSize(find.byWidget(card)))
        .toList();
    expect(sizes.first, sizes.last);
    expect(sizes.first.height, HomeConfig.activityCardHeight);
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
            // Exactly the room the wave row leaves a circle, with the longest
            // reason the app can produce.
            SizedBox(
              height:
                  HomeConfig.suggestionBubbleHeight -
                  HomeConfig.suggestionRowPadding * 2,
              child: HomeSuggestionBubble(
                person: contact('c', 'מיכל', Gender.unknown),
                reason: 'הכרטיס שלה לא עודכן לאחרונה — שווה לבדוק מה חדש',
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(HomeActivityCard)).height,
      HomeConfig.activityCardHeight,
    );
    expect(
      tester.getSize(find.byType(HomeIdeaCard)).height,
      HomeConfig.ideaCardHeight,
    );
    expect(
      tester.getSize(find.byType(HomeSuggestionBubble)).width,
      HomeConfig.suggestionBubbleWidth,
    );
  });
}
