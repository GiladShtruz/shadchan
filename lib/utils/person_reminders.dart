import 'package:hive/hive.dart';

/// Per-person "check on them again" reminders, stored in the local Hive
/// `settings` box so they survive restarts.
///
/// These are set when a person is put on a break (בהפסקה) and the matchmaker
/// asks to be reminded to check in again later. They surface in the home
/// screen's reminders bell alongside proposal reminders. Storage is a simple
/// personId → millisecondsSinceEpoch map, so no Hive adapter/migration is
/// needed.
abstract final class PersonReminders {
  static const String _keyPrefix = 'personReminder.';
  static const String _notePrefix = 'personReminderNote.';

  static Box<dynamic> get _box => Hive.box<dynamic>('settings');
  static bool get _isReady => Hive.isBoxOpen('settings');

  /// The reminder date set for [personId], or null when none is set.
  static DateTime? forPerson(String personId) {
    if (!_isReady) return null;
    final Object? stored = _box.get('$_keyPrefix$personId');
    if (stored is int) {
      return DateTime.fromMillisecondsSinceEpoch(stored);
    }
    return null;
  }

  /// Every person id that currently has a reminder, mapped to its date.
  static Map<String, DateTime> all() {
    final Map<String, DateTime> result = <String, DateTime>{};
    if (!_isReady) return result;
    for (final dynamic key in _box.keys) {
      if (key is String && key.startsWith(_keyPrefix)) {
        final Object? value = _box.get(key);
        if (value is int) {
          result[key.substring(_keyPrefix.length)] =
              DateTime.fromMillisecondsSinceEpoch(value);
        }
      }
    }
    return result;
  }

  /// The matchmaker's own note on the reminder ("לבדוק אם חזרה מהפסקה"), or
  /// null when none was written. The note belongs to the person, so it shows
  /// wherever the reminder does.
  static String? noteFor(String personId) {
    if (!_isReady) return null;
    final Object? stored = _box.get('$_notePrefix$personId');
    if (stored is String && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return null;
  }

  static Future<void> set(
    String personId,
    DateTime date, {
    String? note,
  }) async {
    await _box.put('$_keyPrefix$personId', date.millisecondsSinceEpoch);
    final String text = (note ?? '').trim();
    if (text.isEmpty) {
      await _box.delete('$_notePrefix$personId');
    } else {
      await _box.put('$_notePrefix$personId', text);
    }
  }

  static Future<void> clear(String personId) async {
    if (!_isReady) return;
    await _box.delete('$_keyPrefix$personId');
    await _box.delete('$_notePrefix$personId');
  }
}
