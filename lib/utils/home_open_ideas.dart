import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// One card of "רעיונות פתוחים" on the home screen: a proposal that is open
/// right now, plus whether its reminder is calling for attention.
class HomeOpenIdea {
  const HomeOpenIdea({required this.match, required this.alerting});

  final MatchIdea match;

  /// True while the reminder has come due and the card has not been opened
  /// since — the badge on the card and its place at the head of the row.
  final bool alerting;
}

/// Picks what the home screen's open-ideas row shows.
///
/// "Open" is only what the matchmaker can act on today: a proposal that is
/// still an idea or being checked, with both sides available. Anything waiting
/// — the proposal itself moved to "בהמתנה", or one of the two people is busy or
/// on a break — belongs to the waiting list, not to this row, and so does a
/// couple that is already dating or a closed proposal.
///
/// A proposal whose reminder has come due leads the row, so the thing that
/// asked to be looked at today is the first card in it.
abstract final class HomeOpenIdeas {
  static List<HomeOpenIdea> build({
    required List<MatchIdea> matches,
    required Person? Function(String personId) personById,
    required bool Function(MatchIdea match) isAlerting,
    required bool Function(DateTime? reminder) isDue,
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
      open.add(HomeOpenIdea(match: match, alerting: isAlerting(match)));
    }

    open.sort((HomeOpenIdea a, HomeOpenIdea b) {
      // A reminder that came due leads, earliest first; everything else keeps
      // the newest idea in front.
      final bool aDue = isDue(a.match.reminderDate);
      final bool bDue = isDue(b.match.reminderDate);
      if (aDue != bDue) {
        return aDue ? -1 : 1;
      }
      if (aDue && bDue) {
        return a.match.reminderDate!.compareTo(b.match.reminderDate!);
      }
      return b.match.createdAt.compareTo(a.match.createdAt);
    });

    if (limit != null && open.length > limit) {
      return open.sublist(0, limit);
    }
    return open;
  }
}
