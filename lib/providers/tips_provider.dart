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
/// One of the tips that ship with the app, as the rotation shows it.
class BuiltInTip {
  const BuiltInTip({required this.original, this.override});

  /// The template as it is written in [MatchmakerTips.tips].
  final String original;

  /// The administrator's edit, if there is one.
  final CommunityTip? override;

  /// The words to show — a gender template, like [original].
  String get text => override?.text ?? original;

  bool get hidden => override?.hidden ?? false;

  bool get edited => override != null;
}

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
  List<CommunityTip> _all = const <CommunityTip>[];
  bool _isBusy = false;

  /// Every tip in the collection — the administrator's full list. Only
  /// populated after [refreshAll], and only ever for an administrator.
  List<CommunityTip> get all => _all;

  /// The approved community tips to show, without the administrator's edits
  /// of the built-in ones (those take the built-in's place — see
  /// [builtInTips]) and without anything hidden.
  List<CommunityTip> get visibleCommunity => <CommunityTip>[
    for (final CommunityTip tip in _approved)
      if (!tip.isBuiltInOverride && !tip.hidden) tip,
  ];

  /// The tips that ship with the app, each with the administrator's edit
  /// applied when there is one. [text] is a gender template like the
  /// originals; [hidden] ones are left out of every rotation.
  List<BuiltInTip> builtInTips(List<String> originals) {
    final List<CommunityTip> source = _all.isNotEmpty ? _all : _approved;
    final Map<String, CommunityTip> overrides = <String, CommunityTip>{};
    // Newest first, so the latest edit of a tip wins.
    for (final CommunityTip tip in source) {
      final String? key = tip.builtInText;
      if (key != null &&
          key.isNotEmpty &&
          tip.status == TipStatus.approved &&
          !overrides.containsKey(key)) {
        overrides[key] = tip;
      }
    }
    return <BuiltInTip>[
      for (final String original in originals)
        BuiltInTip(original: original, override: overrides[original]),
    ];
  }

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

  Future<void> refreshAll() async {
    if (!_enabled) {
      return;
    }
    _setBusy(true);
    try {
      _all = await TipsService.fetchAll();
    } catch (_) {
      _all = const <CommunityTip>[];
    } finally {
      _setBusy(false);
    }
  }

  /// The administrator's edit of a community tip. Refreshes every list the
  /// tip could be in, so the change is on screen at once.
  Future<bool> edit(
    CommunityTip tip, {
    String? text,
    TipStatus? status,
    bool? hidden,
  }) async {
    if (!_enabled) {
      return false;
    }
    final bool done = await TipsService.edit(
      tip.id,
      text: text,
      status: status,
      hidden: hidden,
    );
    if (done) {
      await _afterAdminChange();
    }
    return done;
  }

  /// Edits or hides a built-in tip — updating its existing override when
  /// there is one, writing a new one otherwise.
  Future<bool> editBuiltIn(
    BuiltInTip tip, {
    required String text,
    required bool hidden,
  }) async {
    if (!_enabled) {
      return false;
    }
    final CommunityTip? existing = tip.override;
    final bool done = existing != null
        ? await TipsService.edit(existing.id, text: text, hidden: hidden)
        : await TipsService.overrideBuiltIn(
                builtInText: tip.original,
                text: text,
                hidden: hidden,
              ) !=
              null;
    if (done) {
      await _afterAdminChange();
    }
    return done;
  }

  /// Deletes a community tip, or — for a built-in tip — the edit, which puts
  /// the app's own words back.
  Future<bool> delete(String tipId) async {
    if (!_enabled) {
      return false;
    }
    final bool done = await TipsService.delete(tipId);
    if (done) {
      _approved = _approved
          .where((CommunityTip t) => t.id != tipId)
          .toList(growable: false);
      await _writeCache(_approved);
      await _afterAdminChange();
    }
    return done;
  }

  Future<void> _afterAdminChange() async {
    await refreshAll();
    await refreshPending();
    await _refreshApprovedAllowingEmpty();
  }

  /// [refreshApproved], except that an empty answer is believed: after the
  /// administrator deleted the last tip, empty *is* the truth.
  Future<void> _refreshApprovedAllowingEmpty() async {
    try {
      final List<CommunityTip> tips = await TipsService.fetchApproved();
      _approved = tips;
      await _writeCache(tips);
      notifyListeners();
    } catch (_) {}
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
      if (_all.isNotEmpty) {
        await refreshAll();
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
