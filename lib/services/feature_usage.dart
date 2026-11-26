import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/voice_note_store.dart';

/// **Which parts of the app are actually used** — for the administrator's
/// list of features from most to least used.
///
/// Two kinds of code are tallied on this device, and nothing else:
/// * `screen:<path>` — every page opened, its path with ids folded to `:id`
///   (`screen:/people/:id`). Gathered by the router, so a new screen is in
///   the list without anybody remembering to add it.
/// * `feature:<name>` — the `Analytics.feature` actions (a tag set, a voice
///   note recorded, a card shared, a filter used…).
///
/// Per code: how many times, the first and the last day. The tally rides the
/// existing `accountHealth` device report (at most every 10 minutes), and the
/// server adds up all accounts into `adminStats/current.features`. Codes
/// only — never a name, never an id, never anything typed.
///
/// Respects "שליחת נתוני שימוש" being off, like the rest of the measurement.
abstract final class FeatureUsage {
  /// Device-only (`AccountSyncCodec`'s deny-list): each phone reports its own.
  static const String key = 'featureUsage.tally';

  /// Kept to this many codes; the least used fall off.
  static const int maxCodes = 120;

  static Map<String, Map<String, Object?>>? _tally;
  static Timer? _saveTimer;

  /// Test seam / opt-out check, set by `Analytics`.
  static bool Function() isOptedOut = () => false;

  static Map<String, Map<String, Object?>> _read() {
    final Map<String, Map<String, Object?>>? cached = _tally;
    if (cached != null) return cached;
    final Map<String, Map<String, Object?>> loaded =
        <String, Map<String, Object?>>{};
    if (Hive.isBoxOpen('settings')) {
      final Object? raw = Hive.box<dynamic>('settings').get(key);
      if (raw is String) {
        try {
          final Object? json = jsonDecode(raw);
          if (json is Map) {
            for (final MapEntry<Object?, Object?> e in json.entries) {
              if (e.key is String && e.value is Map) {
                loaded[e.key! as String] = Map<String, Object?>.from(
                  e.value! as Map,
                );
              }
            }
          }
        } on FormatException {
          // Start again.
        }
      }
    }
    return _tally = loaded;
  }

  static String _day(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  /// One use of [code].
  static void hit(String code, {DateTime? at}) {
    if (code.isEmpty || isOptedOut()) return;
    final String today = _day(at ?? DateTime.now());
    final Map<String, Map<String, Object?>> tally = _read();
    final Map<String, Object?> entry = tally[code] ??= <String, Object?>{
      'n': 0,
      'first': today,
    };
    entry['n'] = ((entry['n'] as int?) ?? 0) + 1;
    entry['last'] = today;
    if (tally.length > maxCodes) {
      final List<String> least = tally.keys.toList()
        ..sort(
          (String a, String b) => ((tally[a]!['n'] as int?) ?? 0).compareTo(
            (tally[b]!['n'] as int?) ?? 0,
          ),
        );
      for (final String drop in least.take(tally.length - maxCodes)) {
        if (drop != code) tally.remove(drop);
      }
    }
    _scheduleSave();
  }

  /// A page opened: the path with every id-like segment folded to `:id`.
  static void screen(String path) => hit('screen:${normalize(path)}');

  @visibleForTesting
  static String normalize(String path) {
    final List<String> parts = path
        .split('?')
        .first
        .split('/')
        .where((String s) => s.isNotEmpty)
        .map((String s) => RegExp(r'^[a-z][a-z-]*$').hasMatch(s) ? s : ':id')
        .toList();
    return '/${parts.join('/')}';
  }

  static void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    // Batched: a scroll through ten profiles is one write, not ten.
    _saveTimer = Timer(const Duration(seconds: 20), save);
  }

  static void save() {
    final Map<String, Map<String, Object?>>? tally = _tally;
    if (tally == null) return;
    persistHomeSetting(key, jsonEncode(tally));
  }

  /// What the device report carries.
  static Map<String, Object?> snapshot() => <String, Object?>{
    for (final e in _read().entries) e.key: e.value,
  };

  /// How much this device holds that also sits in the account's cloud
  /// storage: photos and voice notes, by count and bytes.
  static Future<Map<String, Object?>> storageFootprint() async {
    Future<(int, int)> sizeOf(Future<Directory> dir) async {
      int count = 0;
      int bytes = 0;
      try {
        final Directory d = await dir;
        if (!d.existsSync()) return (0, 0);
        await for (final FileSystemEntity e in d.list()) {
          if (e is File) {
            count++;
            bytes += await e.length();
          }
        }
      } catch (_) {
        // Whatever was counted.
      }
      return (count, bytes);
    }

    final (int photos, int photoBytes) = await sizeOf(
      PhotoPickerService.ensurePhotosDirectory(),
    );
    final (int voice, int voiceBytes) = await sizeOf(
      VoiceNoteStore.directory(),
    );
    return <String, Object?>{
      'photos': photos,
      'photoBytes': photoBytes,
      'voice': voice,
      'voiceBytes': voiceBytes,
    };
  }

  @visibleForTesting
  static void resetForTest() {
    _tally = null;
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  /// Signing out: the next account's tally starts empty.
  static void forget() {
    _saveTimer?.cancel();
    _tally = <String, Map<String, Object?>>{};
  }
}
