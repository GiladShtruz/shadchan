import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person_event.dart';

/// When an idea last moved, for ordering הרעיונות שלי newest first.
///
/// **Only three things count as an update**: the idea being opened, its own
/// status changing, and either of its two people's status changing. A note,
/// a reminder or a card sent does not — `MatchIdea.updatedAt` moves on all of
/// those, which is why it is not the key.
abstract final class IdeaRecency {
  /// The last update of every idea in [matches], by id.
  static Map<String, DateTime> of({
    required Iterable<MatchIdea> matches,
    required Iterable<MatchStatusEvent> statusEvents,
    required Iterable<PersonEvent> personEvents,
  }) {
    final Map<String, DateTime> lastStatus = <String, DateTime>{};
    for (final MatchStatusEvent event in statusEvents) {
      _keepLatest(lastStatus, event.matchId, event.createdAt);
    }
    final Map<String, DateTime> lastPersonStatus = <String, DateTime>{};
    for (final PersonEvent event in personEvents) {
      if (event.type == PersonEventType.statusChanged) {
        _keepLatest(lastPersonStatus, event.personId, event.createdAt);
      }
    }

    final Map<String, DateTime> result = <String, DateTime>{};
    for (final MatchIdea match in matches) {
      DateTime latest = match.createdAt;
      for (final DateTime? candidate in <DateTime?>[
        lastStatus[match.id],
        lastPersonStatus[match.personAId],
        lastPersonStatus[match.personBId],
      ]) {
        if (candidate != null && candidate.isAfter(latest)) {
          latest = candidate;
        }
      }
      result[match.id] = latest;
    }
    return result;
  }

  static void _keepLatest(Map<String, DateTime> map, String key, DateTime at) {
    final DateTime? known = map[key];
    if (known == null || at.isAfter(known)) {
      map[key] = at;
    }
  }
}
