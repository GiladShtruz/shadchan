import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/home_progress.dart';

void main() {
  group('under a hundred friends: the staged milestones', () {
    test('the friends there are and how many to the next target', () {
      final HomeProgress p = HomeProgress.milestone(37);
      expect(p.line, 'יש לך 37 חברים · עוד 13 ליעד הבא: 50');
      expect(p.progress, greaterThan(0));
      expect(p.progress, lessThan(1));
    });

    test('one friend and none', () {
      expect(
        HomeProgress.milestone(1).line,
        'יש לך חבר אחד · עוד 9 ליעד הבא: 10',
      );
      expect(
        HomeProgress.milestone(0).line,
        'עוד אין לך חברים במאגר · עוד 10 ליעד הבא: 10',
      );
    });
  });

  group('from a hundred: the best week of ideas', () {
    // Sunday 2026-11-15 is the start of "this week".
    final DateTime weekStart = DateTime(2026, 11, 15);

    test(
      'the record is the best completed week; this week tries to beat it',
      () {
        final IdeaWeekRecord r = IdeaWeekRecord.from(
          weekStart: weekStart,
          openedAt: <DateTime>[
            // Last week (Sun 8th – Sat 14th): 3.
            DateTime(2026, 11, 8, 10),
            DateTime(2026, 11, 12),
            DateTime(2026, 11, 14, 23),
            // Two weeks back: 6.
            for (int i = 0; i < 6; i++) DateTime(2026, 11, 3, 9),
            // This week: 4.
            for (int i = 0; i < 4; i++) DateTime(2026, 11, 16),
          ],
        );
        expect(r.record, 6);
        expect(r.thisWeek, 4);
        expect(r.line, 'השיא שלך: 6 רעיונות · עוד 3 לשבור אותו השבוע');
        expect(r.broken, isFalse);
      },
    );

    test('breaking it says so', () {
      final IdeaWeekRecord r = IdeaWeekRecord(record: 2, thisWeek: 3);
      expect(r.broken, isTrue);
      expect(r.progress, 1);
      expect(r.line, contains('שברת את השיא'));
    });

    test('no record yet', () {
      expect(
        const IdeaWeekRecord(record: 0, thisWeek: 0).line,
        'עוד אין לך שיא שבועי · הרעיון הבא יקבע אותו',
      );
      expect(
        const IdeaWeekRecord(record: 1, thisWeek: 0).line,
        'השיא שלך: רעיון אחד · עוד 2 לשבור אותו השבוע',
      );
    });
  });
}
