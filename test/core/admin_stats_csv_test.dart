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
}
