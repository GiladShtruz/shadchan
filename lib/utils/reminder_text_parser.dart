/// Parses short Hebrew reminder offsets such as "45 ימים", "6 שבועות" and
/// "2 חודשים" into a concrete date.
abstract final class ReminderTextParser {
  static DateTime? parse(String raw, {required DateTime base}) {
    final String text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final RegExpMatch? match = RegExp(
      r'^(?:(\d+)\s*)?(יום|ימים|שבוע|שבועות|חודש|חודשים)$',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final int? amount = match.group(1) == null
        ? 1
        : int.tryParse(match.group(1)!);
    if (amount == null || amount <= 0) {
      return null;
    }

    final DateTime normalized = DateTime(base.year, base.month, base.day);
    final String unit = match.group(2)!;
    if (unit == 'יום' || unit == 'ימים') {
      return normalized.add(Duration(days: amount));
    }
    if (unit == 'שבוע' || unit == 'שבועות') {
      return normalized.add(Duration(days: amount * 7));
    }
    return _addMonths(normalized, amount);
  }

  static DateTime _addMonths(DateTime date, int months) {
    final int zeroBasedMonth = date.month - 1 + months;
    final int year = date.year + zeroBasedMonth ~/ 12;
    final int month = zeroBasedMonth % 12 + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    final int day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }
}
