import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/tips_service.dart';

/// The community tips as the app sees them.
///
/// Built around one rule that keeps Firebase off the startup path: **the
/// constructor never touches the network.** It reads the last approved batch
/// out of the local `settings` box synchronously, so the home screen has tips
/// to show on the first frame, offline, and inside a widget test. Refreshing is
/// an explicit call, made from the cloud-sync scheduler once the app is already
/// running and from the tip screens themselves.
///
/// [enabled] is the same seam `SyncProvider` and `AccountProvider` carry: a
/// widget test pumping the whole app must not reach `FirebaseBootstrap
/// .ensureReady`, which never completes inside `testWidgets`' fake-async zone
/// and fails the test with a pending timer.
class TipsProvider extends ChangeNotifier {
  TipsProvider(this._settings, {bool enabled = true}) : _enabled = enabled {
    _approved = _readCache();
  }

  static const String _cacheKey = 'tips.approvedCache';

  final Box<dynamic> _settings;
  final bool _enabled;

  List<CommunityTip> _approved = const <CommunityTip>[];
  List<CommunityTip> _mine = const <CommunityTip>[];
  List<CommunityTip> _pending = const <CommunityTip>[];
  bool _isBusy = false;

  /// Every approved tip this device knows about. Survives a restart and a lost
  /// connection, because it is a cache rather than a live query.
  List<CommunityTip> get approved => _approved;

  /// What this account has submitted, newest first. Only populated after
  /// [refreshMine].
  List<CommunityTip> get mine => _mine;

  /// The approval queue, oldest first. Only ever populated for the
  /// administrator — for anyone else the query is refused by the rules and this
  /// stays empty.
  List<CommunityTip> get pending => _pending;

  bool get isBusy => _isBusy;

  /// Pulls the approved rotation and stores it. Safe to call at any time and
  /// from anywhere: it never throws, and a failure simply leaves the cache as
  /// it was.
  Future<void> refreshApproved() async {
    if (!_enabled || _isBusy) {
      return;
    }
    _setBusy(true);
    try {
      final List<CommunityTip> tips = await TipsService.fetchApproved();
      // An empty answer is not proof the collection is empty — it is also what
      // a refused read looks like. Only a non-empty result replaces the cache.
      if (tips.isNotEmpty) {
        _approved = tips;
        await _writeCache(tips);
      }
    } catch (_) {
      // Deliberately silent: tips are the least important thing on the page.
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshMine() async {
    if (!_enabled) {
      return;
    }
    _setBusy(true);
    try {
      _mine = await TipsService.fetchMine();
    } catch (_) {
      _mine = const <CommunityTip>[];
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshPending() async {
    if (!_enabled) {
      return;
    }
    _setBusy(true);
    try {
      _pending = await TipsService.fetchPending();
    } catch (_) {
      _pending = const <CommunityTip>[];
    } finally {
      _setBusy(false);
    }
  }

  /// Sends a tip for approval and refreshes the author's own list, so the
  /// "ממתין לאישור" line appears immediately rather than on the next visit.
  Future<bool> submit({
    required String text,
    required String authorName,
  }) async {
    if (!_enabled) {
      return false;
    }
    final bool sent = await TipsService.submit(
      text: text,
      authorName: authorName,
    );
    if (sent) {
      await refreshMine();
    }
    return sent;
  }

  Future<bool> review(String tipId, TipStatus status) async {
    if (!_enabled) {
      return false;
    }
    final bool done = await TipsService.setStatus(tipId, status);
    if (done) {
      _pending = _pending
          .where((CommunityTip tip) => tip.id != tipId)
          .toList(growable: false);
      notifyListeners();
      if (status == TipStatus.approved) {
        await refreshApproved();
      }
    }
    return done;
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  List<CommunityTip> _readCache() {
    final Object? stored = _settings.get(_cacheKey);
    if (stored is! String || stored.isEmpty) {
      return const <CommunityTip>[];
    }
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! List) {
        return const <CommunityTip>[];
      }
      return <CommunityTip>[
        for (final Object? raw in decoded)
          if (CommunityTip.fromJson(raw) case final CommunityTip tip) tip,
      ];
    } catch (_) {
      return const <CommunityTip>[];
    }
  }

  Future<void> _writeCache(List<CommunityTip> tips) async {
    try {
      await _settings.put(
        _cacheKey,
        jsonEncode(<Map<String, Object?>>[
          for (final CommunityTip tip in tips) tip.toJson(),
        ]),
      );
    } catch (_) {
      // A cache that cannot be written is a cache miss next time, nothing more.
    }
  }
}
