import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// The last answers the server gave, kept on the device so that a phone with
/// no connection still has something true to show.
///
/// **Only for what the device cannot work out by itself.** The database —
/// people, ideas, notes, the matchmaker's own figures — is already a Hive copy
/// and needs nothing here. What lives here is the server's side of the story:
/// the community's totals and leaderboard (aggregate queries, which Firestore
/// cannot answer from its own offline cache) and which friends' personal cards
/// this account was last confirmed to be allowed to see.
///
/// **Its own box, deliberately outside `settings`.** Every `settings` key
/// travels with the account unless it is on a deny-list; this is a cache of
/// what the server said, it must never be sent back to it, and keeping it in a
/// box the sync does not watch makes that impossible to get wrong. Emptied on
/// sign-out with the rest of the account's copy (`AccountSwitch`).
///
/// Writes run in the root zone, like `persistHomeSetting`, so a write started
/// from a widget test's fake-async zone cannot leave Hive with a write it never
/// finishes. A value written this frame is readable this frame from [_pending].
abstract final class OfflineCache {
  static const String boxName = 'offline_cache';

  static const String _cardOwnersKey = 'cards.verifiedOwners';

  static final Map<String, String?> _pending = <String, String?>{};

  static bool get _ready => Hive.isBoxOpen(boxName);

  /// The JSON stored under [key], or null.
  static Map<String, Object?>? read(String key) {
    final String? raw = _pending.containsKey(key)
        ? _pending[key]
        : (_ready ? Hive.box<dynamic>(boxName).get(key) as String? : null);
    if (raw == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  /// Keeps [value] under [key], replacing what was there.
  static void write(String key, Map<String, Object?> value) {
    final String raw = jsonEncode(value);
    if (_pending[key] == raw) {
      return;
    }
    _pending[key] = raw;
    Zone.root.scheduleMicrotask(() async {
      if (!_ready) {
        return;
      }
      try {
        await Hive.box<dynamic>(boxName).put(key, raw);
      } on Object catch (error) {
        debugPrint('OfflineCache.write($key) failed: $error');
      }
    });
  }

  /// The friends whose personal cards this account was last confirmed, by the
  /// server, to be allowed to read — what an offline phone may go on showing.
  ///
  /// Read for every person in the database while offline, so the decoded set
  /// is kept in memory; a copy is handed out, so a caller cannot change it.
  static Set<String> get verifiedCardOwners =>
      Set<String>.of(_owners ??= _readOwners());

  static Set<String>? _owners;

  static Set<String> _readOwners() {
    final Object? list = read(_cardOwnersKey)?['owners'];
    return <String>{
      if (list is List)
        for (final Object? item in list)
          if (item is String && item.isNotEmpty) item,
    };
  }

  /// Whether [ownerUid]'s card was confirmed readable — without copying the set.
  static bool isVerifiedCardOwner(String? ownerUid) =>
      ownerUid != null && (_owners ??= _readOwners()).contains(ownerUid);

  static void saveVerifiedCardOwners(Iterable<String> owners) {
    final List<String> sorted = owners.toSet().toList()..sort();
    _owners = sorted.toSet();
    write(_cardOwnersKey, <String, Object?>{'owners': sorted});
  }

  /// Forgets everything — for a sign-out, when the next account must not see
  /// this one's cards or figures.
  static Future<void> clear() async {
    _pending.clear();
    _owners = null;
    if (_ready) {
      try {
        await Hive.box<dynamic>(boxName).clear();
      } on Object catch (error) {
        debugPrint('OfflineCache.clear failed: $error');
      }
    }
  }

  @visibleForTesting
  static void debugForgetPending() {
    _pending.clear();
    _owners = null;
  }
}
