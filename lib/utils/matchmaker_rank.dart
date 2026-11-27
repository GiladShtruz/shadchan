import 'package:shadchan/utils/enums.dart';

/// One rung of the matchmaker ladder: earned by the number of ideas opened.
class MatchmakerRank {
  const MatchmakerRank(this.ideas, this.male, this.female);

  /// Ideas opened to reach it.
  final int ideas;
  final String male;
  final String female;

  /// The rung on the ladder, from 1 — the figure drawn inside the medal
  /// ([RankMark]). The app draws its own mark; no emoji stands for a rank.
  int get level => MatchmakerRanks.ladder.indexOf(this) + 1;

  /// The rank's name in the matchmaker's own gender — the masculine form when
  /// it is not known, as in the app's other titles.
  String nameFor(Gender? gender) => gender == Gender.female ? female : male;
}

/// The ladder, by ideas opened (all time): nine ranks.
///
/// **Personal encouragement, not a competition.** Nobody is ranked against
/// anybody else; the rank says how far the matchmaker's own work has come.
///
/// From "שדכן חבר" on, half way to the next rank a "+" joins the name
/// ("שדכן פעיל+"). Never on "שדכן מתחיל", and never at the top (there is no
/// next rank to be half way to).
abstract final class MatchmakerRanks {
  static const List<MatchmakerRank> ladder = <MatchmakerRank>[
    MatchmakerRank(0, 'שדכן מתחיל', 'שדכנית מתחילה'),
    MatchmakerRank(15, 'שדכן חבר', 'שדכנית חברה'),
    MatchmakerRank(50, 'שדכן פעיל', 'שדכנית פעילה'),
    MatchmakerRank(100, 'שדכן מתקדם', 'שדכנית מתקדמת'),
    MatchmakerRank(150, 'שדכן מצטיין', 'שדכנית מצטיינת'),
    MatchmakerRank(200, 'שדכן מקצוען', 'שדכנית מקצוענית'),
    MatchmakerRank(300, 'שדכן בכיר', 'שדכנית בכירה'),
    MatchmakerRank(500, 'שדכן־על', 'שדכנית־על'),
    MatchmakerRank(1000, 'מאסטר שדכן', 'מאסטר שדכנית'),
  ];

  /// The explanation shown with the whole ladder.
  static const String explanation =
      'הדירוג נקבע לפי מספר הרעיונות שפתחת. באמצע הדרך לדרגה הבאה מתווסף + '
      'לשם הדרגה.';

  /// The rank held at [ideas] — every matchmaker has one, from zero.
  static MatchmakerRank current(int ideas) {
    MatchmakerRank held = ladder.first;
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

  /// Ideas at which [rank] gains its "+": half way to the next rank. Null
  /// for the first and the last rank.
  static double? plusAt(MatchmakerRank rank) {
    final int i = ladder.indexOf(rank);
    if (i <= 0 || i >= ladder.length - 1) return null;
    return rank.ideas + (ladder[i + 1].ideas - rank.ideas) / 2;
  }

  /// Whether [ideas] is past half way to the next rank.
  static bool plus(int ideas) {
    final double? at = plusAt(current(ideas));
    return at != null && ideas >= at;
  }

  /// "שדכן פעיל+" — the name, with its "+" when earned.
  static String nameAt(int ideas, Gender? gender) =>
      '${current(ideas).nameFor(gender)}${plus(ideas) ? '+' : ''}';

  /// "שדכן פעיל+" — the rank as a title. Drawn beside a [RankMark].
  static String titleAt(int ideas, Gender? gender) => nameAt(ideas, gender);

  /// Ideas opened out of the next rank's threshold, 0–1. Full at the top.
  static double progress(int ideas) {
    final MatchmakerRank? to = next(ideas);
    if (to == null) return 1;
    return (ideas / to.ideas).clamp(0.0, 1.0);
  }

  /// "עוד 81 רעיונות לשדכן בכיר", or — at the top — the rank itself.
  static String progressLine(int ideas, Gender? gender) {
    final MatchmakerRank? to = next(ideas);
    if (to == null) {
      return 'הגעת לדרגה הגבוהה ביותר: ${ladder.last.nameFor(gender)}';
    }
    final int missing = to.ideas - ideas;
    final String more = missing == 1 ? 'עוד רעיון אחד' : 'עוד $missing רעיונות';
    return '$more ל${to.nameFor(gender)}';
  }
}
