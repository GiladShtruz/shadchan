import 'dart:math' as math;

/// The community's weekly target, and the rule that moves it.
///
/// A shared goal only works if it is reachable. The whole rule set here exists
/// to keep it that way in both directions: it rises when the community is
/// clearly outgrowing it, it rises gently when the community is merely keeping
/// up, and **it never falls** — a target that drops after a quiet week teaches
/// that the quiet week was the problem, which is the opposite of the point.
///
/// Pure arithmetic, no Firestore. It is the one part of the community layer
/// worth being able to test without a network.
abstract final class CommunityGoal {
  /// A brand-new community has nothing to grow from, and a target of three
  /// actions is not a target. The first week is a round number to aim at.
  static const int firstTarget = 50;

  /// The most a target may rise in one step, however good the week was. A
  /// community that doubles once should not be handed double again.
  static const double maxGrowth = 0.15;

  /// How many finished weeks are needed before the four-week average is worth
  /// weighing at all.
  static const int smoothingWeeks = 4;

  /// The target for the coming week.
  ///
  /// [lastTarget] and [lastActual] are the week just finished. [recentActuals]
  /// is that week and the ones before it, newest first — used only once there
  /// are [smoothingWeeks] of them, so that a single freak week (a festival, a
  /// launch, one matchmaker importing a group of four hundred) moves the target
  /// by a fraction of what it would move on its own.
  static int nextTarget({
    required int lastTarget,
    required int lastActual,
    List<int> recentActuals = const <int>[],
  }) {
    if (lastTarget <= 0 && lastActual <= 0) {
      return firstTarget;
    }

    // The floor the raise applies to. Taking the higher of the two is what
    // "5% מעל היעד/תוצאת השבוע הקודם" means: a community that sailed past its
    // target grows from what it actually did, not from what it was asked for.
    final int base = math.max(lastTarget, lastActual);

    double raise;
    if (lastActual < lastTarget) {
      // Missed. The target holds where it was — it is not lowered, and it is
      // not raised either.
      return math.max(lastTarget, 1);
    } else if (lastActual > lastTarget * 1.10) {
      raise = 0.10;
    } else {
      raise = 0.05;
    }

    final double? average = _averageGrowth(recentActuals);
    if (average != null) {
      // Half the rule, half the trend. Enough for a run of strong weeks to
      // pull the target up faster than 10%, and enough for a run of flat ones
      // to hold it back — without either one deciding alone.
      raise = (raise + average) / 2;
    }

    final int next = (base * (1 + raise.clamp(0, maxGrowth))).round();
    return math.max(next, base + 1);
  }

  /// The mean week-over-week growth across [actuals] (newest first), or null
  /// when there is not enough history to mean anything.
  ///
  /// Negative growth is floored at zero rather than allowed to pull the target
  /// down: a shrinking fortnight is exactly when a community needs its goal to
  /// stay where it was.
  static double? _averageGrowth(List<int> actuals) {
    if (actuals.length < smoothingWeeks) {
      return null;
    }
    final List<int> window = actuals.take(smoothingWeeks).toList();
    double total = 0;
    int steps = 0;
    for (int i = 0; i < window.length - 1; i++) {
      final int newer = window[i];
      final int older = window[i + 1];
      if (older <= 0) {
        continue;
      }
      total += ((newer - older) / older).clamp(0.0, maxGrowth);
      steps++;
    }
    return steps == 0 ? null : total / steps;
  }

  /// How far along the week is, 0..1 — capped for the meter, but see
  /// [isOverTarget]: passing the goal does not stop the counting.
  static double progress({required int actual, required int target}) {
    if (target <= 0) {
      return 1;
    }
    return (actual / target).clamp(0.0, 1.0);
  }

  static bool isOverTarget({required int actual, required int target}) =>
      target > 0 && actual > target;

  /// The one line under the meter.
  static String message({required int actual, required int target}) {
    if (target <= 0) {
      return 'מתחילים לספור את השבוע.';
    }
    if (actual > target) {
      return 'עברנו את היעד השבועי! ממשיכים לראות כמה רחוק נגיע?';
    }
    if (actual == target) {
      return 'הגענו ליעד השבועי. כל פעולה מכאן היא בונוס.';
    }
    final int remaining = target - actual;
    if (remaining <= 10) {
      return 'עוד $remaining פעולות והקהילה שם.';
    }
    return 'עוד $remaining פעולות ליעד המשותף.';
  }
}
