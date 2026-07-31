import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/home_config.dart';

/// Stores one of the home screen's settings as plain background I/O.
///
/// Deliberately pinned to the root zone. These writes are triggered from widget
/// lifecycle callbacks — opening a card records it — and a Future created
/// inside a widget test's fake-async zone is never driven to completion once
/// the test body ends, which leaves Hive holding a write it can never finish
/// and a `close()` that never returns. Persistence has nothing to do with
/// whichever zone happened to trigger it, so it runs on its own.
void persistHomeSetting(String key, String value) {
  Zone.root.scheduleMicrotask(() async {
    if (!Hive.isBoxOpen('settings')) {
      return;
    }
    try {
      await Hive.box<dynamic>('settings').put(key, value);
    } catch (error, stackTrace) {
      debugPrint('persistHomeSetting($key) failed: $error\n$stackTrace');
    }
  });
}

/// What a board or activity entry points at.
enum HomeItemKind {
  person,
  idea;

  static HomeItemKind? byName(String? name) {
    for (final HomeItemKind kind in HomeItemKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return null;
  }
}

/// One thing the matchmaker pinned to "הלוח שלי".
///
/// Deliberately holds no reminder date of its own: reminders already live on
/// the person (`PersonReminders`) and on the proposal (`MatchIdea.reminderDate`),
/// where they also drive the push notifications and the reminders panel. The
/// board reads them from there rather than keeping a second, silent copy.
class HomeBoardEntry {
  const HomeBoardEntry({
    required this.kind,
    required this.targetId,
    required this.addedAt,
    this.note,
  });

  final HomeItemKind kind;
  final String targetId;
  final DateTime addedAt;
  final String? note;

  HomeBoardEntry copyWith({Object? note = _sentinel}) {
    return HomeBoardEntry(
      kind: kind,
      targetId: targetId,
      addedAt: addedAt,
      note: identical(note, _sentinel) ? this.note : note as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'id': targetId,
    'at': addedAt.millisecondsSinceEpoch,
    if ((note ?? '').isNotEmpty) 'note': note,
  };

  static HomeBoardEntry? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final HomeItemKind? kind = HomeItemKind.byName(raw['kind'] as String?);
    final Object? id = raw['id'];
    final Object? at = raw['at'];
    if (kind == null || id is! String || id.isEmpty || at is! int) {
      return null;
    }
    final Object? note = raw['note'];
    return HomeBoardEntry(
      kind: kind,
      targetId: id,
      addedAt: DateTime.fromMillisecondsSinceEpoch(at),
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }

  static const Object _sentinel = Object();
}

/// "הלוח שלי" — the people and proposals the matchmaker parked on the home
/// screen to come back to.
///
/// A singleton rather than an injected repository: proposals and people are
/// pinned from several screens and removed from inside the repositories when a
/// record is deleted, and threading one more dependency through all of those
/// would buy nothing. It is still a [ChangeNotifier], so the home screen is
/// registered as a listener and updates the moment something is pinned.
class HomeBoardStore extends ChangeNotifier {
  HomeBoardStore._();

  static final HomeBoardStore instance = HomeBoardStore._();

  static const String _key = 'home.board';

  List<HomeBoardEntry>? _cache;

  Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Newest addition first.
  List<HomeBoardEntry> get entries {
    return _cache ??= _read();
  }

  bool get isEmpty => entries.isEmpty;

  bool contains(HomeItemKind kind, String targetId) {
    return _indexOf(entries, kind, targetId) >= 0;
  }

  HomeBoardEntry? entryFor(HomeItemKind kind, String targetId) {
    final List<HomeBoardEntry> current = entries;
    final int index = _indexOf(current, kind, targetId);
    return index < 0 ? null : current[index];
  }

  void add(HomeItemKind kind, String targetId) {
    if (contains(kind, targetId)) {
      return;
    }
    _write(<HomeBoardEntry>[
      HomeBoardEntry(kind: kind, targetId: targetId, addedAt: DateTime.now()),
      ...entries,
    ]);
  }

  void remove(HomeItemKind kind, String targetId) {
    final List<HomeBoardEntry> next = entries
        .where(
          (HomeBoardEntry e) => !(e.kind == kind && e.targetId == targetId),
        )
        .toList();
    if (next.length == entries.length) {
      return;
    }
    _write(next);
  }

  /// Adds when missing, removes when already there. Returns whether the item is
  /// on the board afterwards, so the caller can word its confirmation.
  bool toggle(HomeItemKind kind, String targetId) {
    final bool wasPinned = contains(kind, targetId);
    if (wasPinned) {
      remove(kind, targetId);
    } else {
      add(kind, targetId);
    }
    return !wasPinned;
  }

  /// Sets (or clears, with a null/empty [note]) the short note on a card.
  void setNote(HomeItemKind kind, String targetId, String? note) {
    final List<HomeBoardEntry> current = entries;
    final int index = _indexOf(current, kind, targetId);
    if (index < 0) {
      return;
    }
    final String? trimmed = (note ?? '').trim().isEmpty ? null : note!.trim();
    final List<HomeBoardEntry> next = List<HomeBoardEntry>.from(current);
    next[index] = current[index].copyWith(note: trimmed);
    _write(next);
  }

  /// Drops a deleted person / proposal off the board.
  void forget(HomeItemKind kind, String targetId) => remove(kind, targetId);

  int _indexOf(List<HomeBoardEntry> list, HomeItemKind kind, String targetId) {
    for (int i = 0; i < list.length; i++) {
      if (list[i].kind == kind && list[i].targetId == targetId) {
        return i;
      }
    }
    return -1;
  }

  List<HomeBoardEntry> _read() {
    final Object? stored = _box?.get(_key);
    if (stored is! String || stored.isEmpty) {
      return <HomeBoardEntry>[];
    }
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! List) {
        return <HomeBoardEntry>[];
      }
      return <HomeBoardEntry>[
        for (final Object? raw in decoded)
          if (HomeBoardEntry.fromJson(raw) case final HomeBoardEntry entry)
            entry,
      ];
    } catch (_) {
      // Unreadable storage is treated as an empty board rather than a crash.
      return <HomeBoardEntry>[];
    }
  }

  void _write(List<HomeBoardEntry> entries) {
    final List<HomeBoardEntry> capped =
        entries.length > HomeConfig.boardMaxItems
        ? entries.sublist(0, HomeConfig.boardMaxItems)
        : entries;
    _cache = capped;
    notifyListeners();
    persistHomeSetting(
      _key,
      jsonEncode(<Map<String, Object?>>[
        for (final HomeBoardEntry entry in capped) entry.toJson(),
      ]),
    );
  }
}
