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
    return statsFor(buildPeriods(DateTime.now(), 1).first, matches, people);
  }
}
