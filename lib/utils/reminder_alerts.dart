import 'package:hive/hive.dart';

/// Which due reminders the matchmaker has already looked at.
///
/// A reminder that has come due raises an alert on the home screen. Opening the
/// card is the answer to that alert — the badge comes off, without touching the
/// reminder itself, which stays until it is really handled. The date is stored
/// alongside the id, so setting a *new* reminder arms a new alert.
///
/// Kept in the local Hive `settings` box as a plain id → millisecondsSinceEpoch
/// map, so no adapter or migration is needed.
abstract final class ReminderAlerts {
  static const String _keyPrefix = 'reminderSeen.';

  static Box<dynamic> get _box => Hive.box<dynamic>('settings');
  static bool get _isReady => Hive.isBoxOpen('settings');

  /// Whether [reminder] has come due and has not been looked at yet.
  static bool isAlerting(String targetId, DateTime? reminder) {
    if (reminder == null || !isDue(reminder)) {
      return false;
    }
    if (!_isReady) {
      return true;
    }
    final Object? seen = _box.get('$_keyPrefix$targetId');
    return seen is! int || seen != reminder.millisecondsSinceEpoch;
  }

  /// Records that the matchmaker opened the card while [reminder] was due.
  static Future<void> markSeen(String targetId, DateTime? reminder) async {
    if (!_isReady || reminder == null || !isDue(reminder)) {
      return;
    }
    await _box.put('$_keyPrefix$targetId', reminder.millisecondsSinceEpoch);
  }

  /// Drops the record for a deleted card, so its key does not linger.
  static Future<void> forget(String targetId) async {
    if (!_isReady) {
      return;
    }
    await _box.delete('$_keyPrefix$targetId');
  }

  /// A reminder is due from the start of its day, not from the exact moment.
  static bool isDue(DateTime? date, {DateTime? now}) {
    if (date == null) {
      return false;
    }
    final DateTime today = now ?? DateTime.now();
    return !DateTime(
      date.year,
      date.month,
      date.day,
    ).isAfter(DateTime(today.year, today.month, today.day));
  }
}
