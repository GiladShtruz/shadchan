import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/date_utils.dart';

/// The line a proposal shows once its reminder has come due — the answer to
/// "why is this card shouting at me?".
void main() {
  test('future reminders keep the interval wording the user selected', () {
    final DateTime now = DateTime(2026, 8, 2);

    expect(
      AppDateUtils.futureReminderLabel(DateTime(2026, 8, 9), now: now),
      'בעוד שבוע',
    );
    expect(
      AppDateUtils.futureReminderLabel(DateTime(2026, 9, 2), now: now),
      'בעוד חודש',
    );
    expect(
      AppDateUtils.futureReminderLabel(DateTime(2026, 10, 2), now: now),
      'בעוד חודשיים',
    );
  });

  final DateTime today = DateTime(2026, 8, 10);

  String label(int daysAgo) {
    return AppDateUtils.remindedAgoLabel(
      today.subtract(Duration(days: daysAgo)),
      now: today,
    );
  }

  test('the day the reminder is due', () {
    expect(label(0), 'היום ביקשת שנזכיר לך');
  });

  test('one day and two days read naturally', () {
    expect(label(1), 'עבר יום מאז שביקשת שנזכיר לך');
    expect(label(2), 'עברו יומיים מאז שביקשת שנזכיר לך');
  });

  test('a few days count the days', () {
    expect(label(3), 'עברו 3 ימים מאז שביקשת שנזכיר לך');
    expect(label(29), 'עברו 29 ימים מאז שביקשת שנזכיר לך');
  });

  test('a long wait counts months instead', () {
    expect(label(30), 'עבר חודש מאז שביקשת שנזכיר לך');
    expect(label(95), 'עברו 3 חודשים מאז שביקשת שנזכיר לך');
  });

  test('a date still ahead never reads as a wait', () {
    expect(
      AppDateUtils.remindedAgoLabel(
        today.add(const Duration(days: 4)),
        now: today,
      ),
      'היום ביקשת שנזכיר לך',
    );
  });
}
