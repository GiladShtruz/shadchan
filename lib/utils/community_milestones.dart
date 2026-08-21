import 'package:shadchan/services/community_service.dart';

/// One thing the whole community reached.
class CommunityMilestone {
  const CommunityMilestone({
    required this.id,
    required this.title,
    required this.body,
    required this.emoji,
  });

  /// Stable across releases — it is what "already celebrated" is remembered by.
  final String id;

  final String title;
  final String body;

  /// The one mark on the card. Big, and the only decoration on it.
  final String emoji;
}

/// What the community is congratulated on, and — the part that took the most
/// deciding — **how rarely**.
///
/// These are not the personal milestones in `CommunityAchievements`. Those are
/// about the reader and arrive as a toast at the moment they earn one. This is
/// about everybody: "הקהילה הגיעה ל־1,000 רעיונות", "100 זוגות יצאו לדייט דרך
/// שדכני הקהילה". Nobody did it, so nobody is being congratulated — it is news,
/// and the pleasure in it is belonging to the number rather than owning it.
///
/// **Three rules keep it from becoming noise.**
///
/// 1. **The rungs are far apart and there are few of them.** A thousand ideas,
///    then two and a half, then five, then ten. A community that is growing
///    crosses one of these a few times a year, not a few times a month.
/// 2. **Nothing already passed is ever announced.** The first resolved read on
///    a device writes down everything reached and says nothing — see
///    [CommunityProfileStore.hasBaselinedCommunityMilestones]. Without that,
///    every fresh install would open on a celebration of something that
///    happened long before it existed.
/// 3. **One at a time, and it rides the same one-prompt-per-launch gate as
///    everything else the app says on its own.** [firstUnseen] returns a single
///    milestone even when a quiet fortnight crossed two.
abstract final class CommunityMilestones {
  /// Ideas opened across the whole community.
  static const List<int> ideaMilestones = <int>[
    1000,
    2500,
    5000,
    10000,
    25000,
    50000,
  ];

  /// Couples who went out on a date through a matchmaker in this community.
  ///
  /// The lowest rung is a hundred and it climbs slowly, because every one of
  /// these is worth more than any count of records: a couple who met is the
  /// only figure in the app that is not about the app.
  static const List<int> coupleMilestones = <int>[100, 250, 500, 1000, 2500];

  /// Engagements — the rarest, and the shortest ladder.
  static const List<int> engagementMilestones = <int>[25, 50, 100, 250, 500];

  /// Friends in everybody's databases together.
  static const List<int> friendMilestones = <int>[
    5000,
    10000,
    25000,
    50000,
    100000,
  ];

  /// The highest rung of [milestones] that [value] has reached, or null.
  static int? reached(List<int> milestones, int value) {
    int? best;
    for (final int milestone in milestones) {
      if (value >= milestone) {
        best = milestone;
      }
    }
    return best;
  }

  /// The one milestone worth showing now, or null when there is nothing new.
  ///
  /// Ordered by what is worth hearing: couples, then engagements, then the
  /// counts. Ten thousand ideas is a lovely number; a hundred couples is a
  /// hundred couples.
  ///
  /// [allTime] must be a *resolved* read — an unresolved zero is "we do not
  /// know", and treating it as an answer would silently baseline a device at
  /// nothing and then congratulate it on everything at the next launch.
  static CommunityMilestone? firstUnseen({
    required CommunityTotals allTime,
    required Set<String> seen,
  }) {
    if (!allTime.resolved) {
      return null;
    }

    final List<CommunityMilestone> candidates = <CommunityMilestone>[
      if (reached(coupleMilestones, allTime.couples) case final int milestone)
        CommunityMilestone(
          id: 'community.couples.$milestone',
          title: '$milestone זוגות יצאו לדייט דרך שדכני הקהילה',
          body: 'כל אחד מהם התחיל ממישהו שחשב על מישהו. תודה שאתם חלק מזה.',
          emoji: '💞',
        ),
      if (reached(engagementMilestones, allTime.engagements)
          case final int milestone)
        CommunityMilestone(
          id: 'community.engagements.$milestone',
          title: '$milestone זוגות כבר הגיעו לחופה מהקהילה',
          body: 'מזל טוב לכולם. שנזכה להמשיך.',
          emoji: '🎉',
        ),
      if (reached(ideaMilestones, allTime.ideas) case final int milestone)
        CommunityMilestone(
          id: 'community.ideas.$milestone',
          title: 'הקהילה הגיעה ל־${_grouped(milestone)} רעיונות',
          body: 'זה הרבה מאוד מחשבה על אנשים אחרים. ממשיכים.',
          emoji: '💡',
        ),
      if (reached(friendMilestones, allTime.friends) case final int milestone)
        CommunityMilestone(
          id: 'community.friends.$milestone',
          title: '${_grouped(milestone)} חברים כבר במאגרים של הקהילה',
          body: 'ככל שהמאגרים גדלים, יש למי לחשוב.',
          emoji: '🌱',
        ),
    ];

    for (final CommunityMilestone candidate in candidates) {
      if (!seen.contains(candidate.id)) {
        return candidate;
      }
    }
    return null;
  }

  /// Every milestone currently reached, for the silent first pass.
  static List<String> reachedIds(CommunityTotals allTime) {
    return <String>[
      if (reached(coupleMilestones, allTime.couples) case final int m)
        'community.couples.$m',
      if (reached(engagementMilestones, allTime.engagements) case final int m)
        'community.engagements.$m',
      if (reached(ideaMilestones, allTime.ideas) case final int m)
        'community.ideas.$m',
      if (reached(friendMilestones, allTime.friends) case final int m)
        'community.friends.$m',
    ];
  }

  /// "10,000" rather than "10000" — four figures are read at a glance and
  /// counted otherwise.
  static String _grouped(int value) {
    final String digits = value.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }
}
