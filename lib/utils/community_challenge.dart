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
/// **A different thing each week, chosen from the week itself.** The metric is
/// picked by hashing the week key, so every device running this code in the
/// same week shows the same challenge without a byte of coordination — which is
/// what makes it *shared* rather than a private goal that happens to be worded
/// in the plural. The rotation also stops the challenge becoming furniture: the
/// same bar for the same number every week is a bar nobody looks at twice.
///
/// **The target comes from last week, and the point is to beat it.** With a
/// record in hand the wording says so — "בשבוע שעבר הגענו ל־X" — and the target
/// is that record raised by about a tenth and rounded to something a person
/// would say out loud. Without one (a device that was not open last week) the
/// challenge falls back to a fixed, deliberately reachable number and simply
/// does not claim a record it cannot know. See
/// [CommunityProfileStore.communityWeek] for why the record is a remembered
/// reading rather than a queried fact.
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

/// This week's shared challenge, ready to draw.
class CommunityChallenge {
  const CommunityChallenge({
    required this.metric,
    required this.target,
    required this.current,
    required this.record,
  });

  final ChallengeMetric metric;

  /// What the community is aiming at this week.
  final int target;

  /// What it has done so far.
  final int current;

  /// Last week's figure, when this device saw one.
  final int? record;

  /// The invitation, in the plural, with no name in it.
  String get headline => 'השבוע מנסים להגיע יחד ל־$target ${metric.targetNoun}';

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
  }) {
    final ChallengeMetric metric = metricFor(weekKey);
    final int? record = metric.valueInSnapshot(previousWeek);
    return CommunityChallenge(
      metric: metric,
      target: targetFor(metric, record),
      current: metric.valueIn(week),
      record: record,
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
