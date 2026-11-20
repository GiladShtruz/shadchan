import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/matchmaker_rank.dart';

/// The one compact, game-like line under "הפעולה הבאה שלך", over its scale.
///
/// **Up to a hundred friends, building the database is the goal** — the same
/// staged targets as always, 10 → 25 → 50 → 100 ([HomeMilestone]):
/// "עוד 7 חברים ליעד הבא – 50".
///
/// **From a hundred, a real figure of the matchmaker's own work, turned into
/// the next step** ([personal]): "הוסף את הרעיון הבא שלך · כבר פתחת 24
/// רעיונות", "6 חברים יצאו לדייט בזכותך", "2 חברים התחתנו בזכותך". A figure
/// at zero is never said; the lines that are true take turns, one a day.
class HomeProgress {
  const HomeProgress({
    required this.line,
    required this.progress,
    this.count,
    this.goal,
    this.unit,
    this.subline,
    this.rankIdeas,
  });

  final String line;

  /// The small line under the scale — "עוד 81 רעיונות לשדכן בכיר 🏆" — or
  /// null when the line already says it.
  final String? subline;

  /// Set for the rank version: the ideas opened, so a tap can open the
  /// ladder.
  final int? rankIdeas;

  /// Between 0 and 1, for the scale under the line.
  final double progress;

  /// Where the matchmaker stands and the figure the scale runs to, so the
  /// bar is never a stripe on its own: "7 מתוך 10 רעיונות". Null when there
  /// is no goal ahead (the top of a ladder).
  final int? count;
  final int? goal;

  /// The plural noun after the figures — "רעיונות", "חברים".
  final String? unit;

  /// "7 מתוך 10 רעיונות", or null when there is nothing to measure against.
  String? get fractionLabel {
    final int? c = count;
    final int? g = goal;
    if (c == null || g == null || g <= 0) return null;
    return '$c מתוך $g${unit == null ? '' : ' $unit'}';
  }

  /// The milestone version, for a database under a hundred.
  ///
  /// "73/100 חברים במאגר · עוד 27 ליעד הבא", over a scale of 73 out of 100.
  static HomeProgress milestone(int friends) {
    final HomeMilestone m = HomeMilestone.forCount(friends);
    final int? target = m.target;
    if (target == null) {
      return HomeProgress(line: friendsLine(friends), progress: 1);
    }
    final int missing = target - friends;
    return HomeProgress(
      line: '$friends/$target חברים במאגר · עוד $missing ליעד הבא',
      progress: (friends / target).clamp(0.0, 1.0),
      count: friends,
      goal: target,
      unit: 'חברים',
    );
  }

  /// "יש לך 37 חברים", "יש לך חבר אחד", "עוד אין לך חברים במאגר".
  static String friendsLine(int friends) => switch (friends) {
    0 => 'עוד אין לך חברים במאגר',
    1 => 'יש לך חבר אחד',
    _ => 'יש לך $friends חברים',
  };

  /// The version from a hundred friends on: one real figure, chosen by [day]
  /// among those above zero. [couples] and [weddings] are couples; the line
  /// counts the friends in them.
  static HomeProgress personal({
    required int ideas,
    required int couples,
    required int weddings,
    Gender? gender,
    int day = 0,
  }) {
    final List<HomeProgress> lines = <HomeProgress>[
      HomeProgress(
        line: ideas == 0
            ? '{הוסף|הוסיפי} את הרעיון הראשון שלך'.forGender(gender)
            : '{הוסף|הוסיפי} את הרעיון הבא שלך · כבר פתחת '
                      '${ideas == 1 ? 'רעיון אחד' : '$ideas רעיונות'}'
                  .forGender(gender),
        progress: towardNextRound(ideas),
      ),
      if (couples > 0)
        HomeProgress(
          line: '${couples * 2} חברים יצאו לדייט בזכותך',
          progress: towardNextRound(couples),
        ),
      if (weddings > 0)
        HomeProgress(
          line: '${weddings * 2} חברים התחתנו בזכותך',
          progress: towardNextRound(weddings),
        ),
    ];
    return lines[day.abs() % lines.length];
  }

  /// The version from a hundred friends on: the way to the next matchmaker
  /// rank — "עוד 7 רעיונות כדי להפוך ל־שדכן פעיל" — measured against that
  /// rank's threshold.
  ///
  /// The scale is ideas opened out of the next rank's figure — the same two
  /// numbers "43 מתוך 50 רעיונות" prints beside it.
  ///
  /// "🏆 שדכן מקצוען · 219/300 רעיונות", a thin scale of 219 out of 300, and
  /// under it "עוד 81 רעיונות לשדכן בכיר 🏆".
  static HomeProgress rank({required int ideas, Gender? gender}) {
    final String title = MatchmakerRanks.titleAt(ideas, gender);
    final MatchmakerRank? to = MatchmakerRanks.next(ideas);
    if (to == null) {
      return HomeProgress(
        line: '$title · $ideas רעיונות',
        subline: MatchmakerRanks.progressLine(ideas, gender),
        progress: 1,
        rankIdeas: ideas,
      );
    }
    return HomeProgress(
      line: '$title · $ideas/${to.ideas} רעיונות',
      subline: MatchmakerRanks.progressLine(ideas, gender),
      progress: MatchmakerRanks.progress(ideas),
      count: ideas,
      goal: to.ideas,
      unit: 'רעיונות',
      rankIdeas: ideas,
    );
  }

  /// How far [value] is between the round figure under it and the next one —
  /// 5s under fifty, 10s under two hundred, 25s after: 24 is 0.8 of the way
  /// from 20 to 25.
  static double towardNextRound(int value) {
    if (value <= 0) return 0;
    final int step = value < 50
        ? 5
        : value < 200
        ? 10
        : 25;
    final int below = (value ~/ step) * step;
    return ((value - below) / step).clamp(0.0, 1.0);
  }

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
