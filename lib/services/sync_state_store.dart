import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

/// What was last uploaded, so a sync can send the difference rather than the
/// database.
///
/// Sync runs on every app open and close. Re-uploading everything each time
/// would cost a write per record per launch — hundreds of writes a day for a
/// database nobody touched — and would do it over whatever connection the
/// phone happens to have. So each record is fingerprinted, and only records
/// whose fingerprint moved are sent.
///
/// The fingerprint is over the record's own JSON, not over a timestamp:
/// `PersonNote` and `MatchNote` are editable and carry only a `createdAt`, so
/// an edited note is invisible to any watermark scheme. Hashing the content
/// catches every change by construction, including the ones a future field
/// would introduce.
///
/// The ledger lives in the ordinary `settings` box. It is a cache, not data:
/// losing it costs one full re-upload and nothing else, which is why it is
/// never migrated or repaired — just rebuilt.
class SyncStateStore {
  SyncStateStore(this._box);

  /// One entry per synced collection, keyed by document id.
  static const String _fingerprintsKey = 'cloudSyncFingerprints';
  static const String _lastSyncedAtKey = 'cloudSyncLastSyncedAt';

  /// The uid the ledger describes. A different account has a different
  /// Firestore tree, so the ledger is meaningless against it and is dropped
  /// rather than being trusted into a half-uploaded state.
  static const String _uidKey = 'cloudSyncUid';

  final Box<dynamic> _box;

  DateTime? get lastSyncedAt {
    final Object? stored = _box.get(_lastSyncedAtKey);
    return stored is String ? DateTime.tryParse(stored) : null;
  }

  /// The fingerprint of every document believed to be in the cloud, keyed by
  /// `'<collection>/<id>'`.
  Map<String, String> get fingerprints {
    final Object? stored = _box.get(_fingerprintsKey);
    if (stored is! Map) {
      return <String, String>{};
    }
    return <String, String>{
      for (final MapEntry<dynamic, dynamic> entry in stored.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// Called before a sync starts. Returns the ledger to use — empty when the
  /// account changed, which forces a full upload into the new account's tree.
  Future<Map<String, String>> fingerprintsFor(String uid) async {
    if (_box.get(_uidKey) != uid) {
      await clear();
      await _box.put(_uidKey, uid);
      return <String, String>{};
    }
    return fingerprints;
  }

  Future<void> commit(Map<String, String> fingerprints) async {
    await _box.put(_fingerprintsKey, fingerprints);
    await _box.put(_lastSyncedAtKey, DateTime.now().toIso8601String());
  }

  Future<void> clear() async {
    await _box.delete(_fingerprintsKey);
    await _box.delete(_lastSyncedAtKey);
    await _box.delete(_uidKey);
  }

  /// A stable fingerprint of one record.
  ///
  /// The map's keys are sorted first: `jsonEncode` preserves insertion order,
  /// and a serializer that grows a field in the middle would otherwise change
  /// every fingerprint in the database and trigger one pointless full upload.
  static String fingerprint(Map<String, Object?> record) {
    final List<String> keys = record.keys.toList()..sort();
    final Map<String, Object?> ordered = <String, Object?>{
      for (final String key in keys) key: record[key],
    };
    return md5.convert(utf8.encode(jsonEncode(ordered))).toString();
  }
}
