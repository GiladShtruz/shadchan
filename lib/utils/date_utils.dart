import 'package:intl/intl.dart';

abstract final class AppDateUtils {
  static final DateFormat _fullDateFormat = DateFormat('dd.MM.yyyy');
  static final DateFormat _shortDateFormat = DateFormat('dd.MM.yy');

  static int calculateAge(DateTime birthDate) {
    final DateTime today = _dateOnly(DateTime.now());
    int age = today.year - birthDate.year;

    final DateTime birthdayThisYear = _birthdayForYear(birthDate, today.year);
    if (today.isBefore(birthdayThisYear)) {
      age--;
    }

    return age;
  }

  static String formatDate(DateTime date) {
    return _fullDateFormat.format(date);
  }

  static String formatDateShort(DateTime date) {
    return _shortDateFormat.format(date);
  }

  static String timeAgo(DateTime date) {
    final Duration difference = DateTime.now().difference(date);

    if (difference.inMinutes < 1) {
      return 'עכשיו';
    }

    if (difference.inHours < 1) {
      return 'לפני ${difference.inMinutes} דקות';
    }

    if (difference.inDays < 1) {
      return 'לפני ${difference.inHours} שעות';
    }

    if (difference.inDays < 7) {
      return 'לפני ${difference.inDays} ימים';
    }

    if (difference.inDays < 30) {
      final int weeks = (difference.inDays / 7).floor().clamp(1, 4);
      return 'לפני $weeks שבועות';
    }

    return formatDate(date);
  }

  /// A shorter, more spoken relative time for the compact home cards, where
  /// "לפני 24 שעות" would both overflow and read like a machine.
  static String timeAgoShort(DateTime date) {
    final Duration difference = DateTime.now().difference(date);

    if (difference.isNegative || difference.inMinutes < 1) {
      return 'עכשיו';
    }
    if (difference.inMinutes < 60) {
      final int minutes = difference.inMinutes;
      return minutes == 1 ? 'לפני דקה' : 'לפני $minutes דק׳';
    }
    if (difference.inHours < 24) {
      final int hours = difference.inHours;
      return hours == 1 ? 'לפני שעה' : 'לפני $hours שעות';
    }
    if (difference.inDays == 1) {
      return 'אתמול';
    }
    if (difference.inDays == 2) {
      return 'לפני יומיים';
    }
    if (difference.inDays < 7) {
      return 'לפני ${difference.inDays} ימים';
    }
    if (difference.inDays < 30) {
      final int weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? 'לפני שבוע' : 'לפני $weeks שבועות';
    }
    if (difference.inDays < 365) {
      final int months = (difference.inDays / 30).floor();
      return months == 1 ? 'לפני חודש' : 'לפני $months חודשים';
    }
    return formatDateShort(date);
  }

  static bool isBirthdayToday(DateTime birthDate) {
    return daysUntilBirthday(birthDate) == 0;
  }

  static bool isBirthdaySoon(DateTime birthDate, {int daysAhead = 7}) {
    final int? daysUntil = daysUntilBirthday(birthDate);
    if (daysUntil == null) {
      return false;
    }

    return daysUntil >= 0 && daysUntil <= daysAhead;
  }

  static int? daysUntilBirthday(DateTime birthDate) {
    final DateTime today = _dateOnly(DateTime.now());
    DateTime nextBirthday = _birthdayForYear(birthDate, today.year);

    if (nextBirthday.isBefore(today)) {
      nextBirthday = _birthdayForYear(birthDate, today.year + 1);
    }

    return nextBirthday.difference(today).inDays;
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime _birthdayForYear(DateTime birthDate, int year) {
    final int safeDay = birthDate.day > _daysInMonth(year, birthDate.month)
        ? _daysInMonth(year, birthDate.month)
        : birthDate.day;

    return DateTime(year, birthDate.month, safeDay);
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}
