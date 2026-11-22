import 'package:hive/hive.dart';

import 'home_board_store.dart';

/// When this phone last asked the server for something it does not need to
/// ask about every few minutes — and so whether it may ask again now.
///
/// **Why (2026-11-22).** Firestore is billed per document read and written.
/// Several things the app did on *every* open, resume and exit — publishing
/// "last active" (which woke the most expensive trigger on the server),
/// re-reading every community tip — cost far more than what they gave. Each
/// now goes through one of these clocks.
///
/// Device-only: the keys start with [prefix], which
/// `AccountSyncCodec.isSyncedSetting` keeps off the account — another phone's
/// clock says nothing about this one. Kept in memory too, so a value written
/// this frame is read back this frame (the Hive write is deferred to the root
/// zone, like every other `persistHomeSetting`).
abstract final class ReadThrottle {
  static const String prefix = 'serverReads.';

  static final Map<String, String> _pending = <String, String>{};

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static String? _read(String name) {
    final String key = '$prefix$name';
    final String? pending = _pending[key];
    if (pending != null) return pending;
    try {
      final Object? stored = _box?.get(key);
      return stored is String ? stored : null;
    } catch (_) {
      return null;
    }
  }

  static void _write(String name, String value) {
    final String key = '$prefix$name';
    _pending[key] = value;
    persistHomeSetting(key, value);
  }

  /// When [name] was last marked, or null when never (or unreadable).
  static DateTime? lastAt(String name) =>
      DateTime.tryParse(_read('$name.at') ?? '');

  /// A small value stored beside the clock (e.g. the count last published).
  static String? value(String name) => _read('$name.value');

  /// Whether [every] has passed since [name] was last marked. A clock in the
  /// future (the phone's time was changed) counts as due, so nothing can be
  /// stuck behind it.
  static bool due(String name, Duration every, {DateTime? now}) {
    final DateTime? last = lastAt(name);
    final DateTime at = now ?? DateTime.now();
    return isDue(last: last, every: every, now: at);
  }

  /// [due], without the storage — for tests and for callers that hold the
  /// time themselves.
  static bool isDue({
    required DateTime? last,
    required Duration every,
    required DateTime now,
  }) {
    if (last == null || last.isAfter(now)) return true;
    return now.difference(last) >= every;
  }

  /// Records that [name] was done now (and, optionally, with what value).
  static void mark(String name, {DateTime? at, String? value}) {
    _write('$name.at', (at ?? DateTime.now()).toIso8601String());
    if (value != null) _write('$name.value', value);
  }

  /// Forgets every clock (sign-out: the next account starts fresh).
  static void reset() {
    _pending.clear();
    final Box<dynamic>? box = _box;
    if (box == null) return;
    for (final Object? key in box.keys.toList()) {
      if (key is String && key.startsWith(prefix)) {
        _pending[key] = '';
        persistHomeSetting(key, '');
      }
    }
  }
}
