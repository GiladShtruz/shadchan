/// How many times the home screen has been opened in this run of the app.
///
/// The rotating parts of the page — which handful of items is worth promoting,
/// which encouraging number is shown — advance on this rather than on a random
/// draw, so consecutive visits are reliably *different* rather than merely
/// unrelated.
///
/// Deliberately in memory only. Persisting it would mean a Hive write during a
/// build, and a Hive write inside a `testWidgets` fake-async zone never
/// completes — it hangs the whole suite. Restarting the app restarting the
/// rotation is a cosmetic detail; a frozen test run is not.
abstract final class HomeVisitCounter {
  static int _visits = 0;

  static int next() => ++_visits;

  /// Test seam: lets a test start from a known point in the rotation.
  static void resetForTesting() => _visits = 0;
}

/// How far along the matchmaker is, expressed as the one number that actually
/// changes what the home screen should say: how many friends are in the
/// database.
///
/// The screen is not a dashboard that shows everything it has. Someone with six
/// friends has no proposals, no couples and no numbers, and showing them six
/// empty boxes teaches that the app is empty. Someone with three hundred does
/// not need to be told to add more. So the same blocks are ordered and
/// emphasised differently, and the ones that would be empty are simply absent —
/// while the colours, the typography and the card shapes stay identical, so the
/// screen never reads as a different app from one week to the next.
enum HomeStage {
  /// 0–9. Almost everything is about getting the first friends in.
  starting,

  /// 10–24. Still mostly growth, but a first idea becomes worth suggesting.
  building,

  /// 25–49. Growth, thinking and existing ideas in balance.
  balancing,

  /// 50–99. A working database: the screen turns into a manager of what to do.
  managing,

  /// 100+. The automatic pair suggestions lead, and the target stops mattering.
  full;

  static HomeStage forCount(int friends) {
    if (friends >= 100) {
      return HomeStage.full;
    }
    if (friends >= 50) {
      return HomeStage.managing;
    }
    if (friends >= 25) {
      return HomeStage.balancing;
    }
    if (friends >= 10) {
      return HomeStage.building;
    }
    return HomeStage.starting;
  }

  /// Whether adding friends is still the loudest thing on the screen.
  bool get leadsWithGrowth =>
      this == HomeStage.starting || this == HomeStage.building;

  /// The bulk-import offer lives on the home screen only until the database is
  /// large enough that it is no longer the fastest way to grow. After that it
  /// stays available, on the add-friends screen.
  bool get showsImportTool =>
      this == HomeStage.starting ||
      this == HomeStage.building ||
      this == HomeStage.balancing;

  /// Below this, an empty ideas or couples row is not drawn at all.
  bool get showsIdeaAreas => this != HomeStage.starting;

  /// The automatic pair suggestions get a high, prominent place of their own.
  bool get leadsWithAutomaticIdeas => this == HomeStage.full;

  /// Once the database is real, the target is no longer a headline.
  bool get showsTarget => this != HomeStage.full;
}

/// The next round number worth reaching, and how far along it is.
///
/// Staged rather than a single "100": a first target of ten is a week's work
/// and is met, while a bar sitting at 6% for a month says only that the
/// matchmaker is failing at something.
class HomeMilestone {
  const HomeMilestone({
    required this.friends,
    required this.target,
    required this.message,
  });

  static const List<int> targets = <int>[10, 25, 50, 100];

  final int friends;

  /// The milestone being worked towards, or null once 100 is passed.
  final int? target;

  /// One positive line about the milestone that is close.
  final String message;

  double get progress {
    final int? target = this.target;
    if (target == null || target == 0) {
      return 1;
    }
    return (friends / target).clamp(0.0, 1.0);
  }

  int get remaining {
    final int? target = this.target;
    return target == null ? 0 : (target - friends).clamp(0, target);
  }

  bool get isReached => target == null;

  static HomeMilestone forCount(int friends) {
    for (final int target in targets) {
      if (friends < target) {
        return HomeMilestone(
          friends: friends,
          target: target,
          message: _messageFor(friends, target),
        );
      }
    }
    return HomeMilestone(
      friends: friends,
      target: null,
      message: 'המאגר שלך גדול ופעיל — מכאן זה כבר עניין של חשיבה והתאמות.',
    );
  }

  static String _messageFor(int friends, int target) {
    final int remaining = (target - friends).clamp(0, target);
    if (friends == 0) {
      return 'החברים הראשונים הם ההתחלה. כל אחד שנוסף פותח כיוון חדש.';
    }
    if (remaining == 1) {
      return 'עוד חבר אחד ואתם ב-$target. ממש קרוב.';
    }
    if (remaining <= 3) {
      return 'עוד $remaining חברים ואתם ב-$target. ממש קרוב.';
    }
    return 'עוד $remaining חברים ליעד של $target.';
  }
}
