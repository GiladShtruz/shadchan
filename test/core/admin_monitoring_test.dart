import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/admin_monitoring.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 26, 15);

  test('the fixed periods: today, 7, 30, a month, a range', () {
    expect(MonitoringPeriod.today(now).fromKey, '2026-11-26');
    final MonitoringPeriod week = MonitoringPeriod.last(7, now);
    expect(week.fromKey, '2026-11-20');
    expect(week.days, 7);
    expect(MonitoringPeriod.last(30, now).days, 30);
    final MonitoringPeriod current = MonitoringPeriod.month(2026, 11, now);
    expect(current.fromKey, '2026-11-01');
    expect(current.toKey, '2026-11-26');
    expect(current.monthKey, '2026-11');
    final MonitoringPeriod october = MonitoringPeriod.month(2026, 10, now);
    expect(october.toKey, '2026-10-31');
    expect(october.label, 'אוקטובר 2026');
    expect(
      MonitoringPeriod.range(DateTime(2026, 11, 3), DateTime(2026, 11, 9)).days,
      7,
    );
  });

  test('money, counts and changes', () {
    expect(MonitoringFormat.ils(12.4), '₪12.40');
    expect(MonitoringFormat.ils(0.001), '<₪0.01');
    expect(MonitoringFormat.count(1234567), '1.2M');
    expect(MonitoringFormat.count(1234), '1,234');
    expect(MonitoringFormat.change(12.5), '+13%');
    expect(MonitoringFormat.change(4.25), '+4.3%');
    expect(MonitoringFormat.change(-40), '−40%');
    expect(MonitoringFormat.change(null), 'חדש');
    expect(MonitoringFormat.bytes(2.5e9), '2.50 GB');
  });

  test('tables sort by any column and search', () {
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
      <String, dynamic>{'email': 'a@x', 'ils': 2},
      <String, dynamic>{'email': 'b@x', 'ils': 9},
      <String, dynamic>{'email': 'c@y', 'ils': null},
    ];
    expect(sortAndFilter(rows, sortKey: 'ils').map((r) => r['email']), <String>[
      'b@x',
      'a@x',
      'c@y',
    ]);
    expect(
      sortAndFilter(
        rows,
        sortKey: 'ils',
        query: '@x',
        searchKeys: <String>['email'],
      ).length,
      2,
    );
  });

  test('CSV is Excel-safe', () {
    final String csv = toCsv(
      <String>['a', 'b'],
      <List<Object?>>[
        <Object?>['x,y', 'say "hi"'],
      ],
    );
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('"x,y","say ""hi"""'));
  });
}
