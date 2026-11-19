import 'package:shadchan/utils/enums.dart';

/// One rung of the matchmaker ladder: earned by the number of ideas opened.
class MatchmakerRank {
  const MatchmakerRank(this.ideas, this.male, this.female);

  /// Ideas opened to reach it.
  final int ideas;
  final String male;
  final String female;

  /// The rank's name in the matchmaker's own gender — the masculine form when
  /// it is not known, as in the app's other titles.
  String nameFor(Gender? gender) => gender == Gender.female ? female : male;
}

/// The ladder, by ideas opened (all time): eleven ranks.
abstract final class MatchmakerRanks {
  static const List<MatchmakerRank> ladder = <MatchmakerRank>[
    MatchmakerRank(5, 'מתחיל לחבר', 'מתחילה לחבר'),
    MatchmakerRank(10, 'מחבר', 'מחברת'),
    MatchmakerRank(20, 'יוזם', 'יוזמת'),
    MatchmakerRank(50, 'שדכן פעיל', 'שדכנית פעילה'),
    MatchmakerRank(75, 'שדכן מתקדם', 'שדכנית מתקדמת'),
    MatchmakerRank(100, 'שדכן מוביל', 'שדכנית מובילה'),
    MatchmakerRank(140, 'שדכן מצטיין', 'שדכנית מצטיינת'),
    MatchmakerRank(200, 'שדכן מומחה', 'שדכנית מומחית'),
    MatchmakerRank(300, 'שדכן בכיר', 'שדכנית בכירה'),
    MatchmakerRank(500, 'שדכן־על', 'שדכנית־על'),
    MatchmakerRank(1000, 'מאסטר שדכן', 'מאסטר שדכנית'),
  ];

  /// The rank held at [ideas], or null below the first rung.
  static MatchmakerRank? current(int ideas) {
    MatchmakerRank? held;
    for (final MatchmakerRank rank in ladder) {
      if (ideas >= rank.ideas) held = rank;
    }
    return held;
  }

  /// The next rank to reach, or null at the top.
  static MatchmakerRank? next(int ideas) {
    for (final MatchmakerRank rank in ladder) {
      if (ideas < rank.ideas) return rank;
    }
    return null;
  }

  /// How far [ideas] is from the current rank's threshold to the next one's,
  /// 0–1. Full at the top.
  static double progress(int ideas) {
    final MatchmakerRank? to = next(ideas);
    if (to == null) return 1;
    final int from = current(ideas)?.ideas ?? 0;
    final double value = (ideas - from) / (to.ideas - from);
    return value.clamp(0.0, 1.0);
  }

  /// "עוד 7 רעיונות כדי להפוך ל־שדכן פעיל", or — at the top — the rank itself.
  static String progressLine(int ideas, Gender? gender) {
    final MatchmakerRank? to = next(ideas);
    if (to == null) {
      return 'הגעת לדרגה הגבוהה ביותר: ${ladder.last.nameFor(gender)}';
    }
    final int missing = to.ideas - ideas;
    final String more = missing == 1 ? 'עוד רעיון אחד' : 'עוד $missing רעיונות';
    return '$more כדי להפוך ל־${to.nameFor(gender)}';
  }
}
