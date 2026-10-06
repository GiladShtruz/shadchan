import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:uuid/uuid.dart';

/// What this device last agreed with the account, document by document.
///
/// The common ancestor of the three-way merge in [AccountSyncCodec.decide]:
/// for every document, the fingerprints both sides had the last time they
/// matched. Without it a difference between this phone and the account says
/// nothing about *who* changed — and "who changed" is the whole question when
/// the same matchmaker works on two phones.
///
/// Its own box rather than the `settings` box, for two reasons. It is large
/// (one entry per record) and written constantly, and the settings box is
/// itself synced, so the ledger living there would mean the ledger describing
/// itself. And it is about *this device*: losing it costs one full
/// re-comparison against the account, never data.
class AccountSyncLedger {
  AccountSyncLedger(this._box);

  static const String boxName = 'account_sync';

  /// Bumped when the meaning of a stored entry changes, which forces one fresh
  /// comparison against the account instead of trusting an old ledger.
  static const int version = 1;

  static const String _uidKey = 'meta.uid';
  static const String _versionKey = 'meta.version';
  static const String _pulledKey = 'meta.initialPullDone';
  static const String _deviceKey = 'meta.device';
  static const String _basePrefix = 'base.';
  static const String _dirtyPrefix = 'dirty.';
  static const String _cursorPrefix = 'cursor.';
  static const String _filePrefix = 'file.';

  final Box<dynamic> _box;

  /// The ledger, when its box is open — which it is from startup on, and not
  /// in a widget test that never opened it.
  static AccountSyncLedger? get maybeInstance => Hive.isBoxOpen(boxName)
      ? AccountSyncLedger(Hive.box<dynamic>(boxName))
      : null;

  /// Whether this device has once read the whole account it is signed in to.
  ///
  /// Read by the router on the first frame: a phone that has never seen its
  /// account's database must not open on an empty one and ask the matchmaker
  /// to introduce themselves again.
  static bool get initialPullDoneHere =>
      maybeInstance?.initialPullDone ?? false;

  String? get uid => _box.get(_uidKey) as String?;

  bool get initialPullDone =>
      _box.get(_pulledKey) == true && _box.get(_versionKey) == version;

  /// A random id for this install, written beside every document it sends so a
  /// conflict can be traced to the phone that caused it. Survives an account
  /// change; it describes the device, not the person.
  String get deviceId {
    final Object? stored = _box.get(_deviceKey);
    if (stored is String && stored.isNotEmpty) {
      return stored;
    }
    final String created = const Uuid().v4();
    _box.put(_deviceKey, created);
    return created;
  }

  /// Points the ledger at [accountUid]. A different account, or a ledger from
  /// an older format, is dropped: it describes some other tree.
  Future<bool> bindTo(String accountUid) async {
    if (uid == accountUid && _box.get(_versionKey) == version) {
      return false;
    }
    await clear();
    await _box.putAll(<String, Object?>{
      _uidKey: accountUid,
      _versionKey: version,
    });
    return true;
  }

  Future<void> markInitialPullDone() => _box.put(_pulledKey, true);

  /// Forgets everything except the device id.
  Future<void> clear() async {
    final String device = deviceId;
    await _box.clear();
    await _box.put(_deviceKey, device);
  }

  // --- Bases -----------------------------------------------------------------

  SyncBase? base(String path) => SyncBase.parse(_box.get('$_basePrefix$path'));

  Iterable<String> get basePaths sync* {
    for (final dynamic key in _box.keys) {
      if (key is String && key.startsWith(_basePrefix)) {
        yield key.substring(_basePrefix.length);
      }
    }
  }

  /// Records that both sides agree at [base] — or forgets the document when
  /// both are absent.
  Future<void> setBase(String path, SyncBase base) async {
    if (base.local == null && base.remote == null) {
      await _box.delete('$_basePrefix$path');
    } else {
      await _box.put('$_basePrefix$path', base.encode());
    }
  }

  /// Many bases at once — one disk write for a migration of thousands.
  Future<void> setBases(Map<String, SyncBase> bases) async {
    final Map<String, Object?> puts = <String, Object?>{};
    final List<String> deletes = <String>[];
    bases.forEach((String path, SyncBase base) {
      if (base.local == null && base.remote == null) {
        deletes.add('$_basePrefix$path');
      } else {
        puts['$_basePrefix$path'] = base.encode();
      }
    });
    if (puts.isNotEmpty) {
      await _box.putAll(puts);
    }
    if (deletes.isNotEmpty) {
      await _box.deleteAll(deletes);
    }
  }

  // --- Local changes not yet sent -----------------------------------------

  /// When this device first noticed an unsent change to [path], in
  /// milliseconds. It is this side's clock in a conflict between two edits.
  int? dirtyAt(String path) => _box.get('$_dirtyPrefix$path') as int?;

  Iterable<String> get dirtyPaths sync* {
    for (final dynamic key in _box.keys) {
      if (key is String && key.startsWith(_dirtyPrefix)) {
        yield key.substring(_dirtyPrefix.length);
      }
    }
  }

  Future<void> markDirty(String path, int atMillis) async {
    if (_box.containsKey('$_dirtyPrefix$path')) {
      return;
    }
    await _box.put('$_dirtyPrefix$path', atMillis);
  }

  Future<void> clearDirty(String path) => _box.delete('$_dirtyPrefix$path');

  // --- Cursors -----------------------------------------------------------------

  /// The latest server write time seen in [collection], in microseconds — the
  /// listener asks only for what came after it.
  int? cursor(SyncCollection collection) =>
      _box.get('$_cursorPrefix${collection.remote}') as int?;

  Future<void> setCursor(SyncCollection collection, int micros) async {
    final int? current = cursor(collection);
    if (current != null && current >= micros) {
      return;
    }
    await _box.put('$_cursorPrefix${collection.remote}', micros);
  }

  // --- Files -------------------------------------------------------------------

  /// The fingerprint (size and mtime) of a photo or recording as it was when
  /// it last reached the account — `photos/{name}` or `voice/{name}`.
  String? file(String key) => _box.get('$_filePrefix$key') as String?;

  Iterable<String> get fileKeys sync* {
    for (final dynamic key in _box.keys) {
      if (key is String && key.startsWith(_filePrefix)) {
        yield key.substring(_filePrefix.length);
      }
    }
  }

  Future<void> setFile(String key, String fingerprint) =>
      _box.put('$_filePrefix$key', fingerprint);

  Future<void> removeFile(String key) => _box.delete('$_filePrefix$key');

  @visibleForTesting
  Box<dynamic> get box => _box;
}
