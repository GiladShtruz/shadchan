/// Decides which reminder notifications are actually handed to the operating
/// system. Pure, so the rules are tested rather than hoped for.
///
/// Two problems with scheduling every reminder as its own notification:
///
/// * **A wall of notifications.** Ideas opened together (an import, a busy
///   evening) get their monthly reminder on the same day, and the phone then
///   rings once per idea at 09:00. One line — "יש לך 12 רעיונות שכדאי לחזור
///   אליהם" — says the same thing. All of them are still on the notifications
///   page; only the push is shared.
/// * **iOS keeps the 64 soonest pending notifications and silently drops the
///   rest.** The list used to be scheduled in whatever order it arrived, so
///   which reminders survived was arbitrary. They are now sorted by time and
///   capped, so the ones dropped are always the furthest away — and every
///   launch schedules again, so those come in as the near ones fire.
class ReminderSchedulePlan<T> {
  const ReminderSchedulePlan({required this.single, required this.bundles});

  /// Reminders that keep their own notification, soonest first.
  final List<PlannedReminder<T>> single;

  /// Days on which too many reminders fell: one summary notification each.
  final List<ReminderBundle<T>> bundles;

  int get notificationCount => single.length + bundles.length;

  /// More than this many reminders on one calendar day are announced as one.
  static const int bundleAbove = 3;

  static ReminderSchedulePlan<T> build<T>(
    Iterable<PlannedReminder<T>> reminders, {
    required int maxNotifications,
    int bundleAbove = ReminderSchedulePlan.bundleAbove,
  }) {
    final Map<DateTime, List<PlannedReminder<T>>> byDay =
        <DateTime, List<PlannedReminder<T>>>{};
    for (final PlannedReminder<T> reminder in reminders) {
      final DateTime day = DateTime(
        reminder.at.year,
        reminder.at.month,
        reminder.at.day,
      );
      (byDay[day] ??= <PlannedReminder<T>>[]).add(reminder);
    }

    // One entry per notification, ordered by when it rings.
    final List<_Entry<T>> entries = <_Entry<T>>[];
    for (final MapEntry<DateTime, List<PlannedReminder<T>>> day
        in byDay.entries) {
      final List<PlannedReminder<T>> items = day.value
        ..sort(
          (PlannedReminder<T> a, PlannedReminder<T> b) => a.at.compareTo(b.at),
        );
      if (items.length > bundleAbove) {
        entries.add(
          _Entry<T>.bundle(ReminderBundle<T>(at: items.first.at, items: items)),
        );
      } else {
        for (final PlannedReminder<T> item in items) {
          entries.add(_Entry<T>.single(item));
        }
      }
    }
    entries.sort((_Entry<T> a, _Entry<T> b) => a.at.compareTo(b.at));

    final List<PlannedReminder<T>> single = <PlannedReminder<T>>[];
    final List<ReminderBundle<T>> bundles = <ReminderBundle<T>>[];
    for (final _Entry<T> entry in entries.take(
      maxNotifications < 0 ? 0 : maxNotifications,
    )) {
      if (entry.bundle != null) {
        bundles.add(entry.bundle!);
      } else {
        single.add(entry.single!);
      }
    }
    return ReminderSchedulePlan<T>(single: single, bundles: bundles);
  }
}

class PlannedReminder<T> {
  const PlannedReminder({required this.at, required this.item});

  final DateTime at;
  final T item;
}

class ReminderBundle<T> {
  const ReminderBundle({required this.at, required this.items});

  /// The earliest time on that day: the summary rings when the first of
  /// them would have.
  final DateTime at;
  final List<PlannedReminder<T>> items;

  int get count => items.length;
}

class _Entry<T> {
  _Entry.single(PlannedReminder<T> this.single) : bundle = null;
  _Entry.bundle(ReminderBundle<T> this.bundle) : single = null;

  final PlannedReminder<T>? single;
  final ReminderBundle<T>? bundle;

  DateTime get at => single?.at ?? bundle!.at;
}
