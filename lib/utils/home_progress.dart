import 'package:shadchan/utils/home_stage.dart';

/// The one compact line between "הפעולה הבאה שלך" and its list.
///
/// **Up to a hundred friends, building the database is the goal** — the same
/// staged targets as always, 10 → 25 → 50 → 100 ([HomeMilestone]):
/// "יש לך 37 חברים · עוד 13 ליעד הבא: 50".
///
/// **From a hundred, the matchmaker races their own record** — the most ideas
/// they opened in one week ([IdeaWeekRecord]): "השיא שלך: 6 רעיונות · עוד 2
/// לשבור אותו השבוע".
class HomeProgress {
  const HomeProgress({required this.line, required this.progress});

  final String line;

  /// Between 0 and 1, for the scale under the line.
  final double progress;

  /// The milestone version, for a database under a hundred.
  static HomeProgress milestone(int friends) {
    final HomeMilestone m = HomeMilestone.forCount(friends);
    final int? target = m.target;
    if (target == null) {
      return HomeProgress(line: friendsLine(friends), progress: 1);
    }
    final int missing = target - friends;
    return HomeProgress(
      line: '${friendsLine(friends)} · עוד $missing ליעד הבא: $target',
      progress: m.progress,
    );
  }

  /// "יש לך 37 חברים", "יש לך חבר אחד", "עוד אין לך חברים במאגר".
  static String friendsLine(int friends) => switch (friends) {
    0 => 'עוד אין לך חברים במאגר',
    1 => 'יש לך חבר אחד',
    _ => 'יש לך $friends חברים',
  };

  /// The record version, from a hundred friends on.
  static HomeProgress record(IdeaWeekRecord record) =>
      HomeProgress(line: record.line, progress: record.progress);
}

/// The most ideas the matchmaker ever opened in one week, against this week.
///
/// Weeks start on Sunday, as everywhere else in the app
/// (`CommunityPeriods.startOf`). The record is the best *completed* week —
/// this week is what is trying to beat it.
class IdeaWeekRecord {
  const IdeaWeekRecord({required this.record, required this.thisWeek});

  /// The best week before this one; 0 when there was none.
  final int record;

  /// Ideas opened since this week began.
  final int thisWeek;

  /// Counts [openedAt] into weeks that start at [weekStart] (this week's
  /// Sunday, local midnight) and every seven days before it.
  static IdeaWeekRecord from({
    required Iterable<DateTime> openedAt,
    required DateTime weekStart,
  }) {
    final DateTime start = DateTime.utc(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );
    int thisWeek = 0;
    final Map<int, int> past = <int, int>{};
    for (final DateTime at in openedAt) {
      final DateTime day = DateTime.utc(at.year, at.month, at.day);
      final int days = start.difference(day).inDays;
      if (days <= 0) {
        // This week (or a clock that ran ahead: counted as now).
        thisWeek++;
      } else {
        final int weeksBack = (days + 6) ~/ 7;
        past[weeksBack] = (past[weeksBack] ?? 0) + 1;
      }
    }
    int best = 0;
    for (final int n in past.values) {
      if (n > best) best = n;
    }
    return IdeaWeekRecord(record: best, thisWeek: thisWeek);
  }

  /// The week that beats the record.
  int get target => record + 1;

  bool get broken => record > 0 && thisWeek > record;

  double get progress {
    if (broken) return 1;
    final double value = thisWeek / target;
    return value.clamp(0, 1).toDouble();
  }

  static String _ideas(int n) => n == 1 ? 'רעיון אחד' : '$n רעיונות';

  String get line {
    if (record == 0) {
      return thisWeek == 0
          ? 'עוד אין לך שיא שבועי · הרעיון הבא יקבע אותו'
          : 'השבוע: ${_ideas(thisWeek)} · זה השיא השבועי הראשון שלך';
    }
    if (broken) {
      return 'שברת את השיא! ${_ideas(thisWeek)} השבוע 🎉';
    }
    return 'השיא שלך: ${_ideas(record)} · עוד ${target - thisWeek} '
        'לשבור אותו השבוע';
  }
}
