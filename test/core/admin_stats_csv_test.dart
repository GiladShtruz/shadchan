import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/admin_stats_tab.dart';

void main() {
  test('the CSV export is one row per day, counts only', () {
    final String csv = AdminStatsCsv.build(<Map<String, dynamic>>[
      <String, dynamic>{
        'day': '2026-11-07',
        'users': <String, dynamic>{'total': 120, 'new7': 9},
        'access': <String, dynamic>{'trustLinks': 31},
      },
      <String, dynamic>{
        'day': '2026-11-08',
        'users': <String, dynamic>{'total': 124},
      },
    ]);
    final List<String> lines = csv.trim().split('\n');
    expect(lines, hasLength(3));
    expect(lines.first.split(',').first, 'תאריך');
    expect(lines[1].split(',').take(3).toList(), <String>[
      '2026-11-07',
      '120',
      '9',
    ]);
    // A figure missing that day is an empty cell, not a zero.
    expect(lines[2].split(',')[2], '');
    expect(lines.first.split(',').length, AdminStatsCsv.columns.length + 1);
  });

  group('AdminStatsRange', () {
    Map<String, dynamic> day(String d, int users, int dau, int cards) =>
        <String, dynamic>{
          'day': d,
          'users': <String, dynamic>{'total': users},
          'activity': <String, dynamic>{'dau': dau},
          'singles': <String, dynamic>{'cardsActive': cards},
        };
    final List<Map<String, dynamic>> history = <Map<String, dynamic>>[
      day('2026-11-01', 100, 10, 5),
      day('2026-11-03', 110, 20, 6),
      day('2026-11-05', 130, 30, 9),
      day('2026-11-08', 150, 40, 12),
    ];

    test('growth is the total at the end minus the day before the start', () {
      expect(
        AdminStatsRange.growth(
          history,
          DateTime(2026, 11, 3),
          DateTime(2026, 11, 6),
          'users',
          'total',
        ),
        30,
      );
    });

    test('a level is read at the end and compared with the start', () {
      expect(
        AdminStatsRange.at(
          history,
          DateTime(2026, 11, 7),
          'singles',
          'cardsActive',
        ),
        9,
      );
      // Before measuring began: the first snapshot stands in.
      expect(
        AdminStatsRange.at(history, DateTime(2026, 10, 1), 'users', 'total'),
        100,
      );
    });

    test('a daily figure is averaged over the measured days', () {
      expect(
        AdminStatsRange.average(
          history,
          DateTime(2026, 11, 2),
          DateTime(2026, 11, 8),
          'activity',
          'dau',
        ),
        30,
      );
      expect(
        AdminStatsRange.daysIn(
          history,
          DateTime(2026, 11, 2),
          DateTime(2026, 11, 8),
        ),
        3,
      );
    });
  });
}
