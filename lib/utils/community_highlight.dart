import 'package:shadchan/services/community_service.dart';

/// The one human sentence on a screen otherwise made of numbers.
///
/// **One line, never a feed.** The whole job is to stop the activity screen
/// reading like an analytics dashboard: somewhere between the totals and the
/// leaderboard there should be a sentence a person could have said. Two of them
/// would be a news section, and a news section is a second thing to maintain,
/// to moderate and to be wrong.
///
/// **Nobody is named.** The engagement line could carry a matchmaker's name —
/// the leaderboard already carries names, with consent — but tying a *name* to
/// an *engagement* is a different disclosure from tying a name to a score, and
/// the record the app writes when a couple marries is deliberately anonymous.
/// So the good news is announced and the couple stays theirs. Congratulating
/// the matchmaker by name is a feature that needs its own consent, not a string
/// change here.
///
/// Every line is derived from figures the screen has already fetched, so this
/// costs no reads at all.
abstract final class CommunityHighlight {
  /// The sentence for this window, or null when the community has been quiet
  /// enough that anything said would be an announcement of nothing.
  ///
  /// [seed] chooses between the lines that are true right now. The screen
  /// passes the day of the year, so the sentence changes daily and holds still
  /// while somebody is reading it — a line that swaps itself on every rebuild
  /// is a line nobody finishes.
  static String? forWeek(CommunityTotals week, {required int seed}) {
    final List<String> lines = <String>[
      if (week.engagements > 0)
        week.engagements == 1
            ? 'מזל טוב! השבוע התארס עוד זוג דרך הקהילה.'
            : 'מזל טוב! השבוע התארסו ${week.engagements} זוגות דרך הקהילה.',
      if (week.couples > 0)
        week.couples == 1
            ? 'השבוע יצא זוג חדש לדייט דרך הקהילה.'
            : 'השבוע יצאו ${week.couples} זוגות חדשים לדייטים דרך הקהילה.',
      if (week.activeMatchmakers > 1)
        '${week.activeMatchmakers} שדכנים כבר היו פעילים השבוע.',
      if (week.ideas > 0)
        week.ideas == 1
            ? 'רעיון חדש אחד נפתח בקהילה השבוע.'
            : '${week.ideas} רעיונות חדשים נפתחו בקהילה השבוע.',
      if (week.friends > 0)
        week.friends == 1
            ? 'חבר חדש אחד נוסף למאגרים של הקהילה השבוע.'
            : '${week.friends} חברים חדשים נוספו למאגרים של הקהילה השבוע.',
    ];

    if (lines.isEmpty) {
      return null;
    }
    return lines[seed.abs() % lines.length];
  }

  /// A stable-per-day seed. Not the date itself, so a caller does not have to
  /// know or care how the rotation is spread.
  static int seedFor(DateTime at) =>
      at.difference(DateTime(at.year)).inDays + at.year;
}
