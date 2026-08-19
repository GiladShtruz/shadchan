import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// Per-person "soft rejected" suggestion candidates, stored in the local
/// Hive `settings` box so they survive app restarts.
///
/// Dismissing a suggested candidate only pushes them to the end of the
/// suggestions list for that source person — it does not create a rejected
/// proposal, so the pair never appears under רעיונות שנשללו.
abstract final class SuggestionDismissals {
  static const String _keyPrefix = 'suggestionDismissals.';

  static Box<dynamic> get _box => Hive.box<dynamic>('settings');

  static Set<String> dismissedFor(String personId) {
    final Object? stored = _box.get('$_keyPrefix$personId');
    if (stored is! List) {
      return <String>{};
    }
    return stored.whereType<String>().toSet();
  }

  static bool isDismissed(String personId, String candidateId) {
    return dismissedFor(personId).contains(candidateId);
  }

  static Future<void> dismiss(String personId, String candidateId) async {
    final Set<String> ids = dismissedFor(personId)..add(candidateId);
    await _box.put('$_keyPrefix$personId', ids.toList());
  }

  static Future<void> restore(String personId, String candidateId) async {
    final Set<String> ids = dismissedFor(personId)..remove(candidateId);
    if (ids.isEmpty) {
      await _box.delete('$_keyPrefix$personId');
    } else {
      await _box.put('$_keyPrefix$personId', ids.toList());
    }
  }
}

/// Which batch of "רעיונות שהמאגר מציע לך" to open on next time.
///
/// **A cursor, not a shuffle.** Randomising the ten would show the same
/// matchmaker the same strong pairs over and over and bury the rest; walking a
/// cursor through the rounds means every visit starts where the last one left
/// off, so the whole database gets seen instead of its top corner. It wraps at
/// the end, because a list that runs out and shows nothing is worse than one
/// that comes back round.
abstract final class NewIdeaRotation {
  static const String _key = 'newIdeas.batchCursor';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The value written this session, readable back immediately.
  ///
  /// The write itself goes through [persistHomeSetting], which runs on the root
  /// zone — and it has to, because this one is written from a widget's
  /// `initState`. A `Box.put` started inside a widget test's fake-async zone is
  /// never driven to completion, and it leaves `Hive.close()` hanging in
  /// `tearDownAll` for ever; every store in this app that writes during a build
  /// goes the same way round for the same reason. The price is that the value
  /// is not in the box the instant it is set, which this covers.
  static Object? _pending;

  static int get cursor {
    final Object? raw = _pending ?? _box?.get(_key);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  /// Records where the next visit should start. Kept small so the stored value
  /// never grows without bound on a device used for years.
  static void setCursor(int value) {
    final int next = value.abs() % 1000;
    _pending = next;
    persistHomeSetting(_key, next.toString());
  }
}
