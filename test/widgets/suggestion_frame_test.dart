import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_icons.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/app_glyphs.dart';
import 'package:shadchan/widgets/idea_actions.dart';

/// "התאמות" frames a candidate who already has an idea exactly as the idea's
/// card is framed on "הרעיונות שלי", in rows and in squares alike.
void main() {
  Person candidate(String id) => Person(
    id: id,
    firstName: 'אלישבע־מרים',
    lastName: 'כהן־שטרנברג',
    gender: Gender.female,
    manualAge: 27,
    religiousLevel: ReligiousLevel.datiLeumiTorani,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  group('AppColors.ideaFrame', () {
    test('open is blue, waiting orange, out rose, over unframed', () {
      expect(AppColors.ideaFrame(MatchStatus.idea), AppColors.primaryDark);
      expect(AppColors.ideaFrame(MatchStatus.checking), AppColors.primaryDark);
      expect(AppColors.ideaFrame(MatchStatus.unavailable), AppColors.secondary);
      // An open idea with a side on a break waits, as on "הרעיונות שלי".
      expect(
        AppColors.ideaFrame(MatchStatus.idea, paused: true),
        AppColors.secondary,
      );
      expect(AppColors.ideaFrame(MatchStatus.dating), AppColors.femaleAccent);
      for (final MatchStatus over in <MatchStatus>[
        MatchStatus.rejected,
        MatchStatus.dated,
        MatchStatus.married,
      ]) {
        expect(AppColors.ideaFrame(over), isNull);
      }
    });
  });

  Widget host(Widget child, {double width = 390, double scale = 1}) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('an existing idea is a question mark and wears its frame', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: <Widget>[
            SuggestionRow(
              key: const ValueKey<String>('framed'),
              person: candidate('a'),
              summary: 'גיל 27',
              hasIdea: true,
              frameColor: AppColors.femaleAccent,
              onTap: () {},
              onOpenIdea: () {},
              onNotSuitable: () {},
              onOpenCard: () {},
            ),
            SuggestionRow(
              key: const ValueKey<String>('plain'),
              person: candidate('b'),
              summary: 'גיל 27',
              onTap: () {},
              onOpenIdea: () {},
              onNotSuitable: () {},
              onOpenCard: () {},
            ),
          ],
        ),
      ),
    );

    final Finder framed = find.byKey(const ValueKey<String>('framed'));
    final Finder plain = find.byKey(const ValueKey<String>('plain'));
    expect(
      find.descendant(of: framed, matching: find.byIcon(AppIcons.help)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: framed, matching: find.byType(IdeaBulbIcon)),
      findsNothing,
    );
    expect(
      find.descendant(of: plain, matching: find.byType(IdeaBulbIcon)),
      findsOneWidget,
    );

    final Material paper = tester.widget<Material>(
      find.descendant(of: framed, matching: find.byType(Material)).first,
    );
    final BorderSide side = (paper.shape! as RoundedRectangleBorder).side;
    expect(side.width, 1.6);
    expect(
      side.color.toARGB32() & 0xFFFFFF,
      AppColors.femaleAccent.toARGB32() & 0xFFFFFF,
    );
  });

  for (final double width in <double>[320, 390]) {
    for (final double scale in <double>[1.0, 1.5]) {
      testWidgets('squares fit a ${width.toInt()}px grid at ${scale}x text', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          host(
            Builder(
              builder: (BuildContext context) => GridView(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisExtent: SuggestionTile.extentFor(context),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                children: <Widget>[
                  for (final (String id, bool idea) in <(String, bool)>[
                    ('t1', true),
                    ('t2', false),
                  ])
                    SuggestionTile(
                      key: ValueKey<String>(id),
                      person: candidate(id),
                      summary: 'גיל 27 · דתי לאומי תורני',
                      hasIdea: idea,
                      dismissed: !idea,
                      tag: idea ? const Text('בהמתנה') : null,
                      frameColor: idea ? AppColors.secondary : null,
                      onTap: () {},
                      onOpenIdea: () {},
                      onNotSuitable: () {},
                      onOpenCard: () {},
                    ),
                ],
              ),
            ),
            width: width,
            scale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        // Everything a row offers, in every square.
        expect(find.text('לרעיון הקיים'), findsOneWidget);
        expect(find.text('החזרה'), findsOneWidget);
        expect(find.byTooltip('פתיחת הכרטיס'), findsNWidgets(2));
        expect(find.text('גיל 27 · דתי לאומי תורני'), findsNWidgets(2));
        expect(
          tester.getSize(find.byKey(const ValueKey<String>('t1'))).height,
          tester.getSize(find.byKey(const ValueKey<String>('t2'))).height,
        );
      });
    }
  }
}
