import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/home_activity_block.dart';
import 'package:shadchan/widgets/home_community_pulse.dart';
import 'package:shadchan/widgets/home_section.dart';

class _Account extends AccountProvider {
  _Account() : super(connect: () async {});
  @override
  bool get isSignedIn => true;
}

class _Community extends CommunityProvider {
  _Community() : super(connect: () async {});
  @override
  int myPoints(CommunityPeriod period) => switch (period) {
    CommunityPeriod.week => 11,
    CommunityPeriod.month => 21,
    _ => 91,
  };
}

CommunityTotals _totals(int points) => CommunityTotals(
  points: points,
  activeMatchmakers: 2,
  friends: 4,
  ideas: 6,
  couples: 1,
  engagements: 0,
);

Widget _wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AccountProvider>(create: (_) => _Account()),
    ChangeNotifierProvider<CommunityProvider>(create: (_) => _Community()),
  ],
  child: MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  testWidgets('both scores follow the same selected window on one paper card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HomeActivityBlock(
          onOpen: () {},
          loadTotals: (period, {bool forceRefresh = false}) async =>
              _totals(switch (period) {
                CommunityPeriod.week => 101,
                CommunityPeriod.month => 201,
                _ => 901,
              }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomePaperCard), findsOneWidget);
    expect(find.text('91'), findsOneWidget);
    expect(find.text('901'), findsOneWidget);
    await tester.tap(find.text('השבוע'));
    await tester.pumpAndSettle();
    expect(find.text('11'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);
    expect(find.text('901'), findsNothing);
    await tester.tap(find.text('החודש'));
    await tester.pumpAndSettle();
    expect(find.text('21'), findsOneWidget);
    expect(find.text('201'), findsOneWidget);
  });

  testWidgets(
    'an admin goal edit updates the live home target without restarting',
    (tester) async {
      final goals = StreamController<WeeklyCommunityGoal?>();
      await tester.pumpWidget(
        _wrap(
          HomeCommunityPulse(
            onOpen: () {},
            watchGoal: () => goals.stream,
            loadTotals: (_, {bool forceRefresh = false}) async => _totals(100),
          ),
        ),
      );
      await tester.pump();
      goals.add(
        const WeeklyCommunityGoal(
          metric: ChallengeMetric.ideas,
          target: 20,
          title: 'יחד פותחים רעיונות',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('יחד פותחים רעיונות'), findsOneWidget);
      expect(find.text('6 מתוך 20 רעיונות'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(.3, .001),
      );

      goals.add(
        const WeeklyCommunityGoal(
          metric: ChallengeMetric.friends,
          target: 40,
          title: 'מגדילים את המעגל',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('מגדילים את המעגל'), findsOneWidget);
      expect(find.text('4 מתוך 40 חברים'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(.1, .001),
      );
      expect(find.text('יחד פותחים רעיונות'), findsNothing);
      expect(find.text('מה קורה בקהילה עכשיו'), findsOneWidget);
      // The original news still rotates independently of the administrator edit.
      expect(find.text('6 רעיונות נפתחו היום'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('6 רעיונות נפתחו היום'), findsNothing);
      expect(find.text('מגדילים את המעגל'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(goals.close());
    await tester.pump();
    },
  );
}
