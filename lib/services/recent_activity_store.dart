import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/home_config.dart';

/// What the matchmaker last did with a person or a proposal. Opening a
/// WhatsApp chat is deliberately absent: it happens constantly and would drown
/// out the real work.
enum HomeActivityAction {
  openedPerson,
  openedIdea,
  createdIdea,
  editedDetails,
  addedNote,
  changedStatus;

  static HomeActivityAction? byName(String? name) {
    for (final HomeActivityAction action in HomeActivityAction.values) {
      if (action.name == name) {
        return action;
      }
    }
    return null;
  }

  String get label {
    switch (this) {
      case HomeActivityAction.openedPerson:
        return 'צפית בכרטיס';
      case HomeActivityAction.openedIdea:
        return 'פתחת רעיון';
      case HomeActivityAction.createdIdea:
        return 'רעיון חדש';
      case HomeActivityAction.editedDetails:
        return 'ערכת פרטים';
      case HomeActivityAction.addedNote:
        return 'הוספת הערה';
      case HomeActivityAction.changedStatus:
        return 'עדכנת סטטוס';
    }
  }
}

class HomeActivityEntry {
  const HomeActivityEntry({
    required this.kind,
    required this.targetId,
    required this.action,
    required this.at,
  });

  final HomeItemKind kind;
  final String targetId;
  final HomeActivityAction action;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'id': targetId,
    'action': action.name,
    'at': at.millisecondsSinceEpoch,
  };

  static HomeActivityEntry? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final HomeItemKind? kind = HomeItemKind.byName(raw['kind'] as String?);
    final HomeActivityAction? action = HomeActivityAction.byName(
      raw['action'] as String?,
    );
    final Object? id = raw['id'];
    final Object? at = raw['at'];
    if (kind == null || action == null || id is! String || at is! int) {
      return null;
    }
    return HomeActivityEntry(
      kind: kind,
      targetId: id,
      action: action,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// "הפעולות האחרונות שלך" — the trail of what the matchmaker just worked on,
/// so getting back to it is one tap instead of a search.
///
/// One entry per person / proposal: touching the same card again refreshes it
/// and floats it back to the front rather than piling up duplicates. Recording
/// is automatic — every call site is a place the app already knew something
/// happened, so the matchmaker is never asked to log anything.
///
/// A singleton for the same reason as [HomeBoardStore]: the repositories record
/// into it, and passing it through their constructors would buy nothing.
class RecentActivityStore extends ChangeNotifier {
  RecentActivityStore._();

  static final RecentActivityStore instance = RecentActivityStore._();

  static const String _key = 'home.recentActivity';

  List<HomeActivityEntry>? _cache;

  Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Newest first.
  List<HomeActivityEntry> get entries => _cache ??= _read();

  void record({
    required HomeItemKind kind,
    required String targetId,
    required HomeActivityAction action,
  }) {
    if (targetId.isEmpty) {
      return;
    }

    final List<HomeActivityEntry> current = entries;
    final DateTime now = DateTime.now();

    // Re-opening a card the user is already sitting on would rewrite the entry
    // on every rebuild; nothing changes visually, so skip the write.
    if (current.isNotEmpty) {
      final HomeActivityEntry head = current.first;
      if (head.kind == kind &&
          head.targetId == targetId &&
          head.action == action &&
          now.difference(head.at).inSeconds < 5) {
        return;
      }
    }

    final List<HomeActivityEntry> next = <HomeActivityEntry>[
      HomeActivityEntry(
        kind: kind,
        targetId: targetId,
        action: action,
        at: now,
      ),
      for (final HomeActivityEntry entry in current)
        if (!(entry.kind == kind && entry.targetId == targetId)) entry,
    ];
    _write(next);
  }

  /// Drops a deleted person / proposal off the strip.
  void forget(HomeItemKind kind, String targetId) {
    final List<HomeActivityEntry> next = entries
        .where(
          (HomeActivityEntry e) => !(e.kind == kind && e.targetId == targetId),
        )
        .toList();
    if (next.length == entries.length) {
      return;
    }
    _write(next);
  }

  List<HomeActivityEntry> _read() {
    final Object? stored = _box?.get(_key);
    if (stored is! String || stored.isEmpty) {
      return <HomeActivityEntry>[];
    }
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! List) {
        return <HomeActivityEntry>[];
      }
      return <HomeActivityEntry>[
        for (final Object? raw in decoded)
          if (HomeActivityEntry.fromJson(raw) case final HomeActivityEntry e) e,
      ];
    } catch (_) {
      return <HomeActivityEntry>[];
    }
  }

  void _write(List<HomeActivityEntry> entries) {
    final List<HomeActivityEntry> capped =
        entries.length > HomeConfig.recentActivityMaxItems
        ? entries.sublist(0, HomeConfig.recentActivityMaxItems)
        : entries;
    _cache = capped;
    notifyListeners();
    persistHomeSetting(
      _key,
      jsonEncode(<Map<String, Object?>>[
        for (final HomeActivityEntry entry in capped) entry.toJson(),
      ]),
    );
  }
}
