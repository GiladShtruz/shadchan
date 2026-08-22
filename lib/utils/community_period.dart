import 'package:shadchan/utils/hebrew_date_utils.dart';
import 'package:timezone/timezone.dart' as tz;

/// The four windows the activity screen and the leaderboard switch between.
enum CommunityPeriod {
  day,
  week,
  month,
  allTime;

  String get label {
    switch (this) {
      case CommunityPeriod.day:
        return 'היום';
      case CommunityPeriod.week:
        return 'השבוע';
      case CommunityPeriod.month:
        return 'החודש';
      case CommunityPeriod.allTime:
        return 'כל הזמנים';
    }
  }

  /// The prefix every one of this window's fields on a member document is
  /// written with: `weekActions`, `weekFriends`, `weekCouples` and so on.
  ///
  /// One prefix rather than five getters full of switch statements, and the
  /// four `*Actions` names are the ones that already existed — renaming them to
  /// `*Points` would have meant four new composite indexes and a window in
  /// which every leaderboard in the wild returned nothing.
  String get fieldPrefix {
    switch (this) {
      case CommunityPeriod.day:
        return 'day';
      case CommunityPeriod.week:
        return 'week';
      case CommunityPeriod.month:
        return 'month';
      case CommunityPeriod.allTime:
        return 'all';
    }
  }

  /// The field holding this window's weighted activity points.
  ///
  /// Still called `*Actions` on the server. It held a flat count of actions
  /// until the scoring was weighted; the name is the one thing about it that
  /// did not change, because it is the field four composite indexes sort by.
  String get actionsField => '${fieldPrefix}Actions';

  /// The four real events behind the points, each summed on its own so the
  /// community area can show what actually happened rather than only a score.
  String get friendsField => '${fieldPrefix}Friends';
  String get ideasField => '${fieldPrefix}Ideas';
  String get couplesField => '${fieldPrefix}Couples';
  String get engagementsField => '${fieldPrefix}Engagements';

  /// The field holding the window this document's count belongs to, so a
  /// member who has not opened the app since last week is not still sitting at
  /// the top of this week's board. Null for all-time, which never rolls over.
  String? get keyField {
    switch (this) {
      case CommunityPeriod.day:
        return 'dayKey';
      case CommunityPeriod.week:
        return 'weekKey';
      case CommunityPeriod.month:
        return 'monthKey';
      case CommunityPeriod.allTime:
        return null;
    }
  }
}

/// Which day, week and month it is — in Israel, wherever the phone is.
///
/// The leaderboard resets at midnight Israel time by product decision, and a
/// matchmaker travelling abroad must not get a different day from everybody
/// else: two devices disagreeing about the date would put the same person's
/// work into two different daily boards.
///
/// Keys rather than dates. They are compared for equality and never for order,
/// they survive a round trip through Firestore as plain strings, and they make
/// "has this window rolled over?" a string comparison instead of a calendar
/// calculation repeated in four places.
abstract final class CommunityPeriods {
  static const String _zone = 'Asia/Jerusalem';

  /// Israel's own wall clock.
  ///
  /// Falls back to UTC+3 when the timezone database is not up — it is
  /// initialised by `NotificationService` at startup, and on a device where
  /// that failed the worst case is that the daily reset lands an hour out for
  /// the winter half of the year. That is a far better failure than throwing
  /// somewhere inside the activity screen.
  static DateTime now() {
    try {
      return tz.TZDateTime.now(tz.getLocation(_zone));
    } on Object {
      return DateTime.now().toUtc().add(const Duration(hours: 3));
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String dayKey([DateTime? at]) {
    final DateTime t = at ?? now();
    return '${t.year}-${_two(t.month)}-${_two(t.day)}';
  }

  /// The Hebrew month, written as its year and month number.
  ///
  /// **Rosh Chodesh, not the first of January's calendar.** "החודש" in this app
  /// means the Hebrew month everywhere else — the activity chart is drawn in
  /// Hebrew months, and the stats screen lists records by them — so the
  /// community's month had no business being the Gregorian one. Two matchmakers
  /// comparing "החודש" now mean the same thirty days as each other *and* as
  /// their own charts.
  ///
  /// Prefixed `H` so it can never be confused with the Gregorian keys written
  /// before this, which simply stop matching: a member's monthly figure rolls
  /// over at the next publish, exactly as it does at any month boundary.
  ///
  /// Falls back to the Gregorian month only when the Hebrew conversion fails,
  /// which is the same fallback [HebrewDateUtils.hebrewMonthStart] takes.
  static String monthKey([DateTime? at]) {
    final DateTime t = at ?? now();
    final ({int year, int month, int day})? hebrew =
        HebrewDateUtils.fromGregorian(t);
    if (hebrew == null) {
      return '${t.year}-${_two(t.month)}';
    }
    return 'H${hebrew.year}-${_two(hebrew.month)}';
  }

  /// The Sunday-based week, written as the date of its first day.
  ///
  /// **The week turns over at midnight on מוצאי שבת** — which is Sunday 00:00,
  /// Israel time. Sunday rather than ISO's Monday because that is when the week
  /// starts for the people this app is written for. Written as the date rather
  /// than as a number so it needs no year-boundary special case and can be read
  /// by a person looking at the database.
  static String weekKey([DateTime? at]) {
    final DateTime t = at ?? now();
    // DateTime.weekday is 1 = Monday … 7 = Sunday, so Sunday is 0 days back.
    final int daysSinceSunday = t.weekday % 7;
    final DateTime sunday = DateTime(
      t.year,
      t.month,
      t.day,
    ).subtract(Duration(days: daysSinceSunday));
    return 'W${sunday.year}-${_two(sunday.month)}-${_two(sunday.day)}';
  }

  static String keyFor(CommunityPeriod period, [DateTime? at]) {
    switch (period) {
      case CommunityPeriod.day:
        return dayKey(at);
      case CommunityPeriod.week:
        return weekKey(at);
      case CommunityPeriod.month:
        return monthKey(at);
      case CommunityPeriod.allTime:
        return 'all';
    }
  }

  /// The start of the current window, for counting the local ledgers over it.
  /// Null for all-time, which has no start worth naming.
  static DateTime? startOf(CommunityPeriod period, [DateTime? at]) {
    final DateTime t = at ?? now();
    switch (period) {
      case CommunityPeriod.day:
        return DateTime(t.year, t.month, t.day);
      case CommunityPeriod.week:
        // Sunday at 00:00 — midnight on מוצאי שבת, which is where the week
        // turns over for the people this app is written for.
        return DateTime(
          t.year,
          t.month,
          t.day,
        ).subtract(Duration(days: t.weekday % 7));
      case CommunityPeriod.month:
        // Rosh Chodesh. The counterpart of [monthKey]: the key says which
        // month a figure belongs to and this says where that month began, so
        // the two can never describe different windows.
        return HebrewDateUtils.hebrewMonthStart(t);
      case CommunityPeriod.allTime:
        return null;
    }
  }
}
