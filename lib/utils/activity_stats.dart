import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/monthly_stats.dart';

/// What one act of matchmaking is worth.
///
/// **Weighted, and deliberately not flat.** Adding a friend and marrying two
/// people off are both work, and calling them both "פעולה אחת" is the fastest
/// way to make the whole figure meaningless. The four weights below are the
/// product decision, and the wording that goes with them is "נקודות פעילות"
/// rather than "פעולות" for exactly that reason: not every event is worth one.
abstract final class ActivityPoints {
  static const int friend = 1;
  static const int idea = 1;
  static const int couple = 5;
  static const int engagement = 50;

  /// The one line that fits under a figure. The full table is [scoringLines],
  /// which is what the home block's explanation opens.
  static const String shortExplanation =
      'כל חבר או רעיון = נקודה · זוג שיוצא לדייט = 5 · חתונה = 50';

  static const String howItIsCountedTitle = 'איך הפעילות נספרת?';

  /// The scoring method, said in full and in the order the acts happen in.
  static const List<String> scoringLines = <String>[
    'הוספת חבר = נקודת פעילות אחת.',
    'פתיחת רעיון = נקודת פעילות אחת.',
    'זוג שהתחיל לצאת = 5 נקודות פעילות.',
    'חתונה = 50 נקודות פעילות.',
  ];

  /// The one question the table above still raises, answered once.
  ///
  /// The list used to carry three more notes — how long a couple had to be
  /// out before they counted, that their five points stay even if they later
  /// stopped seeing each other, and that a plain status update is worth
  /// nothing. Each was true and each answered a question nobody was asking at
  /// that moment; four paragraphs of small print under a four-line table read
  /// as terms and conditions rather than as an explanation.
  static const List<String> scoringNotes = <String>[
    'ייבוא חברים נספר לפי מספר החברים שנוספו בפועל. כפילויות לא נספרות.',
  ];
}

/// What happened in one window, before it is turned into a score.
///
/// The four real events are kept apart from the points they add up to because
/// the two answer different questions and both are shown: "הנתונים שלך" wants
/// four honest counts, and "הפעילות שלך" wants one weighted number.
class ActivityBreakdown {
  const ActivityBreakdown({
    this.friends = 0,
    this.ideas = 0,
    this.couples = 0,
    this.engagements = 0,
  });

  static const ActivityBreakdown empty = ActivityBreakdown();

  /// Friends added to the database.
  final int friends;

  /// Proposals opened.
  final int ideas;

  /// Couples who started dating and stayed that way past
  /// [DatingHistory.qualifyingPeriod].
  final int couples;

  /// Engagements and weddings, which are one event here — the app has no
  /// separate "מאורסים" status, and the community figures would have to add the
  /// two together anyway.
  final int engagements;

  int get points =>
      friends * ActivityPoints.friend +
      ideas * ActivityPoints.idea +
      couples * ActivityPoints.couple +
      engagements * ActivityPoints.engagement;
}

/// One bar on the activity chart.
class ActivityBucket {
  const ActivityBucket({
    required this.label,
    required this.points,
    required this.period,
  });

  final String label;

  /// Weighted activity points, not a count of events.
  final int points;

  /// The month the bar stands for, so tapping it can move the whole screen to
  /// that month rather than only highlighting a column.
  final MonthPeriod period;
}

/// How much the matchmaker actually did, counted from the records themselves.
///
/// Deliberately not "time spent in the app". Sitting on the ideas screen for an
/// hour is not work, and adding a friend on the bus is. **Four** things are
/// counted, and they are the four that change something for a real person:
///
/// * a friend added,
/// * an idea opened,
/// * a couple who started going out,
/// * an engagement.
///
/// **A status update is not activity.** It used to be, and it was the one
/// countable thing in the app that cost nothing to produce: a proposal moved to
/// "בבדיקה" and back again is two rows in a ledger and no change in anybody's
/// life. Dropping it is what lets the remaining four be weighted honestly —
/// there is no longer any figure here that rewards tapping.
///
/// **A note is not activity either**, for the older version of the same reason:
/// counting notes rewards typing rather than doing, and someone who keeps
/// careful notes on one candidate would out-score someone who opened five
/// proposals.
///
/// Each event is counted from its own dated record rather than from an activity
/// log, which has two consequences worth keeping: the history survives however
/// long ago it happened, and editing the same record ten times is one event.
abstract final class ActivityStats {
  /// The day an event falls on, as a key. Everything deduplicated here is
  /// deduplicated *per day* rather than for all time: adding the same friend
  /// again next month is a real second act of matchmaking.
  static String _dayKey(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  /// A name reduced to what makes two entries the same person: no case, no
  /// runs of whitespace, no punctuation between the parts.
  static String _nameKey(Person person) => person.fullName
      .toLowerCase()
      .replaceAll(RegExp(r'''[\s'"־–—.,()\-]+'''), ' ')
      .trim();

  /// The day each proposal became a wedding, from the ledger where there is
  /// one and from the proposal's own `updatedAt` where there is not.
  ///
  /// The fallback is not a guess for its own sake: [MatchStatusEvent] only
  /// started being written on 2026-08-14, and every couple who married before
  /// that has no event to read. Their date is approximate; that they married is
  /// not, and dropping them would quietly erase the best thing in the database.
  static Map<String, DateTime> _engagementDates(
    List<MatchIdea> matches,
    List<MatchStatusEvent> statusEvents,
  ) {
    final Map<String, DateTime> byMatch = <String, DateTime>{};
    for (final MatchStatusEvent event in statusEvents) {
      if (event.toStatus != MatchStatus.married) {
        continue;
      }
      final DateTime? seen = byMatch[event.matchId];
      // The first time it was marked, not the last. A record edited a year
      // later did not get engaged a year later.
      if (seen == null || event.createdAt.isBefore(seen)) {
        byMatch[event.matchId] = event.createdAt;
      }
    }
    return <String, DateTime>{
      for (final MatchIdea match in matches)
        if (match.status == MatchStatus.married)
          match.id: byMatch[match.id] ?? match.updatedAt,
    };
  }

  /// The four events inside `[start, end)`.
  ///
  /// [datingCouples] lets a caller counting several windows over the same data
  /// build the dating history once. It is the expensive part of this — it reads
  /// the whole status ledger — and building it four times to answer "היום,
  /// השבוע, החודש, כל הזמנים" is three times too many.
  static ActivityBreakdown breakdownBetween({
    required DateTime start,
    required DateTime end,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    Set<String> excludedFromDating = const <String>{},
    List<DatingCoupleRecord>? datingCouples,
    DateTime? now,
  }) {
    bool inRange(DateTime at) => !at.isBefore(start) && at.isBefore(end);

    // Everything below is counted through this set, so the same act can never
    // be worth two. It exists because the figure is not private any more: it
    // feeds the community total and the leaderboard, and a number anybody can
    // inflate by adding the same person twice is not worth showing to others.
    final Set<String> counted = <String>{};
    bool once(String key) => counted.add(key);

    // A friend added. Deduplicated by name *and day*, which covers three cases
    // at once: an import run twice, a contact added twice by hand, and a record
    // deleted and immediately re-added — that last one comes back with a new
    // id, so an id-based check would miss it entirely.
    //
    // An import of thirty new friends is thirty points. That is the intended
    // answer: thirty real people entered the database, and the only thing this
    // rule takes out is the duplicates that never actually arrived.
    int friends = 0;
    for (final Person person in people) {
      if (person.hidden || !inRange(person.createdAt)) {
        continue;
      }
      if (once('person:${_nameKey(person)}:${_dayKey(person.createdAt)}')) {
        friends++;
      }
    }

    // An idea opened. Keyed by the pair rather than by the proposal id, for the
    // same delete-and-reopen reason.
    int ideas = 0;
    for (final MatchIdea match in matches) {
      if (!inRange(match.createdAt)) {
        continue;
      }
      final List<String> pair = <String>[match.personAId, match.personBId]
        ..sort();
      if (once('idea:${pair.join('|')}:${_dayKey(match.createdAt)}')) {
        ideas++;
      }
    }

    // Couples, from the same history the rest of the app counts them with — so
    // "זוגות שהתחילו לצאת" on the stats screen and the five points here can
    // never disagree about what a couple is. A couple enters the count a day
    // after the status was set and never leaves it again.
    final List<DatingCoupleRecord> dating =
        datingCouples ??
        DatingHistory.all(
          matches: matches,
          statusEvents: matchStatusEvents,
          excludedMatchIds: excludedFromDating,
          now: now,
        );
    int couples = 0;
    for (final DatingCoupleRecord record in dating) {
      if (inRange(record.startedAt)) {
        couples++;
      }
    }

    int engagements = 0;
    for (final DateTime at in _engagementDates(
      matches,
      matchStatusEvents,
    ).values) {
      if (inRange(at)) {
        engagements++;
      }
    }

    return ActivityBreakdown(
      friends: friends,
      ideas: ideas,
      couples: couples,
      engagements: engagements,
    );
  }

  /// Everything that ever happened, which is what "הנתונים שלך" shows.
  static ActivityBreakdown allTime({
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    Set<String> excludedFromDating = const <String>{},
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    return breakdownBetween(
      start: DateTime(2000),
      end: DateTime(at.year, at.month, at.day).add(const Duration(days: 1)),
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      excludedFromDating: excludedFromDating,
      now: at,
    );
  }

  /// One bar per Hebrew month, oldest first — the same month division the rest
  /// of the app already uses, so the chart and the figures beside it agree.
  static List<ActivityBucket> monthlyBars({
    required List<MonthPeriod> periods,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    Set<String> excludedFromDating = const <String>{},
    DateTime? now,
  }) {
    // Built once for every bar rather than once per bar: the ledger scan is the
    // whole cost of this call.
    final List<DatingCoupleRecord> dating = DatingHistory.all(
      matches: matches,
      statusEvents: matchStatusEvents,
      excludedMatchIds: excludedFromDating,
      now: now,
    );

    return <ActivityBucket>[
      for (final MonthPeriod period in periods.reversed)
        ActivityBucket(
          label: period.shortLabel,
          period: period,
          points: breakdownBetween(
            start: period.start,
            end: period.end,
            people: people,
            matches: matches,
            matchStatusEvents: matchStatusEvents,
            datingCouples: dating,
            now: now,
          ).points,
        ),
    ];
  }

  /// A word for how the month has gone.
  ///
  /// Generous on purpose, and never comparative: the scale is what this
  /// matchmaker did, not how they rank against anybody. There is no wording for
  /// "not enough" because there is no such amount.
  static String grade(int points) {
    if (points == 0) {
      return 'מוכנים להתחיל';
    }
    if (points < 5) {
      return 'התחלה טובה';
    }
    if (points < 20) {
      return 'חודש פעיל';
    }
    if (points < 60) {
      return 'קצב יפה';
    }
    return 'בונה בתים';
  }
}
