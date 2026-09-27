import 'package:hive/hive.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/services/home_board_store.dart';

/// Which changes to a friend's own card the matchmaker has already looked at.
///
/// The card tile on a profile shows only what is *new*: meaningful changes
/// from the last month that came after the matchmaker last opened the card's
/// full change history. Opening that history is what "seen" means — the tile
/// is a doorway into it, not a place to read and dismiss lines one by one.
///
/// One timestamp per friend, in the `settings` box, written through
/// [persistHomeSetting] like every store a build reads.
abstract final class CardUpdatesSeen {
  static const String _prefix = 'cardUpdatesSeen.';

  /// How far back an unseen update still counts as news.
  static const Duration window = Duration(days: 30);

  static final Map<String, int> _pending = <String, int>{};

  static DateTime? seenAt(String personId) {
    int? millis = _pending[personId];
    if (millis == null && Hive.isBoxOpen('settings')) {
      final Object? stored = Hive.box<dynamic>('settings').get(
        '$_prefix$personId',
      );
      millis = stored is String ? int.tryParse(stored) : null;
    }
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// The history was opened: everything up to [at] is no longer new.
  static void markSeen(String personId, {DateTime? at}) {
    final int millis = (at ?? DateTime.now()).millisecondsSinceEpoch;
    _pending[personId] = millis;
    persistHomeSetting('$_prefix$personId', millis.toString());
  }

  /// The meaningful updates in [events] still worth showing as new, newest
  /// first as given.
  static List<PersonEvent> fresh(
    Iterable<PersonEvent> events,
    String personId, {
    DateTime? now,
  }) {
    final DateTime from = (now ?? DateTime.now()).subtract(window);
    final DateTime? seen = seenAt(personId);
    return events
        .where(
          (PersonEvent e) =>
              e.type == PersonEventType.cardSynced &&
              e.createdAt.isAfter(from) &&
              (seen == null || e.createdAt.isAfter(seen)),
        )
        .toList();
  }

  static void resetForTest() => _pending.clear();
}
