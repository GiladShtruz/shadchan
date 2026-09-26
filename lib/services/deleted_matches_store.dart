import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// One deleted idea, exactly as it stood the moment before it went: the
/// record, every journal line and its status ledger, as the backup codecs
/// write them.
class DeletedMatch {
  const DeletedMatch({
    required this.matchId,
    required this.deletedAt,
    required this.match,
    required this.notes,
    required this.events,
  });

  final String matchId;
  final DateTime deletedAt;

  /// `BackupService.matchToJson`, plus the three fields that codec does not
  /// carry (`askedMaleAt`, `askedFemaleAt`, `checkInEveryDays`) so a restored
  /// idea comes back at the stage it was at.
  final Map<String, dynamic> match;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> events;

  String get personAId => (match['personAId'] as String?) ?? '';
  String get personBId => (match['personBId'] as String?) ?? '';

  Map<String, Object?> toJson() => <String, Object?>{
    'matchId': matchId,
    'deletedAt': deletedAt.toIso8601String(),
    'match': match,
    'notes': notes,
    'events': events,
  };

  static DeletedMatch? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
    final String? id = json['matchId'] as String?;
    final DateTime? at = DateTime.tryParse(json['deletedAt'] as String? ?? '');
    final Object? match = json['match'];
    if (id == null || at == null || match is! Map) {
      return null;
    }
    List<Map<String, dynamic>> listOf(Object? value) {
      if (value is! List) {
        return <Map<String, dynamic>>[];
      }
      return <Map<String, dynamic>>[
        for (final Object? item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }

    return DeletedMatch(
      matchId: id,
      deletedAt: at,
      match: Map<String, dynamic>.from(match),
      notes: listOf(json['notes']),
      events: listOf(json['events']),
    );
  }
}

/// "רעיונות שנמחקו" — where a deleted idea waits before it is gone for good.
///
/// **Deleting an idea took its whole journal with it, with one confirmation
/// in the way.** That is the right weight for a record nobody wants, and far
/// too much for a long press that landed on the wrong card. So a delete now
/// files a snapshot here first; the undo banner and the "רעיונות שנמחקו" page
/// both put it back, and anything older than [retention] is dropped the next
/// time the list is read.
///
/// A device-local list in the settings box, deliberately outside the cloud
/// backup: it is a safety net for this phone's recent mistakes, not data.
class DeletedMatchesStore extends ChangeNotifier {
  DeletedMatchesStore._();

  static final DeletedMatchesStore instance = DeletedMatchesStore._();

  static const String _key = 'trash.matches';

  /// How long a deleted idea can still be brought back.
  static const Duration retention = Duration(days: 30);

  List<DeletedMatch>? _items;

  List<DeletedMatch> _load() {
    final List<DeletedMatch>? cached = _items;
    if (cached != null) {
      return cached;
    }
    final List<DeletedMatch> loaded = <DeletedMatch>[];
    if (Hive.isBoxOpen('settings')) {
      final Object? raw = Hive.box<dynamic>('settings').get(_key);
      if (raw is String && raw.isNotEmpty) {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final Object? item in decoded) {
              final DeletedMatch? entry = DeletedMatch.fromJson(item);
              if (entry != null) {
                loaded.add(entry);
              }
            }
          }
        } catch (error) {
          debugPrint('DeletedMatchesStore: unreadable trash: $error');
        }
      }
    }
    return _items = loaded;
  }

  /// Every idea that can still be restored, most recently deleted first.
  List<DeletedMatch> get all {
    final DateTime cutoff = DateTime.now().subtract(retention);
    final List<DeletedMatch> items = _load();
    final int before = items.length;
    items.removeWhere((DeletedMatch e) => e.deletedAt.isBefore(cutoff));
    if (items.length != before) {
      _persist();
    }
    final List<DeletedMatch> sorted = List<DeletedMatch>.of(items)
      ..sort(
        (DeletedMatch a, DeletedMatch b) => b.deletedAt.compareTo(a.deletedAt),
      );
    return sorted;
  }

  bool get isEmpty => all.isEmpty;

  void add(DeletedMatch entry) {
    final List<DeletedMatch> items = _load()
      ..removeWhere((DeletedMatch e) => e.matchId == entry.matchId)
      ..add(entry);
    _items = items;
    _persist();
    notifyListeners();
  }

  /// Takes one entry out of the trash and hands it back, or null.
  DeletedMatch? take(String matchId) {
    final List<DeletedMatch> items = _load();
    final int index = items.indexWhere(
      (DeletedMatch e) => e.matchId == matchId,
    );
    if (index < 0) {
      return null;
    }
    final DeletedMatch entry = items.removeAt(index);
    _persist();
    notifyListeners();
    return entry;
  }

  /// Gone for good.
  void purge(String matchId) {
    take(matchId);
  }

  /// Everything, for sign-out.
  void clear() {
    _items = <DeletedMatch>[];
    _persist();
    notifyListeners();
  }

  void _persist() {
    persistHomeSetting(
      _key,
      jsonEncode(<Object?>[for (final DeletedMatch e in _load()) e.toJson()]),
    );
  }

  @visibleForTesting
  void resetForTest() {
    _items = null;
  }
}
