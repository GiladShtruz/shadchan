import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// How this phone's address book read went last time — for support and for
/// the administrators' alerts, never anybody's contact.
///
/// Kept on the device (`contacts.health`, outside the account sync: it is
/// about this phone) and sent with the device's part of `accountHealth/{uid}`
/// (see `AccountHealthService.deviceReport`). The server reads every device's
/// copy and raises an alert when reads start failing, or when a new version
/// finds far fewer contacts than the one before it — the "my contacts went
/// missing" signal, seen before anybody writes in.
///
/// Only numbers, a permission word and an error *type* are kept.
abstract final class ContactsHealth {
  static const String key = 'contacts.health';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// What was written this run — the write itself lands a microtask later.
  static Map<String, Object?>? _cache;

  @visibleForTesting
  static void resetForTest() => _cache = null;

  /// The last report, or empty when the address book was never read here.
  static Map<String, Object?> snapshot() {
    final Map<String, Object?>? cached = _cache;
    if (cached != null) {
      return Map<String, Object?>.of(cached);
    }
    final Object? raw = _box?.get(key);
    if (raw is! String || raw.isEmpty) {
      return <String, Object?>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  static void _write(Map<String, Object?> values) {
    if (_box == null) {
      return;
    }
    final Map<String, Object?> next = <String, Object?>{
      ...snapshot(),
      ...values,
    };
    _cache = next;
    persistHomeSetting(key, jsonEncode(next));
  }

  /// A successful read: how many contacts the phone has, and how many of
  /// them could be offered.
  static void recordRead({required int deviceCount, required int suitable}) {
    _write(<String, Object?>{
      'readAt': DateTime.now().toUtc().toIso8601String(),
      'deviceCount': deviceCount,
      'suitable': suitable,
      'permission': 'granted',
    });
  }

  /// A read that failed, by error type.
  static void recordFailure(String code) {
    _write(<String, Object?>{
      'failedAt': DateTime.now().toUtc().toIso8601String(),
      'failure': code,
    });
  }

  /// Where the permission stands: `granted`, `denied` or `blocked`.
  static void recordPermission(String state) {
    _write(<String, Object?>{'permission': state});
  }

  /// On sign-out, with the rest of the device's copy.
  static void reset() {
    _cache = <String, Object?>{};
    if (_box != null) {
      persistHomeSetting(key, '');
    }
  }
}
