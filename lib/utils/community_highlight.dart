import 'package:shadchan/services/community_engagements_service.dart';
import 'package:shadchan/services/community_service.dart';

/// One sentence on "מה קורה בקהילה עכשיו", and whatever can be done about it.
///
/// **Most news is only news.** A line about how many ideas opened today is
/// something to know and nothing to act on, and dressing it up with a chevron
/// would promise a screen that does not exist. The one exception is somebody
/// else's good news: a wedding a matchmaker put their own name to can be
/// answered, in one tap, with a bracha that lands in their journal for that
/// couple — see `MazelTovService`. That is the only action this banner has ever
/// been able to offer, and [engagement] is how a line carries it.
class CommunityPulseLine {
  const CommunityPulseLine({required this.text, this.engagement});

  final String text;

  /// The wedding this line is about, when it is one that can be answered.
  /// Null on every other line, and on a wedding whose author is not accepting
  /// congratulations.
  final CommunityEngagement? engagement;

  bool get isActionable => engagement?.canBeCongratulated ?? false;
}

/// The one human sentence on a screen otherwise made of numbers.
///
/// **One line, never a feed.** The whole job is to stop the activity screen
/// reading like an analytics dashboard: somewhere between the totals and the
/// leaderboard there should be a sentence a person could have said. Two of them
/// would be a news section, and a news section is a second thing to maintain,
/// to moderate and to be wrong.
///
/// **The couple is never named, and the matchmaker only ever names
/// themselves.** Tying a *name* to an *engagement* is a different disclosure
/// from tying one to a score, so it has its own consent: the record the app
/// writes when a couple marries is anonymous, and a name goes on it afterwards
/// only if that matchmaker was asked about that wedding and said yes — see
/// `CommunityEngagementsService.attachMatchmakerName`. Nothing about either
/// member of the couple is ever stored or said.
///
/// Every line is derived from figures the screen has already fetched. The one
/// exception is the list of engagements in [pulseLines], which its caller
/// fetches.
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

  /// The short lines the home screen's "מה קורה בקהילה עכשיו" rotates through.
  ///
  /// **A list rather than one pick, because this surface moves.** The activity
  /// screen shows a single sentence chosen for the day and holds still while
  /// somebody reads it; the home banner is a small live area that turns over
  /// every few seconds, so it needs everything that is true right now, in the
  /// order worth hearing it.
  ///
  /// **Today first, then the week.** "18 רעיונות נפתחו היום" is news; the same
  /// figure for the week is background. The engagement is the exception and
  /// leads whatever else is true — it is the only line here that is somebody's
  /// life rather than somebody's activity — and where the matchmaker put their
  /// own name to it, so does the line.
  ///
  /// The lines are short on purpose: this is one line of a banner, at whatever
  /// text size the phone is set to, and a sentence that wraps to three lines
  /// makes the banner jump every time it turns over.
  ///
  /// Both windows come from figures the caller has already fetched, so this
  /// costs no reads.
  ///
  /// [namedEngagements] are the weddings whose matchmaker published their own
  /// name this week — see `CommunityEngagementsService.namedThisWeek`. Each one
  /// gets a line of its own, ahead of everything else, and it stays in the
  /// rotation for as long as the record is fresh, which is a week. Where the
  /// author is accepting congratulations the line is tappable and says so.
  ///
  /// **A name here was volunteered for this wedding.** It is not the
  /// leaderboard's standing consent and it is not inferred from anything: the
  /// matchmaker was asked when the couple married and said yes. Nothing about
  /// the couple is stored on those records, so there is nothing about them to
  /// say — the line congratulates the matchmaker and stops.
  static List<CommunityPulseLine> pulseLines({
    required CommunityTotals day,
    required CommunityTotals week,
    List<CommunityEngagement> namedEngagements = const <CommunityEngagement>[],
  }) {
    // A named engagement outranks the anonymous count of the same news, so the
    // count only speaks for the weddings nobody put a name to.
    final int unnamed = week.engagements - namedEngagements.length;

    CommunityPulseLine plain(String text) => CommunityPulseLine(text: text);

    return <CommunityPulseLine>[
      // The only lines here that carry an action: tapping one opens the
      // brachot sheet addressed to that matchmaker. See [CommunityPulseLine].
      for (final CommunityEngagement engagement in namedEngagements)
        CommunityPulseLine(
          text: engagement.canBeCongratulated
              ? 'מזל טוב לשדכן ${engagement.matchmakerName} שזוג שלו התארס השבוע! 🎉 לשליחת ברכה'
              : 'מזל טוב לשדכן ${engagement.matchmakerName} שזוג שלו התארס השבוע! 🎉',
          engagement: engagement,
        ),
      if (unnamed > 0)
        plain(
          unnamed == 1
              ? 'מזל טוב! זוג נוסף התארס 🎉'
              : 'מזל טוב! $unnamed זוגות התארסו השבוע 🎉',
        ),
      if (day.ideas > 0)
        plain(
          day.ideas == 1
              ? 'רעיון חדש נפתח היום'
              : '${day.ideas} רעיונות נפתחו היום',
        ),
      if (week.couples > 0)
        plain(
          week.couples == 1
              ? 'זוג אחד התחיל לצאת השבוע'
              : '${week.couples} זוגות התחילו לצאת השבוע',
        ),
      if (day.friends > 0)
        plain(
          day.friends == 1
              ? 'חבר חדש נוסף למאגרים היום'
              : '${day.friends} חברים חדשים נוספו היום',
        ),
      if (day.activeMatchmakers > 1)
        plain('${day.activeMatchmakers} שדכנים פעילים היום'),
      if (week.ideas > 0 && day.ideas == 0)
        plain('${week.ideas} רעיונות נפתחו השבוע'),
      if (week.friends > 0 && day.friends == 0)
        plain('${week.friends} חברים חדשים נוספו השבוע'),
    ];
  }

  /// A stable-per-day seed. Not the date itself, so a caller does not have to
  /// know or care how the rotation is spread.
  static int seedFor(DateTime at) =>
      at.difference(DateTime(at.year)).inDays + at.year;
}
