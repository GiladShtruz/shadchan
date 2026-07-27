import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/reminder_text_parser.dart';

void main() {
  final DateTime base = DateTime(2026, 7, 27);

  test('parses Hebrew day and week offsets', () {
    expect(
      ReminderTextParser.parse('45 ימים', base: base),
      DateTime(2026, 9, 10),
    );
    expect(
      ReminderTextParser.parse('6 שבועות', base: base),
      DateTime(2026, 9, 7),
    );
  });

  test('parses calendar months and clamps the day', () {
    expect(
      ReminderTextParser.parse('2 חודשים', base: base),
      DateTime(2026, 9, 27),
    );
    expect(
      ReminderTextParser.parse('חודש', base: DateTime(2026, 1, 31)),
      DateTime(2026, 2, 28),
    );
  });

  test('rejects unclear or non-positive offsets', () {
    expect(ReminderTextParser.parse('מתישהו', base: base), isNull);
    expect(ReminderTextParser.parse('0 ימים', base: base), isNull);
  });
}
