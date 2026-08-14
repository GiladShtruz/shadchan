import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/utils/enums.dart';

/// The one number the home screen shows, and where it came from.
class HomeStatLine {
  const HomeStatLine({required this.text, required this.isPersonal});

  final String text;

  /// A fact about this matchmaker's own database, rather than about the app as
  /// a whole. Personal facts always win when there is one to tell.
  final bool isPersonal;
}

/// Picks the single encouraging line under the home screen's numbers banner.
///
/// One line, not a panel: charts, month-on-month comparisons and usage figures
/// belong on the screen the banner opens, not on the page someone lands on. The
/// rule the line follows is that it is always true and never a reproach — a
/// matchmaker with no couples yet is told what the milestone ahead is or what
/// the app as a whole did this month, never that their own number is zero.
abstract final class HomeStatsBanner {
  /// Community figures are only shown when a real number is available; the app
  /// does not invent activity it cannot see.
  static HomeStatLine build({
    required List<MatchIdea> matches,
    required int friends,
    DateTime? now,
    int rotation = 0,
  }) {
    final DateTime today = now ?? DateTime.now();
    final DateTime monthStart = DateTime(today.year, today.month);

    final List<MatchIdea> dating = matches
        .where((MatchIdea match) => match.status == MatchStatus.dating)
        .toList();
    final List<MatchIdea> weddings = matches
        .where((MatchIdea match) => match.status == MatchStatus.married)
        .toList();
    final List<MatchIdea> everDated = matches
        .where(
          (MatchIdea match) =>
              match.status == MatchStatus.dating ||
              match.status == MatchStatus.dated ||
              match.status == MatchStatus.married,
        )
        .toList();
    final int startedThisMonth = everDated
        .where((MatchIdea match) => !match.updatedAt.isBefore(monthStart))
        .length;
    final int weddingsThisMonth = weddings
        .where((MatchIdea match) => !match.updatedAt.isBefore(monthStart))
        .length;

    // Every line that is true right now, strongest first.
    final List<HomeStatLine> personal = <HomeStatLine>[
      if (dating.length == 1)
        const HomeStatLine(text: 'זוג שלך יוצא עכשיו', isPersonal: true),
      if (dating.length > 1)
        HomeStatLine(
          text: '${dating.length} זוגות שלך יוצאים עכשיו',
          isPersonal: true,
        ),
      if (weddingsThisMonth > 0)
        const HomeStatLine(
          text: 'זוג שחשבת עליו הגיע לחתונה',
          isPersonal: true,
        ),
      if (startedThisMonth > 0)
        const HomeStatLine(
          text: 'החודש התחיל לצאת זוג חדש מהמאגר שלך',
          isPersonal: true,
        ),
      if (everDated.length > 1)
        HomeStatLine(
          text: 'עד היום ${everDated.length} זוגות שלך התחילו לצאת',
          isPersonal: true,
        ),
      if (weddings.isNotEmpty)
        HomeStatLine(
          text: weddings.length == 1
              ? 'בית אחד נבנה מהמאגר שלך'
              : '${weddings.length} בתים נבנו מהמאגר שלך',
          isPersonal: true,
        ),
    ];

    if (personal.isNotEmpty) {
      return personal[rotation % personal.length];
    }

    // Nothing personal to celebrate yet. What is shown instead is the milestone
    // just ahead — never a zero, and never a comparison with anyone else.
    return HomeStatLine(text: _encouragement(friends), isPersonal: false);
  }

  static String _encouragement(int friends) {
    if (friends == 0) {
      return 'כל שידוך מתחיל מחבר אחד שנכנס למאגר';
    }
    if (friends < 10) {
      return 'המאגר שלך מתחיל להיבנות — $friends חברים כבר בפנים';
    }
    if (friends < 25) {
      return '$friends חברים במאגר. מכאן מתחילים לצוץ רעיונות';
    }
    if (friends < 50) {
      return '$friends חברים במאגר — מספיק כדי לחשוב על התאמות אמיתיות';
    }
    return '$friends חברים במאגר. יש כאן הרבה כיוונים לפתוח';
  }
}
