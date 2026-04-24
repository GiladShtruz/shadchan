import 'package:kosher_dart/kosher_dart.dart';

abstract final class HebrewDateUtils {
  static final HebrewDateFormatter _formatter = HebrewDateFormatter()
    ..hebrewFormat = true;

  static ({int year, int month, int day})? fromGregorian(DateTime date) {
    try {
      final JewishDate jd = JewishDate.fromDateTime(date);
      return (
        year: jd.getJewishYear(),
        month: jd.getJewishMonth(),
        day: jd.getJewishDayOfMonth(),
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? toGregorian({
    required int year,
    required int month,
    required int day,
  }) {
    try {
      final JewishDate jd = JewishDate.initDate(
        jewishYear: year,
        jewishMonth: month,
        jewishDayOfMonth: day,
      );
      return DateTime(
        jd.getGregorianYear(),
        jd.getGregorianMonth(),
        jd.getGregorianDayOfMonth(),
      );
    } catch (_) {
      return null;
    }
  }

  static String format({
    required int year,
    required int month,
    required int day,
  }) {
    try {
      final JewishDate jd = JewishDate.initDate(
        jewishYear: year,
        jewishMonth: month,
        jewishDayOfMonth: day,
      );
      return _formatter.format(jd);
    } catch (_) {
      return '';
    }
  }

  static DateTime? nextGregorianOccurrence({
    required int month,
    required int day,
    DateTime? from,
  }) {
    final DateTime reference = from ?? DateTime.now();
    try {
      final JewishDate today = JewishDate.fromDateTime(reference);
      final int currentJewishYear = today.getJewishYear();

      for (int offset = 0; offset <= 2; offset++) {
        final int candidateYear = currentJewishYear + offset;
        try {
          final JewishDate candidate = JewishDate.initDate(
            jewishYear: candidateYear,
            jewishMonth: month,
            jewishDayOfMonth: day,
          );
          final DateTime gregorian = DateTime(
            candidate.getGregorianYear(),
            candidate.getGregorianMonth(),
            candidate.getGregorianDayOfMonth(),
          );
          if (!gregorian.isBefore(
            DateTime(reference.year, reference.month, reference.day),
          )) {
            return gregorian;
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool isBirthdayToday({
    required int month,
    required int day,
    DateTime? today,
  }) {
    final DateTime reference = today ?? DateTime.now();
    try {
      final JewishDate current = JewishDate.fromDateTime(reference);
      return current.getJewishMonth() == month &&
          current.getJewishDayOfMonth() == day;
    } catch (_) {
      return false;
    }
  }
}
