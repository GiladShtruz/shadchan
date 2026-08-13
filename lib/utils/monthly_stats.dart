import 'package:flutter/material.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';

/// One Hebrew month as a Gregorian half-open range `[start, end)`, running from
/// one Rosh Chodesh to the next.
class MonthPeriod {
  const MonthPeriod({
    required this.start,
    required this.end,
    required this.label,
    required this.shortLabel,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final String shortLabel;
}

/// What happened inside one [MonthPeriod].
class MonthStats {
  const MonthStats({
    required this.ideas,
    required this.people,
    required this.dating,
    required this.weddings,
  });

  final int ideas;
  final int people;
  final int dating;
  final int weddings;

  int get total => ideas + people + dating + weddings;
}

/// Which of the four numbers is being looked at. Tapping a card on the stats
/// screen opens the records behind exactly one of these.
enum MonthlyStatMetric {
  ideas,
  people,
  dating,
  weddings;

  /// The url segment the drill-down route is addressed by.
  static MonthlyStatMetric? byName(String? name) {
    for (final MonthlyStatMetric metric in MonthlyStatMetric.values) {
      if (metric.name == name) {
        return metric;
      }
    }
    return null;
  }

  String get title {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return 'רעיונות שנפתחו';
      case MonthlyStatMetric.people:
        return 'חברים שנוספו';
      case MonthlyStatMetric.dating:
        return 'זוגות שהתחילו לצאת';
      case MonthlyStatMetric.weddings:
        return 'חתונות בכל הזמנים';
    }
  }

  /// The caption on the home card, where a third of a phone's width is all the
  /// label gets. Same count, fewer words.
  String get shortTitle {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return 'רעיונות שנפתחו';
      case MonthlyStatMetric.people:
        return 'חברים שנוספו';
      case MonthlyStatMetric.dating:
        return 'התחילו לצאת';
      case MonthlyStatMetric.weddings:
        return 'חתונות';
    }
  }

  /// One line saying what the app counted, so the number is never a mystery.
  String get explanation {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return 'כל רעיון שנפתח בחודש הזה, לפי תאריך הפתיחה שלו.';
      case MonthlyStatMetric.people:
        return 'כל חבר שנוסף למאגר בחודש הזה.';
      case MonthlyStatMetric.dating:
        return 'זוגות שמסומנים "יוצאים" ושהעדכון האחרון שלהם היה החודש.';
      case MonthlyStatMetric.weddings:
        return 'כל הזוגות שמסומנים "חתונה" במאגר, ללא תלות בחודש.';
    }
  }

  String get emptyLine {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return 'עוד לא נפתחו רעיונות בחודש הזה';
      case MonthlyStatMetric.people:
        return 'עוד לא נוספו חברים בחודש הזה';
      case MonthlyStatMetric.dating:
        return 'עוד לא התחילו לצאת זוגות בחודש הזה';
      case MonthlyStatMetric.weddings:
        return 'עוד לא נרשמו חתונות במאגר';
    }
  }

  IconData get icon {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return Icons.lightbulb_outline_rounded;
      case MonthlyStatMetric.people:
        return Icons.handshake_outlined;
      case MonthlyStatMetric.dating:
        return Icons.favorite_rounded;
      case MonthlyStatMetric.weddings:
        return Icons.diamond_outlined;
    }
  }

  Color get color {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return MonthlyStats.ideasColor;
      case MonthlyStatMetric.people:
        return MonthlyStats.peopleColor;
      case MonthlyStatMetric.dating:
        return MonthlyStats.datingColor;
      case MonthlyStatMetric.weddings:
        return MonthlyStats.weddingsColor;
    }
  }

  /// This metric's own number out of a month's [MonthStats].
  int valueOf(MonthStats stats) {
    switch (this) {
      case MonthlyStatMetric.ideas:
        return stats.ideas;
      case MonthlyStatMetric.people:
        return stats.people;
      case MonthlyStatMetric.dating:
        return stats.dating;
      case MonthlyStatMetric.weddings:
        return stats.weddings;
    }
  }
}

/// The four metrics behind "הנתונים שלך החודש", shared by the full stats screen
/// and the compact card at the bottom of the home screen so the two can never
/// drift apart.
///
/// Counts are read straight from the records rather than kept as running
/// totals, so they reset on their own every Rosh Chodesh.
abstract final class MonthlyStats {
  /// The accent already assigned to each metric across the app.
  static const Color ideasColor = Color(0xFFE0A33C);
  static const Color peopleColor = Color(0xFF5E86A6);
  static const Color datingColor = Color(0xFF6FA07E);
  static const Color weddingsColor = Color(0xFFCF87A9);

  /// The last [count] Hebrew months, newest first.
  static List<MonthPeriod> buildPeriods(DateTime now, int count) {
    final List<MonthPeriod> periods = <MonthPeriod>[];
    DateTime start = HebrewDateUtils.hebrewMonthStart(now);
    // The current month ends at the next Rosh Chodesh (a few days ahead).
    DateTime end = HebrewDateUtils.hebrewMonthStart(
      start.add(const Duration(days: 32)),
    );

    for (int i = 0; i < count; i++) {
      final ({int year, int month, int day})? hebrew = HebrewDateUtils.today(
        from: start,
      );
      periods.add(
        MonthPeriod(
          start: start,
          end: end,
          label: hebrew == null
              ? ''
              : HebrewDateUtils.monthYearLabel(
                  year: hebrew.year,
                  month: hebrew.month,
                ),
          shortLabel: hebrew == null
              ? ''
              : HebrewDateUtils.monthName(
                  year: hebrew.year,
                  month: hebrew.month,
                ),
        ),
      );

      // Step back one Hebrew month: the day before this month's start belongs
      // to the previous month, whichever length or leap month that may be.
      end = start;
      start = HebrewDateUtils.hebrewMonthStart(
        start.subtract(const Duration(days: 1)),
      );
    }

    return periods;
  }

  static MonthStats statsFor(
    MonthPeriod period,
    List<MatchIdea> matches,
    List<Person> people,
  ) {
    bool within(DateTime date) =>
        !date.isBefore(period.start) && date.isBefore(period.end);

    final int ideas = matches
        .where((MatchIdea m) => within(m.createdAt))
        .length;
    final int newPeople = people
        .where((Person p) => !p.hidden && within(p.createdAt))
        .length;
    // A couple's move into "יוצאים"/"חתונה" is not stamped separately, so the
    // proposal's last update stands in for when it happened.
    final int dating = matches
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.dating && within(m.updatedAt),
        )
        .length;
    final int weddings = matches
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.married && within(m.updatedAt),
        )
        .length;

    return MonthStats(
      ideas: ideas,
      people: newPeople,
      dating: dating,
      weddings: weddings,
    );
  }

  /// The current Hebrew month only — what the home screen's compact card needs.
  static MonthStats current(List<MatchIdea> matches, List<Person> people) {
    return withAllTimeWeddings(
      statsFor(buildPeriods(DateTime.now(), 1).first, matches, people),
      matches,
    );
  }

  static MonthStats withAllTimeWeddings(
    MonthStats monthly,
    List<MatchIdea> matches,
  ) {
    return MonthStats(
      ideas: monthly.ideas,
      people: monthly.people,
      dating: monthly.dating,
      weddings: matches
          .where((MatchIdea match) => match.status == MatchStatus.married)
          .length,
    );
  }

  /// The proposals a match-shaped metric counted, newest first. Empty for
  /// [MonthlyStatMetric.people], which counts people rather than proposals.
  static List<MatchIdea> matchesFor(
    MonthlyStatMetric metric,
    MonthPeriod period,
    List<MatchIdea> matches,
  ) {
    bool within(DateTime date) =>
        !date.isBefore(period.start) && date.isBefore(period.end);

    final List<MatchIdea> found = switch (metric) {
      MonthlyStatMetric.ideas =>
        matches.where((MatchIdea m) => within(m.createdAt)).toList(),
      MonthlyStatMetric.dating =>
        matches
            .where(
              (MatchIdea m) =>
                  m.status == MatchStatus.dating && within(m.updatedAt),
            )
            .toList(),
      MonthlyStatMetric.weddings =>
        matches
            .where((MatchIdea m) => m.status == MatchStatus.married)
            .toList(),
      MonthlyStatMetric.people => <MatchIdea>[],
    };

    found.sort(
      (MatchIdea a, MatchIdea b) => b.updatedAt.compareTo(a.updatedAt),
    );
    return found;
  }

  /// The people [MonthlyStatMetric.people] counted, newest first. Empty for
  /// every other metric.
  static List<Person> peopleFor(
    MonthlyStatMetric metric,
    MonthPeriod period,
    List<Person> people,
  ) {
    if (metric != MonthlyStatMetric.people) {
      return const <Person>[];
    }
    final List<Person> found = people
        .where(
          (Person p) =>
              !p.hidden &&
              !p.createdAt.isBefore(period.start) &&
              p.createdAt.isBefore(period.end),
        )
        .toList();
    found.sort((Person a, Person b) => b.createdAt.compareTo(a.createdAt));
    return found;
  }
}
