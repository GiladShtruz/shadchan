import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/enums.dart';

/// Turns this device's own ledgers into the numbers the community layer
/// publishes.
///
/// Everything is derived rather than accumulated. There is no running counter
/// anywhere: each figure is recounted from the records that caused it, which is
/// what makes a double publish harmless, a restored backup correct, and a
/// deleted record actually disappear from the total.
///
/// **The windows here are Gregorian**, unlike the Hebrew month the personal
/// activity card on the home screen uses. Two matchmakers' months have to be
/// the same month before their numbers can be added together, and "החודש" on a
/// screen that puts your figure beside the community's has to mean one thing.
abstract final class CommunityCounts {
  /// A couple is only counted once they have been "מתחילים לצאת" for this long.
  /// A status set and undone within the hour is a correction, not a couple.
  static const Duration datingSettlesAfter = Duration(hours: 24);

  /// [recordBulkImportLimit] only ever reaches the extra `weekForRecord`
  /// figure. Every number that is published, added to a community total or
  /// sorted on a leaderboard is counted with every import included.
  static CommunityMemberCounts build({
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> matchStatusEvents,
    required List<PersonEvent> events,
    DateTime? now,
    int? recordBulkImportLimit,
  }) {
    final DateTime at = now ?? CommunityPeriods.now();
    final DateTime tomorrow = DateTime(
      at.year,
      at.month,
      at.day,
    ).add(const Duration(days: 1));

    int actionsSince(DateTime? start, {int? bulkImportLimit}) =>
        ActivityStats.countBetween(
          start: start ?? DateTime(2000),
          end: tomorrow,
          people: people,
          matches: matches,
          matchStatusEvents: matchStatusEvents,
          events: events,
          bulkImportLimit: bulkImportLimit,
        );

    final DateTime? weekStart = CommunityPeriods.startOf(
      CommunityPeriod.week,
      at,
    );
    final Set<String> couples = _settledCouples(matchStatusEvents, at: at);
    final Set<String> weekCouples = _settledCouples(
      matchStatusEvents,
      at: at,
      since: weekStart,
    );

    return CommunityMemberCounts(
      day: actionsSince(CommunityPeriods.startOf(CommunityPeriod.day, at)),
      week: actionsSince(weekStart),
      month: actionsSince(CommunityPeriods.startOf(CommunityPeriod.month, at)),
      allTime: actionsSince(null),
      ideas: matches.length,
      couples: couples.length,
      weekCouples: weekCouples.length,
      weekForRecord: recordBulkImportLimit == null
          ? null
          : actionsSince(weekStart, bulkImportLimit: recordBulkImportLimit),
    );
  }

  /// Proposals that have been "מתחילים לצאת" for more than a day.
  ///
  /// Counted from the *event*, not from the proposal's current status, which is
  /// what makes this history: a couple who later stopped, or who married, still
  /// started dating, and the community figure is a record of what happened
  /// rather than a census of who is out this evening.
  static Set<String> _settledCouples(
    List<MatchStatusEvent> events, {
    required DateTime at,
    DateTime? since,
  }) {
    final DateTime cutoff = at.subtract(datingSettlesAfter);
    return <String>{
      for (final MatchStatusEvent event in events)
        if (event.toStatus == MatchStatus.dating &&
            event.createdAt.isBefore(cutoff) &&
            (since == null || !event.createdAt.isBefore(since)))
          event.matchId,
    };
  }
}
