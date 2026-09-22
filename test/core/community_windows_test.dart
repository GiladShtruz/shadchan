import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/community_period.dart';

/// Which windows "פעילות הקהילה" offers, by the day.
///
/// Tishrei 5787 began on Saturday 2026-09-12 (Rosh Hashanah), which puts a
/// Sunday, a weekday and the second week of the month all within a week.
void main() {
  test('the month this test is written against starts where it says', () {
    final DateTime? start = CommunityPeriods.startOf(
      CommunityPeriod.month,
      DateTime(2026, 9, 15, 12),
    );
    expect(start, isNotNull);
    expect(
      DateTime(start!.year, start.month, start.day),
      DateTime(2026, 9, 12),
    );
  });

  test('the Sunday of the first week offers today and all time', () {
    expect(
      CommunityPeriods.communityWindows(DateTime(2026, 9, 13, 10)),
      <CommunityPeriod>[CommunityPeriod.day, CommunityPeriod.allTime],
    );
  });

  test('the rest of the first week leaves the month out', () {
    for (final int day in <int>[12, 14, 15, 18]) {
      expect(
        CommunityPeriods.communityWindows(DateTime(2026, 9, day, 10)),
        <CommunityPeriod>[CommunityPeriod.week, CommunityPeriod.allTime],
        reason: '2026-09-$day',
      );
    }
  });

  test('from the eighth day of the month all three are offered', () {
    for (final int day in <int>[19, 20, 27]) {
      expect(
        CommunityPeriods.communityWindows(DateTime(2026, 9, day, 10)),
        <CommunityPeriod>[
          CommunityPeriod.week,
          CommunityPeriod.month,
          CommunityPeriod.allTime,
        ],
        reason: '2026-09-$day',
      );
    }
  });
}
