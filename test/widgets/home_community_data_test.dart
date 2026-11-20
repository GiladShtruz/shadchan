import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/home_week_block.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/community_widgets.dart';

class _Account extends AccountProvider {
  _Account() : super(connect: () async {});
  @override
  bool get isSignedIn => true;
}

class _Community extends CommunityProvider {
  _Community({this.hidden = false}) : super(connect: () async {});
  final bool hidden;
  int revision = 0;
  @override
  bool get isHidden => hidden;
  @override
  int get publishRevision => revision;
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

Widget _wrap(Widget child, {_Community? community}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AccountProvider>(create: (_) => _Account()),
    ChangeNotifierProvider<CommunityProvider>(
      create: (_) => community ?? _Community(),
    ),
  ],
  child: MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  testWidgets('the two figures are large, the window is chosen, the target '
      'follows with last week beside it', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeWeekBlock(
          onOpen: () {},
          watchGoal: () => Stream<WeeklyCommunityGoal?>.value(null),
          loadTotals: (period, {bool forceRefresh = false}) async =>
              _totals(period == CommunityPeriod.week ? 101 : 707),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomePaperCard), findsOneWidget);
    // No heading of its own; the window switch is back.
    expect(find.text('השבוע בשדכן'), findsNothing);
    expect(find.text('כל הזמנים'), findsOneWidget);
    expect(find.text('הפעילות שלי'), findsOneWidget);
    expect(find.text('פעילות הקהילה'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);
    // The weekly target sits under the figures.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.getCenter(find.text('101')).dy,
      lessThan(tester.getCenter(find.byType(LinearProgressIndicator)).dy),
    );

    await tester.tap(find.text('כל הזמנים'));
    await tester.pumpAndSettle();
    expect(find.text('91'), findsOneWidget);
    expect(find.text('707'), findsOneWidget);
    // The target is always the week's.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('last week goes into the short headline', () {
    const CommunityChallenge none = CommunityChallenge(
      metric: ChallengeMetric.ideas,
      target: 100,
      current: 40,
      record: null,
    );
    expect(none.lastWeekLabel, isNull);
    const CommunityChallenge seen = CommunityChallenge(
      metric: ChallengeMetric.ideas,
      target: 100,
      current: 40,
      record: 120,
    );
    expect(
      seen.headline,
      'שבוע שעבר הגענו ל־120 רעיונות. השבוע היעד הוא 140 — שוברים את השיא.',
    );
    // The bar is measured against the same figure the headline names.
    expect(seen.progressLabel, '40/140 רעיונות');
    expect(seen.progress, closeTo(40 / 140, 0.001));
    expect(seen.lastWeekLabel, isNull);
    const CommunityChallenge titled = CommunityChallenge(
      metric: ChallengeMetric.ideas,
      target: 150,
      current: 40,
      record: 120,
      title: 'מחברים יחד',
    );
    expect(titled.lastWeekLabel, 'בשבוע שעבר: 120 רעיונות');
  });

  testWidgets('a slower obsolete read cannot overwrite a refreshed score', (
    tester,
  ) async {
    final community = _Community();
    final pending = <Completer<CommunityTotals>>[];
    await tester.pumpWidget(
      _wrap(
        HomeWeekBlock(
          onOpen: () {},
          watchGoal: () => Stream<WeeklyCommunityGoal?>.value(null),
          loadTotals: (period, {bool forceRefresh = false}) {
            final result = Completer<CommunityTotals>();
            pending.add(result);
            return result.future;
          },
        ),
        community: community,
      ),
    );
    await tester.pump();
    final old = pending.toList();
    community.revision++;
    community.notifyListeners();
    await tester.pump();
    pending.last.complete(_totals(222));
    await tester.pumpAndSettle();
    expect(find.text('222'), findsOneWidget);
    for (final request in old) {
      request.complete(_totals(111));
    }
    await tester.pumpAndSettle();
    expect(find.text('222'), findsOneWidget);
    expect(find.text('111'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unresolved community score is not presented as zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HomeWeekBlock(
          onOpen: () {},
          watchGoal: () => Stream<WeeklyCommunityGoal?>.value(null),
          loadTotals: (_, {bool forceRefresh = false}) async =>
              CommunityTotals.empty,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('11'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    // Nothing about the target is said before it is known.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('hiding from the community is mutual', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeWeekBlock(
          onOpen: () {},
          watchGoal: () => Stream<WeeklyCommunityGoal?>.value(null),
          loadTotals: (_, {bool forceRefresh = false}) async => _totals(500),
        ),
        community: _Community(hidden: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(CommunityHiddenNotice.text), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('500'), findsNothing);
    expect(find.text('פעילות הקהילה'), findsNothing);
    // The matchmaker's own activity is still theirs to see.
    expect(find.text('11'), findsOneWidget);
  });

  testWidgets(
    'an admin goal edit updates the live home target without restarting',
    (tester) async {
      final goals = StreamController<WeeklyCommunityGoal?>();
      await tester.pumpWidget(
        _wrap(
          HomeWeekBlock(
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
      expect(find.text('6/20 רעיונות'), findsOneWidget);
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
      expect(find.text('4/40 חברים'), findsOneWidget);
      expect(find.text('יחד פותחים רעיונות'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(goals.close());
      await tester.pump();
    },
  );

  for (final double width in <double>[320, 390]) {
    testWidgets('the community card fits ${width.toInt()}px at 1.5x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: _wrap(
            HomeWeekBlock(
              onOpen: () {},
              watchGoal: () => Stream<WeeklyCommunityGoal?>.value(null),
              loadTotals: (_, {bool forceRefresh = false}) async =>
                  _totals(123456),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
