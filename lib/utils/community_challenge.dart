import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';

/// What the whole community is trying to do this week.
///
/// **One target, one bar, and it belongs to everybody.** The app already tells
/// a matchmaker how far their own database is from the next round number; this
/// is deliberately not that. A personal target is a thing to fall behind on,
/// and somebody who opened the app twice this week does not need a progress bar
/// telling them so. A shared one is the opposite: whatever anybody adds moves
/// it, nobody's contribution is named, and a week where it fills is a week the
/// community had rather than a week the reader had.
///
/// Administrators choose the metric, target and optional public heading in
/// `communityGoals/weekly`. Until configured, a stable hash of the week picks
/// a metric with a fixed opening target, identical on every device. A locally
/// remembered previous week may supply encouragement, never the shared target.
enum ChallengeMetric {
  ideas,
  friends,
  couples;

  /// What the target counts, in the sentence that names it.
  String get targetNoun {
    switch (this) {
      case ChallengeMetric.ideas:
        return 'רעיונות חדשים';
      case ChallengeMetric.friends:
        return 'חברים חדשים';
      case ChallengeMetric.couples:
        return 'זוגות שיוצאים לדייט';
    }
  }

  /// The short form, for the record line and the progress figure.
  String get shortNoun {
    switch (this) {
      case ChallengeMetric.ideas:
        return 'רעיונות';
      case ChallengeMetric.friends:
        return 'חברים';
      case ChallengeMetric.couples:
        return 'זוגות';
    }
  }

  /// Where the challenge starts on a device with no record to beat.
  ///
  /// Chosen to be reachable rather than impressive: a bar that ends the week at
  /// a tenth of its target has taught everybody who saw it to ignore the next
  /// one.
  int get openingTarget {
    switch (this) {
      case ChallengeMetric.ideas:
        return 100;
      case ChallengeMetric.friends:
        return 250;
      case ChallengeMetric.couples:
        return 20;
    }
  }

  int valueIn(CommunityTotals totals) {
    switch (this) {
      case ChallengeMetric.ideas:
        return totals.ideas;
      case ChallengeMetric.friends:
        return totals.friends;
      case ChallengeMetric.couples:
        return totals.couples;
    }
  }

  int? valueInSnapshot(CommunityWeekSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    switch (this) {
      case ChallengeMetric.ideas:
        return snapshot.ideas;
      case ChallengeMetric.friends:
        return snapshot.friends;
      case ChallengeMetric.couples:
        return snapshot.couples;
    }
  }
}

/// The administrator's shared target, applied each week until changed.
class WeeklyCommunityGoal {
  const WeeklyCommunityGoal({
    required this.metric,
    required this.target,
    this.title = '',
  });

  static const int maxTarget = 1000000;
  static const int maxTitleLength = 100;

  final ChallengeMetric metric;
  final int target;
  final String title;

  bool get isValid =>
      target > 0 && target <= maxTarget && title.length <= maxTitleLength;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'metric': metric.name,
    'target': target,
    'title': title.trim(),
  };

  static WeeklyCommunityGoal? fromJson(Map<String, dynamic>? data) {
    if (data == null) return null;
    final Object? target = data['target'];
    final Object? title = data['title'];
    if (target is! int || title is! String) return null;
    for (final ChallengeMetric metric in ChallengeMetric.values) {
      if (data['metric'] == metric.name) {
        final WeeklyCommunityGoal goal = WeeklyCommunityGoal(
          metric: metric,
          target: target,
          title: title,
        );
        return goal.isValid ? goal : null;
      }
    }
    return null;
  }
}

/// This week's shared challenge, ready to draw.
class CommunityChallenge {
  const CommunityChallenge({
    required this.metric,
    required this.target,
    required this.current,
    required this.record,
    this.title = '',
  });

  final ChallengeMetric metric;

  /// What the community is aiming at this week.
  final int target;

  /// What it has done so far.
  final int current;

  /// Last week's figure, when this device saw one.
  final int? record;

  final String title;

  /// The invitation, in the plural, with no name in it.
  String get headline => title.isNotEmpty
      ? title
      : 'השבוע מנסים להגיע יחד ל־$target ${metric.targetNoun}';

  /// The line under it: what happened last week, or — with nothing to compare
  /// to — why the number is there at all.
  String get subline {
    final int? last = record;
    if (last == null || last <= 0) {
      return 'כל רעיון, כל חבר וכל זוג של כל שדכן נספרים כאן.';
    }
    if (beatsRecord) {
      return 'שברנו את השיא של שבוע שעבר ($last ${metric.shortNoun})! ממשיכים.';
    }
    return 'בשבוע שעבר הגענו ל־$last ${metric.shortNoun} — בואו נשבור את השיא '
        'ביחד.';
  }

  /// Between 0 and 1, for the one bar.
  double get progress {
    if (target <= 0) {
      return 0;
    }
    final double ratio = current / target;
    return ratio.clamp(0.0, 1.0);
  }

  bool get reachedTarget => current >= target;

  bool get beatsRecord => record != null && record! > 0 && current > record!;

  /// "43 מתוך 100 רעיונות".
  String get progressLabel => '$current מתוך $target ${metric.shortNoun}';

  /// This week's challenge.
  ///
  /// [weekKey] picks the metric, [week] is the community's running total, and
  /// [previousWeek] is what this device remembers of the last completed week.
  static CommunityChallenge build({
    required String weekKey,
    required CommunityTotals week,
    CommunityWeekSnapshot? previousWeek,
    WeeklyCommunityGoal? goal,
  }) {
    final WeeklyCommunityGoal? configured = goal != null && goal.isValid
        ? goal
        : null;
    final ChallengeMetric metric = configured?.metric ?? metricFor(weekKey);
    final int? record = metric.valueInSnapshot(previousWeek);
    return CommunityChallenge(
      metric: metric,
      // A shared target cannot depend on which phone saw last week's total.
      // The remembered record remains useful as encouragement, never as config.
      target: configured?.target ?? metric.openingTarget,
      current: metric.valueIn(week),
      record: record,
      title: configured?.title.trim() ?? '',
    );
  }

  /// Which challenge [weekKey] carries.
  ///
  /// Its own hash rather than `String.hashCode`: that value is not promised to
  /// be stable between runs or platforms, and two phones showing two different
  /// "shared" challenges in the same week is the one failure this feature
  /// cannot survive.
  static ChallengeMetric metricFor(String weekKey) {
    int hash = 0;
    for (final int unit in weekKey.codeUnits) {
      hash = (hash * 31 + unit) % 100003;
    }
    return ChallengeMetric.values[hash % ChallengeMetric.values.length];
  }

  /// The target for a metric given last week's figure.
  ///
  /// A tenth above the record, never less than one above it, rounded up to
  /// something somebody would say: 5s below fifty, 10s below two hundred, 25s
  /// below five hundred, 50s above that. The rounding is what turns "בואו נגיע
  /// ל־133" into "בואו נגיע ל־140".
  static int targetFor(ChallengeMetric metric, int? record) {
    if (record == null || record <= 0) {
      return metric.openingTarget;
    }
    final int raised = (record * 1.1).ceil();
    return _roundUp(raised > record ? raised : record + 1);
  }

  static int _roundUp(int value) {
    final int step = value < 50
        ? 5
        : value < 200
        ? 10
        : value < 500
        ? 25
        : 50;
    return ((value + step - 1) ~/ step) * step;
  }
}
