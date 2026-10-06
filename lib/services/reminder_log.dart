import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// One reminder that came due, as the notifications page remembers it.
class ReminderLogEntry {
  const ReminderLogEntry({
    required this.kind,
    required this.targetId,
    required this.dueAt,
    required this.note,
    this.read = false,
    this.removed = false,
  });

  /// A friend or an idea.
  final HomeItemKind kind;
  final String targetId;

  /// When it came due — the reminder's own date, at the hour reminders fire.
  final DateTime dueAt;

  /// What the matchmaker wrote on the reminder, or empty for none.
  final String note;
  final bool read;

  /// Taken off the notifications page. Kept as a tombstone, so the same
  /// reminder is not logged a second time on the next look.
  final bool removed;

  /// One reminder date of one record: a reminder set again for another day is
  /// a new notification.
  String get key => '${kind.name}:$targetId:${dueAt.millisecondsSinceEpoch}';

  ReminderLogEntry copyWith({bool? read, bool? removed}) => ReminderLogEntry(
    kind: kind,
    targetId: targetId,
    dueAt: dueAt,
    note: note,
    read: read ?? this.read,
    removed: removed ?? this.removed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'k': kind.name,
    't': targetId,
    'd': dueAt.millisecondsSinceEpoch,
    'n': note,
    if (read) 'r': true,
    if (removed) 'x': true,
  };

  static ReminderLogEntry? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final HomeItemKind? kind = HomeItemKind.byName(raw['k'] as String?);
    final Object? target = raw['t'];
    final Object? due = raw['d'];
    if (kind == null || target is! String || due is! int) {
      return null;
    }
    return ReminderLogEntry(
      kind: kind,
      targetId: target,
      dueAt: DateTime.fromMillisecondsSinceEpoch(due),
      note: (raw['n'] as String?) ?? '',
      read: raw['r'] == true,
      removed: raw['x'] == true,
    );
  }
}

/// A reminder about to be logged: whatever record carries a due date now.
class DueReminder {
  const DueReminder({
    required this.kind,
    required this.targetId,
    required this.date,
    this.note,
  });

  final HomeItemKind kind;
  final String targetId;
  final DateTime date;
  final String? note;
}

/// The history of reminders that came due — the reminder half of the
/// notifications page.
///
/// **A reminder is a date on a record, and a notification is an event.** The
/// record only ever knows its *next* reminder, so once a reminder is handled or
/// set for another day, the one that came due would vanish from the page with
/// it. This log keeps it: [sync] writes an entry the first time a reminder is
/// seen to be due, and the entry stays — read or not — until the matchmaker
/// removes it. Nothing is deleted by age.
///
/// The reminders themselves are untouched: setting, moving and clearing them
/// is exactly what it was.
class ReminderLog extends ChangeNotifier {
  ReminderLog._();

  static final ReminderLog instance = ReminderLog._();

  static const String _key = 'notifications.reminderLog';

  /// The hour a reminder picked as a bare date actually fires.
  static const int reminderHour = 9;

  /// Tombstones beyond this many are dropped, oldest first — enough that a
  /// removed reminder never comes back while its date is still on the record.
  static const int _maxEntries = 400;

  List<ReminderLogEntry>? _cache;

  List<ReminderLogEntry> get _entries => _cache ??= _read();

  List<ReminderLogEntry> _read() {
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(_key)
        : null;
    if (raw is! String || raw.isEmpty) {
      return <ReminderLogEntry>[];
    }
    try {
      final Object? list = jsonDecode(raw);
      if (list is! List) {
        return <ReminderLogEntry>[];
      }
      return <ReminderLogEntry>[
        for (final Object? item in list)
          if (ReminderLogEntry.fromJson(item) case final ReminderLogEntry e) e,
      ];
    } catch (_) {
      return <ReminderLogEntry>[];
    }
  }

  void _write() {
    final List<ReminderLogEntry> entries = _entries;
    if (entries.length > _maxEntries) {
      entries
        ..sort(
          (ReminderLogEntry a, ReminderLogEntry b) =>
              b.dueAt.compareTo(a.dueAt),
        )
        ..removeRange(_maxEntries, entries.length);
    }
    persistHomeSetting(
      _key,
      jsonEncode(<Map<String, Object?>>[
        for (final ReminderLogEntry e in entries) e.toJson(),
      ]),
    );
  }

  /// The moment [date] counts as due: a bare date fires at [reminderHour].
  static DateTime dueMoment(DateTime date) => date.hour == 0 && date.minute == 0
      ? DateTime(date.year, date.month, date.day, reminderHour)
      : date;

  /// Logs every reminder in [due] not seen before. Safe to call from a build:
  /// it writes, but never notifies — what it adds is unread, and whoever
  /// called it is about to count it.
  void sync(Iterable<DueReminder> due) {
    final Set<String> known = <String>{
      for (final ReminderLogEntry e in _entries) e.key,
    };
    bool changed = false;
    for (final DueReminder reminder in due) {
      final ReminderLogEntry entry = ReminderLogEntry(
        kind: reminder.kind,
        targetId: reminder.targetId,
        dueAt: dueMoment(reminder.date),
        note: (reminder.note ?? '').trim(),
      );
      if (known.add(entry.key)) {
        _entries.add(entry);
        changed = true;
      }
    }
    if (changed) {
      _write();
    }
  }

  /// Every entry still on the page, newest first.
  List<ReminderLogEntry> get visible =>
      _entries.where((ReminderLogEntry e) => !e.removed).toList()..sort(
        (ReminderLogEntry a, ReminderLogEntry b) => b.dueAt.compareTo(a.dueAt),
      );

  ReminderLogEntry? byKey(String key) {
    for (final ReminderLogEntry e in _entries) {
      if (e.key == key) {
        return e;
      }
    }
    return null;
  }

  void _replace(
    bool Function(ReminderLogEntry e) where,
    ReminderLogEntry Function(ReminderLogEntry e) change,
  ) {
    final List<ReminderLogEntry> entries = _entries;
    bool changed = false;
    for (int i = 0; i < entries.length; i++) {
      if (where(entries[i])) {
        final ReminderLogEntry next = change(entries[i]);
        if (next.read != entries[i].read ||
            next.removed != entries[i].removed) {
          entries[i] = next;
          changed = true;
        }
      }
    }
    if (changed) {
      _write();
      notifyListeners();
    }
  }

  void markRead(Iterable<String> keys) {
    final Set<String> wanted = keys.toSet();
    _replace(
      (ReminderLogEntry e) => wanted.contains(e.key),
      (ReminderLogEntry e) => e.copyWith(read: true),
    );
  }

  void markAllRead() => _replace(
    (ReminderLogEntry e) => !e.read,
    (ReminderLogEntry e) => e.copyWith(read: true),
  );

  void remove(Iterable<String> keys) {
    final Set<String> wanted = keys.toSet();
    _replace(
      (ReminderLogEntry e) => wanted.contains(e.key),
      (ReminderLogEntry e) => e.copyWith(removed: true, read: true),
    );
  }

  /// Puts removed entries back — the undo of [remove].
  void restore(Iterable<String> keys) {
    final Set<String> wanted = keys.toSet();
    _replace(
      (ReminderLogEntry e) => wanted.contains(e.key),
      (ReminderLogEntry e) => e.copyWith(removed: false),
    );
  }

  /// Whether the reminder of [kind]/[targetId] due on [date] was read on the
  /// notifications page — what takes it off "הלוח שלי".
  bool isRead(HomeItemKind kind, String targetId, DateTime date) {
    final ReminderLogEntry? entry = byKey(
      '${kind.name}:$targetId:${dueMoment(date).millisecondsSinceEpoch}',
    );
    return entry != null && entry.read;
  }

  /// Marks the reminder of [kind]/[targetId] due on [date] read — opened from
  /// "הלוח שלי". Logs it first when the page has not seen it yet.
  void markReadFor(
    HomeItemKind kind,
    String targetId,
    DateTime date, {
    String? note,
  }) {
    final String key =
        '${kind.name}:$targetId:${dueMoment(date).millisecondsSinceEpoch}';
    if (byKey(key) == null) {
      sync(<DueReminder>[
        DueReminder(kind: kind, targetId: targetId, date: date, note: note),
      ]);
    }
    markRead(<String>[key]);
  }

  /// Something else the notifications page draws changed locally — redraw.
  void touch() => notifyListeners();

  /// On sign-out, with the rest of the local data.
  void reset() {
    _cache = <ReminderLogEntry>[];
    persistHomeSetting(_key, '');
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() => _cache = null;
}
