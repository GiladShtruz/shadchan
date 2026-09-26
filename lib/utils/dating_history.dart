import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/utils/enums.dart';

/// One couple that is in the historic "started dating" count, and when they
/// entered it.
class DatingCoupleRecord {
  const DatingCoupleRecord({
    required this.match,
    required this.startedAt,
    required this.estimated,
  });

  final MatchIdea match;

  /// When they were marked as starting to date.
  final DateTime startedAt;

  /// True when the date is inferred from the proposal's own `updatedAt` rather
  /// than read from the status ledger — every couple who started dating before
  /// the ledger existed is in this state. The couple is certainly in the count;
  /// only the date is approximate, so the UI must not present it as exact.
  final bool estimated;
}

/// Which couples have ever started dating — the whole history, not this month.
///
/// A couple counts **the moment they are marked "מתחילים לצאת"** — there used
/// to be a day's wait before they were believed, and the list stayed empty
/// through exactly the day a matchmaker most wants to see them in it.
///
/// A mis-tap is still kept out, without the wait: a stretch of "יוצאים" that
/// was taken back inside [mistakeWindow] to anything other than "יצאו" or
/// "חתונה" was never a date. Anything else marked by mistake is taken out by
/// hand, with a long press on its row in "זוגות שיצאו".
///
/// Once in, a couple stays in. They are part of what this matchmaker did even
/// if they later stopped seeing each other — that is what makes it a history
/// rather than a snapshot, and a number that could go *down* is a number nobody
/// wants to look at.
///
/// Two sources, because one of them is younger than the data. [MatchStatusEvent]
/// is the record of record, but it only started being written on 2026-08-14,
/// so every couple from before that has no dating event to read. For those the
/// proposal's own status stands in: a proposal sitting at "יוצאים", "יצאו" or
/// "חתונה" plainly went out at some point, whatever the ledger does or does not
/// remember. Where the ledger *does* carry a dating transition it is trusted
/// outright, including when it says the status did not hold — so correcting a
/// mis-tap keeps working exactly as it should.
abstract final class DatingHistory {
  /// How soon a "יוצאים" taken back counts as a mis-tap rather than a date.
  static const Duration mistakeWindow = Duration(hours: 24);

  /// Every couple in the count, newest first.
  static List<DatingCoupleRecord> all({
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> statusEvents,
    Set<String> excludedMatchIds = const <String>{},
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();

    final Map<String, List<MatchStatusEvent>> byMatch =
        <String, List<MatchStatusEvent>>{};
    for (final MatchStatusEvent event in statusEvents) {
      byMatch.putIfAbsent(event.matchId, () => <MatchStatusEvent>[]).add(event);
    }
    for (final List<MatchStatusEvent> events in byMatch.values) {
      events.sort(
        (MatchStatusEvent a, MatchStatusEvent b) =>
            a.createdAt.compareTo(b.createdAt),
      );
    }

    final List<DatingCoupleRecord> found = <DatingCoupleRecord>[];
    for (final MatchIdea match in matches) {
      if (excludedMatchIds.contains(match.id)) {
        continue;
      }

      final List<MatchStatusEvent> events =
          byMatch[match.id] ?? const <MatchStatusEvent>[];
      final DateTime? fromLedger = _ledgerStart(events, at);
      if (fromLedger != null) {
        found.add(
          DatingCoupleRecord(
            match: match,
            startedAt: fromLedger,
            estimated: false,
          ),
        );
        continue;
      }

      // A ledger that has an opinion is the end of the matter.
      if (_hasDatingEvent(events)) {
        continue;
      }

      final DateTime? fromStatus = _statusStart(match, at);
      if (fromStatus != null) {
        found.add(
          DatingCoupleRecord(
            match: match,
            startedAt: fromStatus,
            estimated: true,
          ),
        );
      }
    }

    found.sort(
      (DatingCoupleRecord a, DatingCoupleRecord b) =>
          b.startedAt.compareTo(a.startedAt),
    );
    return found;
  }

  /// How many couples are in the count.
  static int count({
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> statusEvents,
    Set<String> excludedMatchIds = const <String>{},
    DateTime? now,
  }) {
    return all(
      matches: matches,
      statusEvents: statusEvents,
      excludedMatchIds: excludedMatchIds,
      now: now,
    ).length;
  }

  static bool _hasDatingEvent(List<MatchStatusEvent> events) {
    return events.any(
      (MatchStatusEvent event) => event.toStatus == MatchStatus.dating,
    );
  }

  /// The first move into "יוצאים" that was not taken back as a mis-tap, or
  /// null.
  static DateTime? _ledgerStart(List<MatchStatusEvent> events, DateTime at) {
    for (int i = 0; i < events.length; i++) {
      if (events[i].toStatus != MatchStatus.dating) {
        continue;
      }
      final DateTime from = events[i].createdAt;
      // Nothing after it: the stretch is still running, and counts now.
      if (i + 1 >= events.length) {
        return from;
      }
      // The next recorded move is what ended the stretch.
      final MatchStatusEvent next = events[i + 1];
      final bool endedAsDate =
          next.toStatus == MatchStatus.dated ||
          next.toStatus == MatchStatus.married;
      if (endedAsDate || next.createdAt.difference(from) > mistakeWindow) {
        return from;
      }
    }
    return null;
  }

  /// The stand-in for a proposal the ledger never saw start dating.
  static DateTime? _statusStart(MatchIdea match, DateTime at) {
    switch (match.status) {
      // Both of these are states a couple can only reach by going out.
      case MatchStatus.dated:
      case MatchStatus.married:
        return match.updatedAt;
      case MatchStatus.dating:
        return match.updatedAt;
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.unavailable:
      case MatchStatus.rejected:
        return null;
    }
  }
}

/// The couples taken out of the historic count by hand.
///
/// The count is deliberately one-way — a couple who stopped seeing each other
/// stays in it — so this is the only way back out, and it exists for exactly
/// one situation: a proposal marked "מתחילים לצאת" that never was. It removes
/// the couple from the figure and from the list behind it and does nothing
/// else; the proposal keeps whatever status it has, because a wrong number and
/// a wrong status are two different mistakes and fixing one silently is not
/// fixing the other.
abstract final class DatingCountExclusions {
  static const String _key = 'datingCountExclusions';

  static Box<dynamic> get _box => Hive.box<dynamic>('settings');

  /// The `settings` box is opened by `main.dart`, so a test that only wanted a
  /// proposal repository has not got one. Guarded exactly like [ReminderAlerts]:
  /// with no box there is simply nothing excluded.
  static bool get _isReady => Hive.isBoxOpen('settings');

  static Set<String> all() {
    if (!_isReady) {
      return <String>{};
    }
    final Object? stored = _box.get(_key);
    if (stored is! List) {
      return <String>{};
    }
    return stored.whereType<String>().toSet();
  }

  static bool contains(String matchId) => all().contains(matchId);

  static Future<void> exclude(String matchId) async {
    if (!_isReady) {
      return;
    }
    final Set<String> ids = all()..add(matchId);
    await _box.put(_key, ids.toList());
  }

  static Future<void> restore(String matchId) async {
    if (!_isReady) {
      return;
    }
    final Set<String> ids = all()..remove(matchId);
    if (ids.isEmpty) {
      await _box.delete(_key);
      return;
    }
    await _box.put(_key, ids.toList());
  }

  /// Drops a deleted proposal's exclusion, so the key set does not grow a tail
  /// of ids nothing can ever match again.
  static Future<void> forget(String matchId) => restore(matchId);
}
