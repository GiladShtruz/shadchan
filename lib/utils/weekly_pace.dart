import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// What the personal weekly pace can be measured in.
///
/// Fixed order: it is also the rotation order [WeeklyPaces.choose] walks
/// through, so the metric a given week lands on never depends on how a list
/// happened to be built.
enum PaceMetric {
  /// Friends added to the database.
  friends,

  /// Ideas opened.
  ideas,

  /// Ideas moved on — a status set by hand, a line written in the journal, a
  /// card sent, a side asked. Counted once per idea per day.
  ideaUpdates,

  /// Everything above, plus couples who went out and weddings.
  actions;

  /// The most one week can sensibly ask for. A week above it — almost always
  /// a bulk import — is a fact about that week, not a pace anybody should be
  /// asked to repeat, so it never becomes the bar.
  int get ceiling => switch (this) {
    PaceMetric.friends => 30,
    PaceMetric.ideas => 15,
    PaceMetric.ideaUpdates => 25,
    PaceMetric.actions => 40,
  };
}

/// How the week's target was arrived at.
enum PaceMode {
  /// "בשבוע שעבר הוספת 4 חברים. השבוע שוברים את השיא?"
  lastWeek,

  /// "השיא שלך הוא 3 רעיונות בשבוע. בוא נעבור אותו."
  record,

  /// Not enough history to speak of a record: a small, gentle opening target,
  /// and no record claimed that does not exist.
  starter,
}

/// This week's personal target, and how far along it is.
class WeeklyPace {
  const WeeklyPace({
    required this.metric,
    required this.mode,
    required this.reference,
    required this.target,
    required this.done,
  });

  final PaceMetric metric;
  final PaceMode mode;

  /// Last week's figure, or the record — whichever [mode] speaks of. Zero for
  /// [PaceMode.starter].
  final int reference;

  /// This week's target: one past [reference].
  final int target;

  /// This week so far. It keeps counting past [target] — reaching the target
  /// is a moment, not the end of the week.
  final int done;

  bool get reached => done >= target;

  double get progress => target <= 0 ? 1 : (done / target).clamp(0.0, 1.0);

  /// The sentence over the bar.
  String headline(Gender? gender) {
    if (reached) {
      return mode == PaceMode.starter
          ? 'עמדת ביעד השבועי 🎉'
          : 'שברת את השיא האישי שלך 🎉';
    }
    switch (mode) {
      case PaceMode.lastWeek:
        return 'בשבוע שעבר ${_did(metric)} ${_count(metric, reference)}. '
            'השבוע שוברים את השיא?';
      case PaceMode.record:
        return 'השיא שלך הוא ${_recordCount(metric, reference)} בשבוע. '
                '{בוא|בואי} נעבור אותו.'
            .forGender(gender);
      case PaceMode.starter:
        return 'השבוע מתחילים בקטן: ${_count(metric, target)}';
    }
  }

  static String _did(PaceMetric metric) => switch (metric) {
    PaceMetric.friends => 'הוספת',
    PaceMetric.ideas => 'פתחת',
    PaceMetric.ideaUpdates => 'עדכנת',
    PaceMetric.actions => 'עשית',
  };

  static String _count(PaceMetric metric, int n) => switch (metric) {
    PaceMetric.friends => n == 1 ? 'חבר אחד' : '$n חברים',
    PaceMetric.ideas ||
    PaceMetric.ideaUpdates => n == 1 ? 'רעיון אחד' : '$n רעיונות',
    PaceMetric.actions => n == 1 ? 'פעולה אחת במאגר' : '$n פעולות במאגר',
  };

  static String _recordCount(PaceMetric metric, int n) => switch (metric) {
    PaceMetric.friends => n == 1 ? 'חבר אחד' : '$n חברים',
    PaceMetric.ideas => n == 1 ? 'רעיון אחד' : '$n רעיונות',
    PaceMetric.ideaUpdates => n == 1 ? 'עדכון רעיון אחד' : '$n עדכוני רעיונות',
    PaceMetric.actions => n == 1 ? 'פעולה אחת' : '$n פעולות',
  };

  @override
  String toString() =>
      'WeeklyPace(${metric.name}, ${mode.name}, ref $reference, '
      '$done/$target)';
}

/// The personal weekly pace on the home screen, for a database that has
/// grown past the stage where growing it is the goal.
///
/// **Up to a hundred friends, building the database is the target** — the
/// milestone bar (10 → 25 → 50 → 100, see `HomeMilestone`) stays exactly as
/// it was. **From a hundred, beating one's own week is.** Each week one
/// metric is picked from what this matchmaker actually does, and the target
/// is one more than last week, or one more than their best week — never a
/// figure shared by everybody, and never a random one.
abstract final class WeeklyPaces {
  /// The database size at which the personal pace replaces the milestones.
  static const int unlockFriends = 100;

  /// How many completed weeks are looked back over.
  static const int historyWeeks = 8;

  /// A metric needs activity in at least this many of those weeks before a
  /// week is built around it.
  static const int minActiveWeeks = 2;

  /// The opening target when there is not enough history for a record.
  static const int starterTarget = 3;

  static const String _unlockedKey = 'home.paceUnlocked';

  /// Whether the personal pace is on. Once a matchmaker reaches a hundred
  /// friends it stays on: a database that dips back under a hundred after a
  /// clean-up does not quietly turn back into a growth target.
  static bool unlocked(int friends) {
    if (friends >= unlockFriends) {
      if (_stored != true) {
        persistHomeSetting(_unlockedKey, 'true');
      }
      return true;
    }
    return _stored == true;
  }

  static bool? get _stored {
    if (!Hive.isBoxOpen('settings')) {
      return null;
    }
    return Hive.box<dynamic>('settings').get(_unlockedKey) == 'true';
  }

  /// The Sunday a week [weeksBack] weeks before the one starting [weekStart].
  static DateTime weekStartBefore(DateTime weekStart, int weeksBack) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day - 7 * weeksBack);

  /// The counts per metric. Index 0 is the current week so far, 1 last week,
  /// and so on up to [historyWeeks].
  static Map<PaceMetric, List<int>> history({
    required DateTime weekStart,
    required DateTime now,
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> statusEvents,
    required List<MatchNote> notes,
    Set<String> excludedFromDating = const <String>{},
  }) {
    final List<DatingCoupleRecord> dating = DatingHistory.all(
      matches: matches,
      statusEvents: statusEvents,
      excludedMatchIds: excludedFromDating,
      now: now,
    );
    final Map<PaceMetric, List<int>> out = <PaceMetric, List<int>>{
      for (final PaceMetric m in PaceMetric.values) m: <int>[],
    };
    for (int back = 0; back <= historyWeeks; back++) {
      final DateTime start = weekStartBefore(weekStart, back);
      final DateTime end = back == 0
          ? ActivityStats.endOfToday(now)
          : weekStartBefore(weekStart, back - 1);
      final ActivityBreakdown week = ActivityStats.breakdownBetween(
        start: start,
        end: end,
        people: people,
        matches: matches,
        matchStatusEvents: statusEvents,
        excludedFromDating: excludedFromDating,
        datingCouples: dating,
        now: now,
      );
      final int updates = ideaUpdatesBetween(
        start: start,
        end: end,
        matches: matches,
        statusEvents: statusEvents,
        notes: notes,
      );
      out[PaceMetric.friends]!.add(week.friends);
      out[PaceMetric.ideas]!.add(week.ideas);
      out[PaceMetric.ideaUpdates]!.add(updates);
      out[PaceMetric.actions]!.add(
        week.friends + week.ideas + updates + week.couples + week.engagements,
      );
    }
    return out;
  }

  /// Ideas moved on inside `[start, end)`: one per idea per day, whatever was
  /// done to it that day. What the app did by itself — a status moved because
  /// a candidate went on a break, a line it wrote on its own — is not counted.
  static int ideaUpdatesBetween({
    required DateTime start,
    required DateTime end,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> statusEvents,
    required List<MatchNote> notes,
  }) {
    bool inRange(DateTime at) => !at.isBefore(start) && at.isBefore(end);
    String day(DateTime at) => '${at.year}-${at.month}-${at.day}';
    final Set<String> touched = <String>{};
    for (final MatchStatusEvent event in statusEvents) {
      if (!event.automatic && inRange(event.createdAt)) {
        touched.add('${event.matchId}:${day(event.createdAt)}');
      }
    }
    for (final MatchNote note in notes) {
      if (!note.isAutomatic && inRange(note.createdAt)) {
        touched.add('${note.matchId}:${day(note.createdAt)}');
      }
    }
    for (final MatchIdea match in matches) {
      for (final DateTime? at in <DateTime?>[
        match.lastShareAt,
        match.askedMaleAt,
        match.askedFemaleAt,
      ]) {
        if (at != null && inRange(at)) {
          touched.add('${match.id}:${day(at)}');
        }
      }
    }
    return touched.length;
  }

  /// The week's pace, from [history] (see [history] for its shape).
  ///
  /// [weekNumber] turns the rotation: the metric changes from week to week
  /// among those with enough history, and stays put for the whole week.
  static WeeklyPace choose({
    required Map<PaceMetric, List<int>> history,
    required int weekNumber,
  }) {
    final List<WeeklyPace> eligible = <WeeklyPace>[];
    for (final PaceMetric metric in PaceMetric.values) {
      final WeeklyPace? pace = _paceFor(metric, history[metric] ?? <int>[]);
      if (pace != null) {
        eligible.add(pace);
      }
    }
    if (eligible.isNotEmpty) {
      return eligible[weekNumber.abs() % eligible.length];
    }
    final List<int> actions = history[PaceMetric.actions] ?? <int>[];
    return WeeklyPace(
      metric: PaceMetric.actions,
      mode: PaceMode.starter,
      reference: 0,
      target: starterTarget,
      done: actions.isEmpty ? 0 : actions.first,
    );
  }

  static WeeklyPace? _paceFor(PaceMetric metric, List<int> weeks) {
    if (weeks.length < 2) {
      return null;
    }
    final int done = weeks.first;
    final List<int> past = weeks.sublist(1);
    final int active = past.where((int n) => n > 0).length;
    if (active < minActiveWeeks) {
      return null;
    }
    final int lastWeek = past.first;
    // The best week that is still a pace — an import of two hundred is left
    // out of the reckoning rather than becoming the bar.
    final int record = past
        .where((int n) => n <= metric.ceiling)
        .fold<int>(0, (int best, int n) => n > best ? n : best);

    // The record, when it is within reach of how this matchmaker has been
    // going lately; otherwise last week, which always is.
    final int reach = lastWeek * 2 > lastWeek + 3 ? lastWeek * 2 : lastWeek + 3;
    if (record > lastWeek && record <= reach) {
      return WeeklyPace(
        metric: metric,
        mode: PaceMode.record,
        reference: record,
        target: record + 1,
        done: done,
      );
    }
    if (lastWeek > 0 && lastWeek <= metric.ceiling) {
      return WeeklyPace(
        metric: metric,
        mode: PaceMode.lastWeek,
        reference: lastWeek,
        target: lastWeek + 1,
        done: done,
      );
    }
    return null;
  }

  /// The number of the week starting [weekStart], counted from a fixed
  /// Sunday — the same on every phone, so the rotation agrees across devices.
  static int weekNumber(DateTime weekStart) {
    final DateTime anchor = DateTime.utc(2024, 1, 7);
    final DateTime start = DateTime.utc(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );
    return start.difference(anchor).inDays ~/ 7;
  }
}
