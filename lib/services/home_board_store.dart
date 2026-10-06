import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

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

  /// Notes on items that are on the board without being pinned — a due
  /// reminder, an open proposal. Kept apart from the pinned entries so a note
  /// never pins anything by itself, and moved across when an item is pinned or
  /// unpinned so it is never lost on the way.
  static const String _notesKey = 'home.boardNotes';

  /// Rows taken off the board with "הסרה", and when. A removed row stays off
  /// until whatever put it there changes — a new reminder date, a proposal
  /// that moved — or it is pinned again. See [hiddenAt].
  static const String _hiddenKey = 'home.boardHidden';

  List<HomeBoardEntry>? _cache;
  Map<String, String>? _notesCache;
  Map<String, int>? _hiddenCache;
  bool _focusPending = false;

  /// The board changed on another phone; read it again.
  void forgetCache() {
    _cache = null;
    _notesCache = null;
    _hiddenCache = null;
    notifyListeners();
  }

  /// Brings the already-mounted home tab to the board after an item is pinned.
  void requestFocus() {
    _focusPending = true;
    notifyListeners();
  }

  /// Consumes a focus request exactly once. It remains pending while the home
  /// branch is being recreated, so navigation cannot lose the request.
  bool takeFocusRequest() {
    if (!_focusPending) {
      return false;
    }
    _focusPending = false;
    return true;
  }

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
    final String key = _noteKey(kind, targetId);
    if (_hidden.containsKey(key)) {
      _writeHidden(Map<String, int>.of(_hidden)..remove(key));
    }
    final String? loose = _notes[key];
    if (loose != null) {
      _writeNotes(Map<String, String>.of(_notes)..remove(key));
    }
    _write(<HomeBoardEntry>[
      HomeBoardEntry(
        kind: kind,
        targetId: targetId,
        addedAt: DateTime.now(),
        note: loose,
      ),
      ...entries,
    ]);
  }

  void remove(HomeItemKind kind, String targetId) {
    final HomeBoardEntry? entry = entryFor(kind, targetId);
    if (entry == null) {
      return;
    }
    // Unpinning is not deleting what was written on it.
    final String? note = entry.note;
    if ((note ?? '').isNotEmpty) {
      _writeNotes(<String, String>{..._notes, _noteKey(kind, targetId): note!});
    }
    _write(
      entries
          .where(
            (HomeBoardEntry e) => !(e.kind == kind && e.targetId == targetId),
          )
          .toList(),
    );
  }

  /// The note on an item, pinned or not.
  String? noteFor(HomeItemKind kind, String targetId) {
    return entryFor(kind, targetId)?.note ?? _notes[_noteKey(kind, targetId)];
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
    final String? trimmed = (note ?? '').trim().isEmpty ? null : note!.trim();
    if (index < 0) {
      final Map<String, String> notes = Map<String, String>.of(_notes);
      final String key = _noteKey(kind, targetId);
      if (trimmed == null) {
        notes.remove(key);
      } else {
        notes[key] = trimmed;
      }
      _writeNotes(notes);
      notifyListeners();
      return;
    }
    final List<HomeBoardEntry> next = List<HomeBoardEntry>.from(current);
    next[index] = current[index].copyWith(note: trimmed);
    _write(next);
  }

  /// Drops a deleted person / proposal off the board, note and all.
  void forget(HomeItemKind kind, String targetId) {
    remove(kind, targetId);
    final String key = _noteKey(kind, targetId);
    if (_notes.containsKey(key)) {
      _writeNotes(Map<String, String>.of(_notes)..remove(key));
    }
    if (_hidden.containsKey(key)) {
      _writeHidden(Map<String, int>.of(_hidden)..remove(key));
    }
  }

  /// The key a row is hidden under: `person:<id>`, `idea:<id>`, or for a pair
  /// the app suggests, [pairKey].
  static String itemKey(HomeItemKind kind, String targetId) =>
      _noteKey(kind, targetId);

  static String pairKey(String maleId, String femaleId) =>
      'pair:$maleId|$femaleId';

  /// Takes a row off the board ("הסרה"). A pinned row is unpinned too.
  void hide(String key) {
    _writeHidden(<String, int>{
      ..._hidden,
      key: DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  /// Puts a removed row back — the undo of [hide].
  void unhide(String key) {
    if (!_hidden.containsKey(key)) {
      return;
    }
    _writeHidden(Map<String, int>.of(_hidden)..remove(key));
    notifyListeners();
  }

  /// When the row under [key] was removed, or null if it never was.
  DateTime? hiddenAt(String key) {
    final int? at = _hidden[key];
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  static String _noteKey(HomeItemKind kind, String targetId) =>
      '${kind.name}:$targetId';

  Map<String, int> get _hidden => _hiddenCache ??= _readHidden();

  Map<String, int> _readHidden() {
    final Object? stored = _box?.get(_hiddenKey);
    if (stored is! String || stored.isEmpty) {
      return <String, int>{};
    }
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! Map) {
        return <String, int>{};
      }
      return <String, int>{
        for (final MapEntry<dynamic, dynamic> e in decoded.entries)
          if (e.key is String && e.value is int)
            e.key as String: e.value as int,
      };
    } catch (_) {
      return <String, int>{};
    }
  }

  void _writeHidden(Map<String, int> hidden) {
    _hiddenCache = hidden;
    persistHomeSetting(_hiddenKey, jsonEncode(hidden));
  }

  Map<String, String> get _notes => _notesCache ??= _readNotes();

  Map<String, String> _readNotes() {
    final Object? stored = _box?.get(_notesKey);
    if (stored is! String || stored.isEmpty) {
      return <String, String>{};
    }
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! Map) {
        return <String, String>{};
      }
      return <String, String>{
        for (final MapEntry<dynamic, dynamic> e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  void _writeNotes(Map<String, String> notes) {
    _notesCache = notes;
    persistHomeSetting(_notesKey, jsonEncode(notes));
  }

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

  /// Empties the board and forgets it on disk.
  ///
  /// Only for signing out: the board points at people and proposals that are
  /// about to stop existing on this device, and a board of dangling ids is
  /// worse than an empty one.
  void reset() {
    _writeHidden(const <String, int>{});
    _writeNotes(const <String, String>{});
    _write(const <HomeBoardEntry>[]);
  }

  void _write(List<HomeBoardEntry> entries) {
    _cache = entries;
    notifyListeners();
    persistHomeSetting(
      _key,
      jsonEncode(<Map<String, Object?>>[
        for (final HomeBoardEntry entry in entries) entry.toJson(),
      ]),
    );
  }
}
