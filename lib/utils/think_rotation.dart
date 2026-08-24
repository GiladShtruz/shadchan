import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// Which friends "עוצרים רגע לחשוב על חברים" opens on, and who was pushed off
/// for now.
///
/// **Two small pieces of memory, and both exist for the same reason: the screen
/// used to greet everybody with the same faces.** The ranking behind it is
/// deterministic — the same database in the same state produces the same order
/// every time — so a matchmaker who opened the page on Monday, thought about
/// the first three and came back on Tuesday was shown those three again at the
/// top. The point of the page is the opposite of that: it is where the database
/// gets *turned over*.
///
/// [ThinkRotation] is a cursor, advanced once per visit, that the screen
/// rotates the ranked list by. It wraps, so nobody is ever permanently out of
/// reach, and it is capped so the stored value cannot grow without bound on a
/// phone used for years.
///
/// [ThinkLater] is the answer to "אחשוב עליו בהמשך": one friend, put away for
/// [ThinkLater.snooze]. Deliberately a date rather than a flag — "later" is a
/// postponement, not a refusal, and a list somebody can permanently empty is a
/// list that eventually says there is nobody to think about.
abstract final class ThinkRotation {
  static const String _key = 'think.cursor';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The value written this session, readable back immediately.
  ///
  /// The write goes through [persistHomeSetting], which runs on the root zone;
  /// a `Box.put` started inside a widget test's fake-async zone is never driven
  /// to completion and leaves `Hive.close()` hanging in `tearDownAll` for ever.
  /// Every store in this app that writes during a build goes the same way round
  /// for the same reason.
  static int? _pending;

  static int get cursor {
    final Object? raw = _pending ?? _box?.get(_key);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  /// Records where the *next* visit should start.
  static void advance(int by) {
    if (by <= 0) {
      return;
    }
    final int next = (cursor + by) % 100000;
    _pending = next;
    persistHomeSetting(_key, next.toString());
  }

  /// [items] rotated so that the [cursor]-th entry leads.
  ///
  /// A rotation rather than a shuffle: the ranking is the product decision —
  /// somebody who just became available really is worth thinking about before
  /// somebody whose card is merely old — and shuffling throws that away
  /// entirely. Rotating keeps the whole order intact and only changes where it
  /// is entered, so every friend reaches the top of the page eventually and
  /// nobody is drawn twice.
  static List<T> rotate<T>(List<T> items, int cursor) {
    if (items.length < 2) {
      return items;
    }
    final int offset = cursor % items.length;
    if (offset == 0) {
      return items;
    }
    return <T>[...items.sublist(offset), ...items.sublist(0, offset)];
  }
}

/// "אחשוב עליו בהמשך" — friends put away until a date, by person id.
abstract final class ThinkLater {
  static const String _key = 'think.later';

  /// Long enough to clear the page of somebody already considered, short enough
  /// that they come back while the thought is still worth having.
  static const Duration snooze = Duration(days: 30);

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Held in memory as well as in the box for the same reason as
  /// [ThinkRotation._pending]: the write is scheduled on the root zone and the
  /// list has to answer correctly before it lands.
  static Map<String, DateTime>? _cache;

  static Map<String, DateTime> _read() {
    final Map<String, DateTime>? cached = _cache;
    if (cached != null) {
      return cached;
    }
    final Map<String, DateTime> result = <String, DateTime>{};
    final Object? raw = _box?.get(_key);
    if (raw is String && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((Object? id, Object? until) {
            final DateTime? at = until is String
                ? DateTime.tryParse(until)
                : null;
            if (id is String && at != null) {
              result[id] = at;
            }
          });
        }
      } on FormatException {
        // A corrupted entry is not worth a crash on a screen about thinking.
      }
    }
    _cache = result;
    return result;
  }

  static void _write(Map<String, DateTime> value) {
    _cache = value;
    persistHomeSetting(
      _key,
      jsonEncode(<String, String>{
        for (final MapEntry<String, DateTime> entry in value.entries)
          entry.key: entry.value.toIso8601String(),
      }),
    );
  }

  /// The ids still put away right now. Entries whose date has passed are
  /// dropped on read, so the store cleans itself without a sweep.
  static Set<String> activeIds([DateTime? now]) {
    final DateTime at = now ?? DateTime.now();
    final Map<String, DateTime> stored = _read();
    final Set<String> active = <String>{
      for (final MapEntry<String, DateTime> entry in stored.entries)
        if (entry.value.isAfter(at)) entry.key,
    };
    if (active.length != stored.length) {
      _write(<String, DateTime>{
        for (final String id in active) id: stored[id]!,
      });
    }
    return active;
  }

  static void remember(String personId, {DateTime? now}) {
    final Map<String, DateTime> stored = Map<String, DateTime>.of(_read());
    stored[personId] = (now ?? DateTime.now()).add(snooze);
    _write(stored);
  }

  static void forget(String personId) {
    final Map<String, DateTime> stored = Map<String, DateTime>.of(_read());
    if (stored.remove(personId) != null) {
      _write(stored);
    }
  }

  /// Test seam: drops the in-memory copy so the next read comes from the box.
  static void resetCacheForTesting() => _cache = null;
}
