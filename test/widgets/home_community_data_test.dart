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

class _Account extends AccountProvider {
  _Account() : super(connect: () async {});
  @override
  bool get isSignedIn => true;
}

class _Community extends CommunityProvider {
  _Community() : super(connect: () async {});
  int revision = 0;
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
  testWidgets('both scores follow the same selected window on one paper card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        HomeWeekBlock(
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
    expect(find.text(HomeWeekBlock.title), findsOneWidget);
    // "השבוע בשדכן" opens on the week.
    expect(find.text('11'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);
    await tester.tap(find.text('כל הזמנים'));
    await tester.pumpAndSettle();
    expect(find.text('91'), findsOneWidget);
    expect(find.text('901'), findsOneWidget);
    expect(find.text('101'), findsNothing);
    await tester.tap(find.text('החודש'));
    await tester.pumpAndSettle();
    expect(find.text('21'), findsOneWidget);
    expect(find.text('201'), findsOneWidget);
    // One live line from the selected window's own totals.
    expect(find.text('זוג אחד התחיל לצאת החודש'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('6 רעיונות נפתחו החודש'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
          loadTotals: (period, {bool forceRefresh = false}) {
            if (period != CommunityPeriod.week) {
              return Future.value(_totals(10));
            }
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
          loadTotals: (_, {bool forceRefresh = false}) async =>
              CommunityTotals.empty,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('11'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('עדיין לא זמין'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    // Nothing about the target or the community is said before it is known.
    expect(find.text('היעד השבועי של הקהילה'), findsNothing);
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
      expect(find.text(HomeWeekBlock.title), findsOneWidget);
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

  for (final double width in <double>[320, 390]) {
    testWidgets('השבוע בשדכן fits ${width.toInt()}px at 1.5x text', (
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
      expect(find.text('היעד השבועי של הקהילה'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
