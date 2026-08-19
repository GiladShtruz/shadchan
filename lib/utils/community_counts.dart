import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/dating_history.dart';

/// Turns this device's own ledgers into the numbers the community layer
/// publishes.
///
/// Everything is derived rather than accumulated. There is no running counter
/// anywhere: each figure is recounted from the records that caused it, which is
/// what makes a double publish harmless, a restored backup correct, and a
/// deleted record actually disappear from the total.
///
/// **The windows here are Gregorian**, unlike the Hebrew months the activity
/// chart is drawn in. Two matchmakers' months have to be the same month before
/// their numbers can be added together, and "החודש" on a screen that puts your
/// figure beside the community's has to mean one thing.
abstract final class CommunityCounts {
  static CommunityMemberCounts build({
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    Set<String> excludedFromDating = const <String>{},
    DateTime? now,
  }) {
    final DateTime at = now ?? CommunityPeriods.now();
    final DateTime tomorrow = DateTime(
      at.year,
      at.month,
      at.day,
    ).add(const Duration(days: 1));

    // Read once and handed to all four windows. It is the only part of the
    // count that walks the whole status ledger.
    final List<DatingCoupleRecord> dating = DatingHistory.all(
      matches: matches,
      statusEvents: matchStatusEvents,
      excludedMatchIds: excludedFromDating,
      now: at,
    );

    ActivityBreakdown since(DateTime? start) => ActivityStats.breakdownBetween(
      start: start ?? DateTime(2000),
      end: tomorrow,
      people: people,
      matches: matches,
      matchStatusEvents: matchStatusEvents,
      datingCouples: dating,
      now: at,
    );

    return CommunityMemberCounts(
      day: since(CommunityPeriods.startOf(CommunityPeriod.day, at)),
      week: since(CommunityPeriods.startOf(CommunityPeriod.week, at)),
      month: since(CommunityPeriods.startOf(CommunityPeriod.month, at)),
      allTime: since(null),
    );
  }
}
