import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// One card of "רעיונות פתוחים" on the home screen: a proposal that is open
/// right now, plus whether it is asking for attention today.
class HomeOpenIdea {
  const HomeOpenIdea({
    required this.match,
    required this.alerting,
    this.reopenedAt,
  });

  final MatchIdea match;

  /// True while the reminder has come due and the card has not been opened
  /// since — the badge on the card and its place at the head of the row.
  final bool alerting;

  /// When the proposal came back into the open list after having left it, if
  /// that happened recently. Non-null puts the card at the head of the row
  /// beside the due reminders.
  final DateTime? reopenedAt;

  /// The two reasons a card leads the row: its reminder came due, or it was
  /// reopened.
  bool get leads => alerting || reopenedAt != null;
}

/// Picks what the home screen's open-ideas row shows.
///
/// "Open" is only what the matchmaker can act on today: a proposal that is
/// still an idea or being checked, with both sides available. Anything waiting
/// — the proposal itself moved to "בהמתנה", or one of the two people is busy or
/// on a break — belongs to the waiting list, not to this row, and so does a
/// couple that is already dating or a closed proposal.
///
/// The row carries *every* open proposal, not a filtered pick of them: it is
/// the one place on the home screen that answers "what is open right now", and
/// a row that empties itself whenever nothing is overdue reads as though the
/// open proposals had disappeared. What ordering does instead is put the ones
/// asking for something today — a reminder that came due, a proposal that just
/// came back into play — at the head, and let the rest follow behind them.
abstract final class HomeOpenIdeas {
  static List<HomeOpenIdea> build({
    required List<MatchIdea> matches,
    required Person? Function(String personId) personById,
    required bool Function(MatchIdea match) isAlerting,
    required bool Function(DateTime? reminder) isDue,
    Map<String, DateTime> reopenedAt = const <String, DateTime>{},
    int? limit,
  }) {
    final List<HomeOpenIdea> open = <HomeOpenIdea>[];
    for (final MatchIdea match in matches) {
      final Person? personA = personById(match.personAId);
      final Person? personB = personById(match.personBId);
      final bool anyArchived =
          (personA?.profileStatus.isArchived ?? false) ||
          (personB?.profileStatus.isArchived ?? false);
      final bool anyPaused =
          (personA?.profileStatus.pausesMatches ?? false) ||
          (personB?.profileStatus.pausesMatches ?? false);

      final MatchProposalTab? tab = matchProposalTabFor(
        status: match.status,
        anyPersonArchived: anyArchived,
        anyPersonPaused: anyPaused,
      );
      if (tab != MatchProposalTab.open) {
        continue;
      }
      open.add(
        HomeOpenIdea(
          match: match,
          alerting: isAlerting(match),
          reopenedAt: reopenedAt[match.id],
        ),
      );
    }

    open.sort((HomeOpenIdea a, HomeOpenIdea b) {
      // Two things lead the row: a reminder that came due, and a proposal that
      // was reopened. Everything else keeps the newest idea in front.
      final bool aDue = isDue(a.match.reminderDate);
      final bool bDue = isDue(b.match.reminderDate);
      final bool aLeads = aDue || a.reopenedAt != null;
      final bool bLeads = bDue || b.reopenedAt != null;
      if (aLeads != bLeads) {
        return aLeads ? -1 : 1;
      }
      if (aLeads && bLeads) {
        // Inside the head of the row a due reminder still comes before a
        // reopening: it is the one the matchmaker asked to be reminded about.
        if (aDue != bDue) {
          return aDue ? -1 : 1;
        }
        if (aDue && bDue) {
          return a.match.reminderDate!.compareTo(b.match.reminderDate!);
        }
        return b.reopenedAt!.compareTo(a.reopenedAt!);
      }
      return b.match.createdAt.compareTo(a.match.createdAt);
    });

    if (limit != null && open.length > limit) {
      return open.sublist(0, limit);
    }
    return open;
  }

  /// A proposal counts as reopened when it came back to "רעיון" or "בבדיקה"
  /// from somewhere else — off the waiting list, or after having been closed.
  ///
  /// Only recent moves count: a proposal reopened half a year ago is simply an
  /// open proposal by now, and putting it at the head of the row would say
  /// something about it that is no longer true.
  static Map<String, DateTime> reopenedFromEvents({
    required List<MatchStatusEvent> statusEvents,
    int withinDays = _reopenedWithinDays,
    DateTime? now,
  }) {
    final DateTime cutoff = (now ?? DateTime.now()).subtract(
      Duration(days: withinDays),
    );
    final Map<String, DateTime> reopened = <String, DateTime>{};
    for (final MatchStatusEvent event in statusEvents) {
      if (event.createdAt.isBefore(cutoff)) {
        continue;
      }
      if (!_isOpenStatus(event.toStatus) || _isOpenStatus(event.fromStatus)) {
        continue;
      }
      final DateTime? known = reopened[event.matchId];
      if (known == null || known.isBefore(event.createdAt)) {
        reopened[event.matchId] = event.createdAt;
      }
    }
    return reopened;
  }

  static const int _reopenedWithinDays = 30;

  static bool _isOpenStatus(MatchStatus? status) =>
      status == MatchStatus.idea || status == MatchStatus.checking;
}
