import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/user_scrolling.dart';
import 'package:shadchan/widgets/branch_gate.dart';
import 'package:shadchan/widgets/home_card_friends.dart';
import 'package:shadchan/widgets/home_my_matchmakers.dart';
import 'package:shadchan/widgets/shell_bottom_bar.dart';

Person _p(String id) {
  final DateTime now = DateTime(2026, 11, 1);
  return Person(
    id: id,
    firstName: id,
    lastName: 'כהן',
    gender: Gender.female,
    createdAt: now,
    updatedAt: now,
  );
}

CardFriendSlide _slide(String id, DateTime at) =>
    CardFriendSlide(person: _p(id), lastActivityAt: at);

/// A notifier standing in for a repository, to see what a gated tab hears.
class _Counter extends ChangeNotifier {
  void bump() => notifyListeners();
}

void main() {
  group('"עודכן לאחרונה" on "החברים שלך"', () {
    final DateTime now = DateTime(2026, 11, 21, 12);

    test('every friend updated this week, when there are five or fewer', () {
      final Set<String> marked =
          HomeCardFriendsSection.recentlyUpdated(<CardFriendSlide>[
            _slide('a', now.subtract(const Duration(days: 2))),
            _slide('b', now.subtract(const Duration(days: 6))),
            _slide('old', now.subtract(const Duration(days: 9))),
          ], now: now);
      expect(marked, <String>{'a', 'b'});
    });

    test('never more than five; the last 24 hours first, then the newest', () {
      final List<CardFriendSlide> slides = <CardFriendSlide>[
        for (int d = 1; d <= 6; d++)
          _slide('week$d', now.subtract(Duration(days: d))),
        _slide('today1', now.subtract(const Duration(hours: 3))),
        _slide('today2', now.subtract(const Duration(hours: 20))),
      ];
      final Set<String> marked = HomeCardFriendsSection.recentlyUpdated(
        slides,
        now: now,
      );
      expect(marked.length, HomeCardFriendsSection.maxUpdatedMarks);
      expect(marked, containsAll(<String>['today1', 'today2']));
      expect(marked, containsAll(<String>['week1', 'week2', 'week3']));
      expect(marked, isNot(contains('week6')));
    });
  });

  test('"השדכנים שלי": requests first, then the most recently active', () {
    final DateTime now = DateTime(2026, 11, 21);
    const MatchmakerFriend quiet = MatchmakerFriend(
      uid: 'quiet',
      name: 'אבי',
      state: MatchmakerFriendState.canGrant,
    );
    final MatchmakerFriend active = MatchmakerFriend(
      uid: 'active',
      name: 'בני',
      state: MatchmakerFriendState.seesCard,
      lastActiveAt: now.subtract(const Duration(hours: 2)),
    );
    final MatchmakerFriend older = MatchmakerFriend(
      uid: 'older',
      name: 'גדי',
      state: MatchmakerFriendState.seesCard,
      lastActiveAt: now.subtract(const Duration(days: 4)),
    );
    const MatchmakerFriend asking = MatchmakerFriend(
      uid: 'asking',
      name: 'דני',
      state: MatchmakerFriendState.requested,
    );
    final List<String> order = HomeMyMatchmakers.order(<MatchmakerFriend>[
      quiet,
      older,
      asking,
      active,
    ]).map((MatchmakerFriend f) => f.uid).toList();
    expect(order, <String>['asking', 'active', 'older', 'quiet']);
    // Put away from the list: gone from the row too — unless asking.
    expect(
      HomeMyMatchmakers.order(
        <MatchmakerFriend>[quiet, asking],
        hidden: <String>{'quiet', 'asking'},
      ).map((MatchmakerFriend f) => f.uid),
      <String>['asking'],
    );
  });

  test('the bar is called "המאגר" and "רעיונות"', () {
    expect(ShellBottomBar.labelsFor(matchmaker: true), <String>[
      'בית',
      'צ\'אטים',
      'פרופיל',
      'המאגר',
      'רעיונות',
    ]);
  });

  testWidgets(
    'the bar is its ordinary height; the raised circle still takes a tap',
    (WidgetTester tester) async {
      int? tapped;
      int pageTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => pageTaps++,
                child: const SizedBox.expand(),
              ),
              bottomNavigationBar: ShellBottomBar(
                matchmaker: true,
                selected: 0,
                onSelected: (int i) => tapped = i,
              ),
            ),
          ),
        ),
      );
      final Rect bar = tester.getRect(find.byType(ShellBottomBar));
      expect(bar.height, ShellBottomBar.barHeight);
      final Rect face = tester.getRect(
        find.byKey(const ValueKey<String>('shell-profile-face')),
      );
      // The circle rises above the bar's top edge…
      expect(face.top, lessThan(bar.top));
      // …and a tap on that raised part opens the profile, not the page.
      await tester.tapAt(Offset(face.center.dx, face.top + 4));
      expect(tapped, 2);
      expect(pageTaps, 0);
      // Beside the circle, above the bar, the page gets the tap.
      await tester.tapAt(Offset(bar.left + 20, bar.top - 6));
      expect(pageTaps, 1);
    },
  );

  testWidgets('news waits while something scrolls, and comes when it settles', (
    WidgetTester tester,
  ) async {
    UserScrolling.reset();
    int runs = 0;
    UserScrolling.whenIdle(() => runs++);
    expect(runs, 1);
    UserScrolling.scrolling.value = true;
    UserScrolling.whenIdle(() => runs++);
    await tester.pump(const Duration(seconds: 1));
    expect(runs, 1);
    UserScrolling.scrolling.value = false;
    expect(runs, 2);
    // Never held back for ever.
    UserScrolling.scrolling.value = true;
    UserScrolling.whenIdle(() => runs++);
    await tester.pump(const Duration(seconds: 5));
    expect(runs, 3);
    UserScrolling.reset();
  });

  testWidgets('a hidden tab does not rebuild, and catches up when shown', (
    WidgetTester tester,
  ) async {
    final _Counter counter = _Counter();
    int builds = 0;
    Widget app(bool active) => ChangeNotifierProvider<_Counter>.value(
      value: counter,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: BranchGate(
          active: active,
          debugGates: (BranchGateBuilder gate, Widget child) =>
              gate<_Counter>(child),
          child: Builder(
            builder: (BuildContext context) {
              context.watch<_Counter>();
              builds++;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    expect(builds, 1);
    counter.bump();
    await tester.pump();
    expect(builds, 2);

    // Hidden: three changes, no rebuild.
    await tester.pumpWidget(app(false));
    final int hiddenAt = builds;
    counter.bump();
    counter.bump();
    counter.bump();
    await tester.pump();
    expect(builds, hiddenAt);

    // Shown again: one catch-up rebuild.
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(builds, hiddenAt + 1);
  });
}
