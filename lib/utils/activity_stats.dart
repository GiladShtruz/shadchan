import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/score_ledger.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/monthly_stats.dart';

/// What one act of matchmaking is worth.
///
/// **Weighted, and deliberately not flat.** Adding a friend and marrying two
/// people off are both work, and calling them both "פעולה אחת" is the fastest
/// way to make the whole figure meaningless. The four weights below are the
/// product decision, and the wording that goes with them is "נקודות פעילות"
/// rather than "פעולות" for exactly that reason: not every event is worth one.
abstract final class ActivityPoints {
  static const int friend = ScoreRules.friend;
  static const int card = ScoreRules.card;
  static const int idea = ScoreRules.idea;
  static const int couple = ScoreRules.dating;
  static const int engagement = ScoreRules.engaged;

  /// The one line that fits under a figure. The full table is [scoringLines],
  /// which is what the home block's explanation opens.
  static const String shortExplanation =
      'חבר מאנשי הקשר = נקודה · כרטיס אישי = 2 · רעיון = נקודה · '
      'זוג שיוצא = 5 · אירוסין = 50';

  static const String howItIsCountedTitle = 'איך הפעילות נספרת?';

  /// The scoring method, said in full and in the order the acts happen in.
  static const List<String> scoringLines = <String>[
    'הוספת חבר מאנשי הקשר = נקודת פעילות אחת.',
    'חבר שאישר לך גישה לכרטיס האישי שלו = 2 נקודות בסך הכול.',
    'פתיחת רעיון = נקודת פעילות אחת.',
    'זוג שהתחיל לצאת = 5 נקודות פעילות.',
    'זוג שהתארס = 50 נקודות פעילות.',
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
    'נקודת חבר ניתנת רק על הוספה מאנשי הקשר שלך — הוספה ידנית, ייבוא AI '
        'או שיתוף כרטיס לא מזכים בה.',
    'כל אירוע נספר פעם אחת בלבד: מחיקה והוספה מחדש, או שינוי סטטוס הלוך '
        'ושוב, לא מוסיפים נקודות.',
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
    int? friendPoints,
  }) : _friendPoints = friendPoints;

  static const ActivityBreakdown empty = ActivityBreakdown();

  /// Friends who earned their base points: added from the contacts, or
  /// whose personal card the matchmaker was given (counted once each).
  final int friends;

  final int? _friendPoints;

  /// The friends' base points — 1 each from the contacts, 2 for a card.
  int get friendPoints => _friendPoints ?? friends * ActivityPoints.friend;

  /// Proposals opened.
  final int ideas;

  /// Couples who started dating — counted at once, unless taken back as a
  /// mis-tap inside [DatingHistory.mistakeWindow].
  final int couples;

  /// Engagements and weddings, which are one event here — the app has no
  /// separate "מאורסים" status, and the community figures would have to add the
  /// two together anyway.
  final int engagements;

  int get points =>
      friendPoints +
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

  /// The friends counted as added inside `[start, end)`, newest first.
  ///
  /// Deduplicated by name *and day*, which covers three cases at once: an
  /// import run twice, a contact added twice by hand, and a record deleted and
  /// immediately re-added — that last one comes back with a new id, so an
  /// id-based check would miss it entirely.
  ///
  /// An import of thirty new friends is thirty entries. That is the intended
  /// answer: thirty real people entered the database, and the only thing this
  /// rule takes out is the duplicates that never actually arrived.
  ///
  /// This is the list *and* the number: [breakdownBetween] counts it, and the
  /// drill-down screen shows it.
  static List<Person> countedFriends({
    required DateTime start,
    required DateTime end,
    required List<Person> people,
  }) {
    final Set<String> seen = <String>{};
    final List<Person> found = <Person>[];
    for (final Person person in people) {
      if (person.hidden ||
          person.createdAt.isBefore(start) ||
          !person.createdAt.isBefore(end)) {
        continue;
      }
      if (seen.add('${_nameKey(person)}:${_dayKey(person.createdAt)}')) {
        found.add(person);
      }
    }
    found.sort((Person a, Person b) => b.createdAt.compareTo(a.createdAt));
    return found;
  }

  /// The proposals counted as opened inside `[start, end)`, newest first.
  ///
  /// Keyed by the pair rather than by the proposal id, for the same
  /// delete-and-reopen reason [countedFriends] is keyed by name.
  static List<MatchIdea> countedIdeas({
    required DateTime start,
    required DateTime end,
    required List<MatchIdea> matches,
  }) {
    final Set<String> seen = <String>{};
    final List<MatchIdea> found = <MatchIdea>[];
    for (final MatchIdea match in matches) {
      if (match.createdAt.isBefore(start) || !match.createdAt.isBefore(end)) {
        continue;
      }
      final List<String> pair = <String>[match.personAId, match.personBId]
        ..sort();
      if (seen.add('${pair.join('|')}:${_dayKey(match.createdAt)}')) {
        found.add(match);
      }
    }
    found.sort(
      (MatchIdea a, MatchIdea b) => b.createdAt.compareTo(a.createdAt),
    );
    return found;
  }

  /// The end of "today" as every all-time count here uses it: tomorrow's
  /// midnight, so an event recorded a minute ago is inside the window.
  static DateTime endOfToday([DateTime? now]) {
    final DateTime at = now ?? DateTime.now();
    return DateTime(at.year, at.month, at.day).add(const Duration(days: 1));
  }

  /// Where every all-time count in the app starts.
  static final DateTime beginningOfTime = DateTime(2000);

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
    // **Every figure comes from the score ledger** — the same events the
    // profile, the board, "שדכני השבוע" and each friend's card add up. The
    // records are only read to bring the ledger up to date.
    return fromEvents(
      ScoreLedger.reconcile(
        people: people,
        matches: matches,
        statusEvents: matchStatusEvents,
        excludedFromDating: excludedFromDating,
        datingCouples: datingCouples,
        now: now,
      ),
      start: start,
      end: end,
    );
  }

  /// The events inside `[start, end)`, added up.
  static ActivityBreakdown fromEvents(
    Iterable<ScoreEvent> events, {
    required DateTime start,
    required DateTime end,
  }) {
    int friends = 0;
    int friendPoints = 0;
    int ideas = 0;
    int couples = 0;
    int engagements = 0;
    for (final ScoreEvent event in events) {
      if (event.at.isBefore(start) || !event.at.isBefore(end)) continue;
      switch (event.type) {
        case ScoreEventType.friend:
          friends++;
          friendPoints += event.points;
        case ScoreEventType.card:
          // A card on top of a contacts friend is the same friend: one more
          // point, not one more friend.
          if (event.points >= ScoreRules.card) friends++;
          friendPoints += event.points;
        case ScoreEventType.idea:
          ideas++;
        case ScoreEventType.dating:
          couples++;
        case ScoreEventType.engaged:
          engagements++;
      }
    }
    return ActivityBreakdown(
      friends: friends,
      friendPoints: friendPoints,
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
    // **Remembered between rebuilds.** The home screen, its figures, its
    // progress line and the profile all ask for the same all-time count, and
    // each rebuild of the page used to walk every ledger again — on a large
    // database that was a dropped frame per notification. The key changes
    // with anything that can change the answer: a record added or removed, a
    // record edited (its `updatedAt`), a status event, an exclusion, the day.
    String? key;
    if (now == null) {
      int latest = 0;
      for (final Person p in people) {
        final int t = p.updatedAt.millisecondsSinceEpoch;
        if (t > latest) latest = t;
      }
      for (final MatchIdea m in matches) {
        final int t = m.updatedAt.millisecondsSinceEpoch;
        if (t > latest) latest = t;
      }
      key =
          '${people.length}|${matches.length}|${matchStatusEvents.length}|'
          '${excludedFromDating.length}|$latest|'
          '${at.year}-${at.month}-${at.day}';
      final (String, ActivityBreakdown)? memo = _allTimeMemo;
      if (memo != null && memo.$1 == key) return memo.$2;
    }
    final ActivityBreakdown result = breakdownBetween(
      start: beginningOfTime,
      end: endOfToday(at),
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      excludedFromDating: excludedFromDating,
      now: at,
    );
    if (key != null) _allTimeMemo = (key, result);
    return result;
  }

  static (String, ActivityBreakdown)? _allTimeMemo;

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
