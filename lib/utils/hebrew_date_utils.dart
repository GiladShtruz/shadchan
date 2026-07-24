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

  static List<DateTime> upcomingGregorianOccurrences({
    required int month,
    required int day,
    DateTime? from,
    int count = 3,
  }) {
    final DateTime reference = from ?? DateTime.now();
    final DateTime referenceDate = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );
    final List<DateTime> occurrences = <DateTime>[];

    try {
      final JewishDate today = JewishDate.fromDateTime(reference);
      final int currentJewishYear = today.getJewishYear();

      for (
        int offset = 0;
        offset <= count + 2 && occurrences.length < count;
        offset++
      ) {
        try {
          final JewishDate candidate = JewishDate.initDate(
            jewishYear: currentJewishYear + offset,
            jewishMonth: month,
            jewishDayOfMonth: day,
          );
          final DateTime gregorian = DateTime(
            candidate.getGregorianYear(),
            candidate.getGregorianMonth(),
            candidate.getGregorianDayOfMonth(),
          );
          if (!gregorian.isBefore(referenceDate)) {
            occurrences.add(gregorian);
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      return const <DateTime>[];
    }

    return occurrences;
  }

  /// Gregorian date (at midnight) of the first day — Rosh Chodesh — of the
  /// Hebrew month that contains [date]. The monthly stats reset on this day.
  static DateTime hebrewMonthStart(DateTime date) {
    try {
      final JewishDate jd = JewishDate.fromDateTime(date);
      final JewishDate first = JewishDate.initDate(
        jewishYear: jd.getJewishYear(),
        jewishMonth: jd.getJewishMonth(),
        jewishDayOfMonth: 1,
      );
      return DateTime(
        first.getGregorianYear(),
        first.getGregorianMonth(),
        first.getGregorianDayOfMonth(),
      );
    } catch (_) {
      // Fall back to the Gregorian month start if the conversion ever fails.
      return DateTime(date.year, date.month);
    }
  }

  /// Just the Hebrew month name, e.g. "כסלו" (or "אדר א׳" in a leap year).
  static String monthName({required int year, required int month}) {
    try {
      final JewishDate jd = JewishDate.initDate(
        jewishYear: year,
        jewishMonth: month,
        jewishDayOfMonth: 1,
      );
      return _formatter.formatMonth(jd);
    } catch (_) {
      return '';
    }
  }

  /// "כסלו תשפ״ו" — Hebrew month name and year, used to label a stats period.
  static String monthYearLabel({required int year, required int month}) {
    try {
      final JewishDate jd = JewishDate.initDate(
        jewishYear: year,
        jewishMonth: month,
        jewishDayOfMonth: 1,
      );
      return '${_formatter.formatMonth(jd)} ${_formatter.formatHebrewNumber(year)}';
    } catch (_) {
      return '';
    }
  }

  static ({int year, int month, int day})? today({DateTime? from}) {
    try {
      final JewishDate current = JewishDate.fromDateTime(
        from ?? DateTime.now(),
      );
      return (
        year: current.getJewishYear(),
        month: current.getJewishMonth(),
        day: current.getJewishDayOfMonth(),
      );
    } catch (_) {
      return null;
    }
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
