/// One thing worth a moment's acknowledgement.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.body,
  });

  /// Stable across releases — it is what "already shown" is remembered by, so
  /// renaming one would show it again to everybody who had already seen it.
  final String id;

  final String title;
  final String body;
}

/// What the app congratulates, and — far more importantly — how rarely.
///
/// **The thresholds get further apart on purpose.** Ten friends, then
/// twenty-five, then fifty, then a hundred, then two hundred: early on a
/// matchmaker is finding out whether the app is worth the trouble and a small
/// milestone answers that; three hundred friends in, another popup is an
/// interruption. Every ladder here is spaced that way, and none of them
/// continues past the point where the number stops being news.
///
/// **Only ever one at a time.** [firstUnseen] returns a single achievement even
/// when three were crossed by the same import, which is the difference between
/// a moment of pleasure and a queue of dialogs to dismiss.
abstract final class CommunityAchievements {
  static const List<int> friendMilestones = <int>[
    10,
    25,
    50,
    100,
    200,
    350,
    500,
    750,
    1000,
  ];

  static const List<int> ideaMilestones = <int>[
    1,
    10,
    25,
    50,
    100,
    200,
    350,
    500,
  ];

  static const List<int> actionMilestones = <int>[
    50,
    100,
    250,
    500,
    1000,
    2000,
    3500,
    5000,
  ];

  /// Couples run further than the rest, because every single one is worth
  /// saying something about: one, three, seven, ten, then fifteen and up in
  /// widening steps, and past seventy every further ten.
  static const List<int> coupleMilestones = <int>[
    1,
    3,
    7,
    10,
    15,
    25,
    40,
    50,
    60,
    70,
  ];

  static const String weeklyRecordId = 'record.week';

  /// The highest milestone of [milestones] that [value] has reached, or null.
  static int? reached(List<int> milestones, int value) {
    int? best;
    for (final int milestone in milestones) {
      if (value >= milestone) {
        best = milestone;
      }
    }
    if (best == null) {
      return null;
    }
    // Past the end of the ladder the couples list keeps going in tens; nothing
    // else does, because nothing else stays news.
    if (identical(milestones, coupleMilestones) && value > milestones.last) {
      return (value ~/ 10) * 10;
    }
    return best;
  }

  /// The one achievement to show now: the most significant thing that has
  /// happened and has not been shown yet, or null when there is nothing.
  ///
  /// Ordered by what a matchmaker would most want to hear. A couple who started
  /// dating outranks a round number of friends every time.
  static Achievement? firstUnseen({
    required int friends,
    required int ideas,
    required int actions,
    required int couples,
    required bool newWeeklyRecord,
    required int weeklyRecord,
    required Set<String> seen,
  }) {
    final List<Achievement> candidates = <Achievement>[
      if (reached(coupleMilestones, couples) case final int milestone)
        Achievement(
          id: 'couples.$milestone',
          title: milestone == 1
              ? 'הזוג הראשון שלך יצא!!!'
              : 'הגעת ל־$milestone זוגות!!!',
          body: milestone == 1 ? 'איזה כיף. כל הכבוד!' : 'מדהים. ממשיכים!',
        ),
      if (newWeeklyRecord)
        Achievement(
          id: '$weeklyRecordId.$weeklyRecord',
          title: 'שיא שבועי חדש!!!',
          body: '$weeklyRecord פעולות השבוע. וואו!',
        ),
      if (reached(ideaMilestones, ideas) case final int milestone)
        Achievement(
          id: 'ideas.$milestone',
          title: milestone == 1
              ? 'הרעיון הראשון שלך!!!'
              : 'הגעת ל־$milestone רעיונות!!!',
          body: milestone == 1 ? 'יצאת לדרך. בהצלחה!' : 'כל הכבוד!',
        ),
      if (reached(friendMilestones, friends) case final int milestone)
        Achievement(
          id: 'friends.$milestone',
          title: 'הגעת ל־$milestone חברים במאגר!!!',
          body: 'יפה מאוד, המאגר שלך גדל!',
        ),
      if (reached(actionMilestones, actions) case final int milestone)
        Achievement(
          id: 'actions.$milestone',
          title: 'הגעת ל־$milestone פעולות!!!',
          body: 'איזה יופי. ממשיכים ככה!',
        ),
    ];

    for (final Achievement candidate in candidates) {
      if (!seen.contains(candidate.id)) {
        return candidate;
      }
    }
    return null;
  }

  /// The one-off note after a large import, which replaces the achievements for
  /// that moment entirely — being told twice in one second that something good
  /// happened is being told nothing.
  ///
  /// It says what just happened rather than which round number was passed,
  /// because after an import of three hundred cards "הגעת ל־200 חברים" is the
  /// less interesting of the two facts.
  static String bulkImportMessage(int added) =>
      'הוספת עכשיו $added חברים למאגר – כל הכבוד! המאגר שלך ממש גדל.';
}
