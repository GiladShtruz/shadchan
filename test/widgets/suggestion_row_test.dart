import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/idea_actions.dart';

/// "התאמות": one compact row per candidate, the same shape on every row, and
/// an arrow into the card that never leads nowhere.
void main() {
  Person candidate({String? phone, String last = 'כהן־שטרנברג'}) => Person(
    id: 'c1',
    firstName: 'אלישבע־מרים',
    lastName: last,
    gender: Gender.female,
    manualAge: 27,
    religiousLevel: ReligiousLevel.datiLeumiTorani,
    phone: phone,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Widget host(Widget child, {double width = 390, double scale = 1}) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  for (final double width in <double>[320, 390]) {
    for (final double scale in <double>[1.0, 1.5]) {
      testWidgets('a row fits ${width.toInt()}px at ${scale}x text', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          host(
            Column(
              children: <Widget>[
                SuggestionRow(
                  key: const ValueKey<String>('plain'),
                  person: candidate(),
                  summary: 'גיל 27 · דתי לאומי תורני',
                  onTap: () {},
                  onOpenIdea: () {},
                  onNotSuitable: () {},
                  onOpenCard: () {},
                ),
                const SizedBox(height: 6),
                SuggestionRow(
                  key: const ValueKey<String>('tagged'),
                  person: candidate(last: 'לוי'),
                  summary: 'גיל 27',
                  tag: const Text('כבר נצפתה'),
                  hasIdea: true,
                  dismissed: true,
                  onTap: () {},
                  onOpenIdea: () {},
                  onNotSuitable: () {},
                  onOpenCard: () {},
                ),
              ],
            ),
            width: width,
            scale: scale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Every row the same height, whatever it carries.
        final double plain = tester
            .getSize(find.byKey(const ValueKey<String>('plain')))
            .height;
        final double tagged = tester
            .getSize(find.byKey(const ValueKey<String>('tagged')))
            .height;
        expect(plain, closeTo(tagged, 0.5));
        if (scale == 1.0) {
          // Compact: well under the old row with its drawings underneath.
          expect(plain, lessThan(80));
        }
      });
    }
  }

  testWidgets('the person is at the start, the answers and arrow at the end', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int ideas = 0;
    int nos = 0;
    int cards = 0;
    await tester.pumpWidget(
      host(
        SuggestionRow(
          person: candidate(),
          summary: 'גיל 27 · דתי לאומי תורני',
          onTap: () {},
          onOpenIdea: () => ideas++,
          onNotSuitable: () => nos++,
          onOpenCard: () => cards++,
        ),
      ),
    );

    expect(find.text('אלישבע־מרים כהן־שטרנברג'), findsOneWidget);
    expect(find.text('גיל 27 · דתי לאומי תורני'), findsOneWidget);

    // RTL: the name sits right of the two answers, the arrow at the far left,
    // and all of them on one level.
    final Offset name = tester.getCenter(find.text('אלישבע־מרים כהן־שטרנברג'));
    final Offset open = tester.getCenter(find.text('פתיחת רעיון'));
    final Offset no = tester.getCenter(find.text('לא מתאים'));
    final Offset arrow = tester.getCenter(find.byTooltip('פתיחת הכרטיס'));
    expect(name.dx, greaterThan(open.dx));
    expect(open.dx, greaterThan(no.dx));
    expect(no.dx, greaterThan(arrow.dx));

    await tester.tap(find.text('פתיחת רעיון'));
    await tester.tap(find.text('לא מתאים'));
    await tester.tap(find.byTooltip('פתיחת הכרטיס'));
    expect(<int>[ideas, nos, cards], <int>[1, 1, 1]);
  });

  testWidgets('an existing idea and an earlier "לא מתאים" change the words', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        SuggestionRow(
          person: candidate(),
          summary: 'גיל 27',
          hasIdea: true,
          dismissed: true,
          onTap: () {},
          onOpenIdea: () {},
          onNotSuitable: () {},
          onOpenCard: () {},
        ),
      ),
    );
    expect(find.text('לרעיון הקיים'), findsOneWidget);
    expect(find.text('החזרה'), findsOneWidget);
    expect(find.text('פתיחת רעיון'), findsNothing);
    expect(find.text('לא מתאים'), findsNothing);
  });

  testWidgets('an empty card offers the details request in WhatsApp', (
    WidgetTester tester,
  ) async {
    int asked = 0;
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.bottomCenter,
          child: EmptyCardRequest(
            person: candidate(phone: '0521234567'),
            onRequest: () => asked++,
          ),
        ),
      ),
    );
    expect(find.text('עדיין אין כרטיס מלא לאלישבע־מרים'), findsOneWidget);
    expect(find.textContaining('ממנה'), findsOneWidget);
    await tester.tap(find.text('בקשת פרטים ב־WhatsApp'));
    expect(asked, 1);
  });

  testWidgets('without a reachable number the request says why', (
    WidgetTester tester,
  ) async {
    int asked = 0;
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.bottomCenter,
          child: EmptyCardRequest(
            person: candidate(),
            onRequest: () => asked++,
          ),
        ),
      ),
    );
    expect(
      find.text('אין מספר טלפון שמור שאפשר לפנות אליו ב־WhatsApp'),
      findsOneWidget,
    );
    await tester.tap(find.text('בקשת פרטים ב־WhatsApp'));
    expect(asked, 0);
  });

  testWidgets('the pair actions read compare, idea, not suitable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        IdeaActionBar(
          onCompare: () {},
          onOpenIdea: () {},
          onNotSuitable: () {},
        ),
      ),
    );
    final double compare = tester.getCenter(find.text('השוואת כרטיסים')).dx;
    final double idea = tester.getCenter(find.text('פתיחת רעיון')).dx;
    final double no = tester.getCenter(find.text('לא מתאים')).dx;
    expect(compare, greaterThan(idea));
    expect(idea, greaterThan(no));
    // No hand-drawn pictures any more.
    expect(find.byType(Image), findsNothing);
  });
}
