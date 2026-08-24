import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/think_rotation.dart';

/// Two small pieces of memory that decide who "עוצרים רגע לחשוב על חברים"
/// opens on, plus the one legacy key the community read still has to span.
void main() {
  group('the rotation', () {
    test('leaves a short list alone and enters a long one at the cursor', () {
      const List<int> list = <int>[0, 1, 2, 3, 4];
      expect(ThinkRotation.rotate<int>(const <int>[], 3), isEmpty);
      expect(ThinkRotation.rotate<int>(const <int>[7], 3), <int>[7]);
      expect(ThinkRotation.rotate(list, 0), list);
      expect(ThinkRotation.rotate(list, 2), <int>[2, 3, 4, 0, 1]);
    });

    test('wraps, so nobody is ever out of reach', () {
      const List<int> list = <int>[0, 1, 2];
      // A cursor far past the end still lands inside the list, and every entry
      // is still drawn exactly once — a rotation, never a filter.
      expect(ThinkRotation.rotate(list, 100), <int>[1, 2, 0]);
      expect(ThinkRotation.rotate(list, 100).toSet(), list.toSet());
    });
  });

  group('"אחשוב עליו בהמשך"', () {
    setUp(() async {
      Hive.init('.dart_tool/test_hive_think');
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox<dynamic>('settings');
      }
      await Hive.box<dynamic>('settings').clear();
      ThinkLater.resetCacheForTesting();
    });

    tearDown(() async {
      await Hive.box<dynamic>('settings').clear();
      ThinkLater.resetCacheForTesting();
    });

    test('puts a friend away, and gives them back when the time is up', () {
      final DateTime now = DateTime(2026, 8, 24);
      ThinkLater.remember('rivka', now: now);

      expect(ThinkLater.activeIds(now), contains('rivka'));
      // A postponement, not a refusal: the point of the screen is that there is
      // always somebody worth a thought, so nothing can be hidden for ever.
      expect(
        ThinkLater.activeIds(now.add(ThinkLater.snooze)),
        isNot(contains('rivka')),
      );
    });

    test('an undo takes it straight back off the list', () {
      final DateTime now = DateTime(2026, 8, 24);
      ThinkLater.remember('yossi', now: now);
      ThinkLater.forget('yossi');
      expect(ThinkLater.activeIds(now), isEmpty);
    });
  });

  group('the community month', () {
    test('spans the key an older build wrote, and only for the month', () {
      final DateTime at = DateTime(2026, 8, 24);
      // The month changed from Gregorian `YYYY-MM` to the Hebrew `H<year>-<mm>`
      // with no migration, which is what split the community's monthly figures
      // in two. Both are read; a document carries one, so the two sets are
      // disjoint and adding them up cannot double-count.
      expect(CommunityPeriods.monthKey(at), startsWith('H'));
      expect(
        CommunityPeriods.legacyKeysFor(CommunityPeriod.month, at),
        <String>['2026-08'],
      );

      // Nothing else ever changed shape, so nothing else pays for a second
      // query.
      for (final CommunityPeriod period in <CommunityPeriod>[
        CommunityPeriod.day,
        CommunityPeriod.week,
        CommunityPeriod.allTime,
      ]) {
        expect(CommunityPeriods.legacyKeysFor(period, at), isEmpty);
      }
    });
  });
}
