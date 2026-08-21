import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/widgets/home_community_pulse.dart';

Widget _wrap(Widget child, {double textScale = 1}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const CommunityChallenge challenge = CommunityChallenge(
    metric: ChallengeMetric.ideas,
    target: 150,
    current: 43,
    record: 128,
  );

  testWidgets('The banner says what is happening and what the week is aiming '
      'at', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        CommunityPulseCard(
          line: '18 רעיונות נפתחו היום',
          challenge: challenge,
          onOpen: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(CommunityPulseCard.title), findsOneWidget);
    expect(find.text('18 רעיונות נפתחו היום'), findsOneWidget);
    expect(
      find.text('השבוע מנסים להגיע יחד ל־150 רעיונות חדשים'),
      findsOneWidget,
    );
    expect(
      find.text('בשבוע שעבר הגענו ל־128 רעיונות — בואו נשבור את השיא ביחד.'),
      findsOneWidget,
    );
    expect(find.text('43 מתוך 150 רעיונות'), findsOneWidget);
  });

  testWidgets('The whole card fits a 320px phone at 1.5x text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        CommunityPulseCard(
          line: 'מזל טוב! זוג נוסף התארס 🎉',
          challenge: challenge,
          onOpen: () {},
        ),
        textScale: 1.5,
      ),
    );
    // The banner turns over on its own; one settled frame is enough to catch a
    // layout that does not fit.
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
  });

  testWidgets('A quiet day still draws the challenge, without a news line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CommunityPulseCard(line: null, challenge: challenge, onOpen: () {}),
      ),
    );
    await tester.pump();

    expect(find.text(CommunityPulseCard.title), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('A week that broke the record says so', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CommunityPulseCard(
          line: null,
          challenge: const CommunityChallenge(
            metric: ChallengeMetric.couples,
            target: 15,
            current: 16,
            record: 12,
          ),
          onOpen: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('שברנו את השיא'), findsOneWidget);
  });
}
