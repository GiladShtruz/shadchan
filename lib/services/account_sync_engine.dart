import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/account_sync_remote.dart';

/// Keeps this device's database and the account's database the same database.
///
/// **The account holds the database; the phone holds a copy of it.** That is
/// the change from the cloud *backup* this replaced, which pushed a phone's
/// records upward and pulled them down once, at sign-in — so a second phone
/// signed in to the same account showed whatever the account held at that
/// moment and nothing anybody did afterwards, and a deletion on one phone was
/// resurrected by the other's next backup.
///
/// Here every change travels both ways, as it happens:
///
/// * **Up.** Each local Hive box is watched. A changed record is sent a moment
///   later — a deleted one as a *tombstone*, so another phone that still has
///   it learns it is gone rather than sending it back.
/// * **Down.** Each collection under `users/{uid}` is listened to for writes
///   after the last one this device saw (`_w`, the server's time), so an app
///   open costs the changes since last time, not the whole database.
/// * **Both.** When the two sides differ, the ledger says which one moved
///   since they last agreed — [AccountSyncCodec.decide].
///
/// **Offline is unchanged.** The screens still read Hive and only Hive, a
/// change made with no connection is kept in Firestore's own on-disk queue
/// and sent when there is one, and nothing here ever blocks a screen.
///
/// The first time a device meets an account, it reads the whole of it and
/// merges with whatever is on the device — which is also the one-time move of
/// a database that lived only on this phone into the account.
class AccountSyncEngine {
  AccountSyncEngine({
    required this.ledger,
    required this.remote,
    required Map<SyncCollection, Box<dynamic>> boxes,
    required this.photosDirectory,
    required this.voiceDirectory,
    this.onRemoteApplied,
    this.onLegacyProfile,
    this.flushDelay = const Duration(milliseconds: 1500),
    int Function()? nowMillis,
  }) : _boxes = boxes,
       _now = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AccountSyncLedger ledger;
  final AccountSyncRemote remote;
  final Map<SyncCollection, Box<dynamic>> _boxes;

  /// Where photos and recordings live on this device.
  final String photosDirectory;
  final String voiceDirectory;

  /// Told which collections (and which setting keys) changed because of the
  /// account, so the screens reading them can redraw.
  final void Function(AccountSyncChanges changes)? onRemoteApplied;

  /// Handed the profile document an older version of the app wrote, the first
  /// time this device meets an account that has one and no synced profile.
  final Future<void> Function(Map<String, Object?> profile)? onLegacyProfile;

  final Duration flushDelay;
  final int Function() _now;

  final List<StreamSubscription<dynamic>> _localWatches =
      <StreamSubscription<dynamic>>[];
  final List<StreamSubscription<dynamic>> _remoteWatches =
      <StreamSubscription<dynamic>>[];
  final Set<String> _dirty = <String>{};
  final Set<String> _failedDownloads = <String>{};

  Timer? _flushTimer;
  Timer? _filesTimer;
  bool _started = false;
  bool _stopped = false;
  bool _pulled = false;
  bool _listening = false;
  bool _filesRunning = false;
  Future<void> _queue = Future<void>.value();

  /// The last thing that went wrong, for a status line. Null while healthy.
  Object? lastError;

  /// Whether this device has read the account at least once since starting —
  /// until then nothing is sent, so an unread account is never overwritten.
  bool get isPulled => _pulled;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // --- Lifecycle ----------------------------------------------------------

  /// Starts watching both sides. Completes once the account has been read
  /// (or the attempt failed — see [lastError]).
  Future<void> start() async {
    if (_started) {
      return _queue;
    }
    _started = true;
    for (final SyncCollection collection in SyncCollection.values) {
      final Box<dynamic>? box = _boxes[collection];
      if (box == null) {
        continue;
      }
      _localWatches.add(
        box.watch().listen((BoxEvent event) => _onLocal(collection, event)),
      );
    }
    await _bootstrap();
  }

  /// Called when the app comes back to the foreground: retries a first read
  /// that failed, re-opens listeners that dropped, and sends what is waiting.
  Future<void> resume() async {
    if (!_started || _stopped) {
      return;
    }
    if (!_pulled) {
      await _bootstrap();
      return;
    }
    if (!_listening) {
      _startListening();
    }
    await flush();
  }

  /// Stops everything, and waits for whatever was in flight. After this the
  /// local boxes can be cleared without a single deletion reaching the
  /// account — which is exactly what signing out does next.
  Future<void> stop() async {
    _stopped = true;
    _flushTimer?.cancel();
    _filesTimer?.cancel();
    for (final StreamSubscription<dynamic> sub in _localWatches) {
      await sub.cancel();
    }
    _localWatches.clear();
    await _stopListening();
    await _queue.catchError((Object _) {});
  }

  Future<void> _stopListening() async {
    for (final StreamSubscription<dynamic> sub in _remoteWatches) {
      await sub.cancel();
    }
    _remoteWatches.clear();
    _listening = false;
  }

  /// Runs [work] after everything queued before it. Every read-compare-write
  /// goes through here, so a listener event and a local flush can never both
  /// decide about the same document at once.
  Future<void> _serial(Future<void> Function() work) {
    final Future<void> next = _queue.then((_) async {
      if (_stopped) {
        return;
      }
      try {
        await work();
      } on Object catch (error, stackTrace) {
        lastError = error;
        debugPrint('ACCOUNT_SYNC failed: $error\n$stackTrace');
      }
    });
    _queue = next;
    return next;
  }

  Future<void> _bootstrap() {
    return _serial(() async {
      if (_pulled) {
        return;
      }
      if (ledger.initialPullDone) {
        await _reconcileLocal();
      } else {
        await _fullPull();
      }
      _pulled = true;
      lastError = null;
      _bump();
    }).then((_) {
      if (_pulled && !_stopped) {
        _startListening();
        _scheduleFlush(Duration.zero);
      }
    });
  }

  // --- Reading the whole account --------------------------------------------

  Future<void> _fullPull() async {
    final Map<SyncCollection, Map<String, RemoteDocument>> remoteAll =
        <SyncCollection, Map<String, RemoteDocument>>{};
    for (final SyncCollection collection in SyncCollection.values) {
      if (_boxes[collection] == null) {
        continue;
      }
      remoteAll[collection] = await remote.fetchAll(collection);
    }
    // An older version kept the matchmaker's own profile in one document. Read
    // now, while the read is already a full one, and only used when the
    // account holds no synced profile yet.
    Map<String, Object?>? legacyProfile;
    try {
      legacyProfile = await remote.fetchLegacyProfile();
    } on Object catch (error) {
      debugPrint('ACCOUNT_SYNC legacy profile unreadable: $error');
    }
    if (_stopped) {
      return;
    }

    final List<RemoteWrite> writes = <RemoteWrite>[];
    final AccountSyncChanges changes = AccountSyncChanges();
    for (final MapEntry<SyncCollection, Map<String, RemoteDocument>> entry
        in remoteAll.entries) {
      final SyncCollection collection = entry.key;
      final Set<String> ids = <String>{
        ..._localIds(collection),
        ...entry.value.keys,
      };
      int? newest;
      for (final String id in ids) {
        final RemoteDocument document =
            entry.value[id] ?? const RemoteDocument(data: null);
        final int? written = document.writtenAtMicros;
        if (written != null && (newest == null || written > newest)) {
          newest = written;
        }
        final RemoteWrite? write = await _merge(
          collection,
          id,
          document,
          changes,
          // A document an older version wrote carries no time, and this
          // device's copy of it is what its owner has been working on: it
          // wins. One an up-to-date device wrote is the account's word.
          legacyLocalWins: written == null,
        );
        if (write != null) {
          writes.add(write);
        }
      }
      await ledger.setCursor(
        collection,
        newest ?? (_now() - const Duration(days: 1).inMilliseconds) * 1000,
      );
    }

    final bool hasSyncedProfile =
        remoteAll[SyncCollection.settings]?.containsKey(
          AccountSyncCodec.settingsDocId('userName'),
        ) ??
        false;
    if (legacyProfile != null && !hasSyncedProfile) {
      await onLegacyProfile?.call(legacyProfile);
    }

    await ledger.markInitialPullDone();
    _send(writes);
    _announce(changes);
  }

  /// Compares every local record with the ledger, to find changes made while
  /// the engine was not running — an edit just before the app was killed.
  Future<void> _reconcileLocal() async {
    final Set<String> seen = <String>{};
    int processed = 0;
    for (final SyncCollection collection in SyncCollection.values) {
      if (_boxes[collection] == null) {
        continue;
      }
      for (final String id in _localIds(collection)) {
        final String path = '${collection.remote}/$id';
        seen.add(path);
        final Map<String, Object?>? local = _localJson(collection, id);
        final String? print = local == null
            ? null
            : AccountSyncCodec.fingerprint(local);
        if (print != ledger.base(path)?.local) {
          _dirty.add(path);
          await ledger.markDirty(path, _now());
        }
        if (++processed % 250 == 0) {
          // A large database is thousands of records; let a frame through.
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    for (final String path in ledger.basePaths.toList()) {
      if (!seen.contains(path) && ledger.base(path)?.local != null) {
        _dirty.add(path);
        await ledger.markDirty(path, _now());
      }
    }
  }

  // --- Listening ---------------------------------------------------------------

  void _startListening() {
    if (_listening || _stopped) {
      return;
    }
    _listening = true;
    for (final SyncCollection collection in SyncCollection.values) {
      if (_boxes[collection] == null) {
        continue;
      }
      final int? cursor = ledger.cursor(collection);
      // Two minutes of overlap: a write the server stamped a moment before the
      // newest one seen may still be on its way. Re-reading it is a no-op.
      final int? after = cursor == null
          ? null
          : cursor - const Duration(minutes: 2).inMicroseconds;
      _remoteWatches.add(
        remote
            .watch(collection, after)
            .listen(
              (List<RemoteChange> changes) => _onRemote(collection, changes),
              onError: (Object error) {
                lastError = error;
                debugPrint(
                  'ACCOUNT_SYNC listener ${collection.remote}: $error',
                );
                unawaited(_stopListening());
              },
            ),
      );
    }
  }

  void _onRemote(SyncCollection collection, List<RemoteChange> changes) {
    unawaited(
      _serial(() async {
        final List<RemoteWrite> writes = <RemoteWrite>[];
        final AccountSyncChanges applied = AccountSyncChanges();
        int? newest;
        for (final RemoteChange change in changes) {
          final int? written = change.document.writtenAtMicros;
          if (written != null && (newest == null || written > newest)) {
            newest = written;
          }
          // Our own write, not yet confirmed by the server. The ledger was
          // updated when it was sent.
          if (change.fromThisDevice) {
            continue;
          }
          final RemoteWrite? write = await _merge(
            collection,
            change.id,
            change.document,
            applied,
          );
          if (write != null) {
            writes.add(write);
          }
        }
        if (newest != null) {
          await ledger.setCursor(collection, newest);
        }
        _send(writes);
        _announce(applied);
      }),
    );
  }

  // --- The merge -----------------------------------------------------------------

  /// Brings one document into line, and returns the write to send when this
  /// device's copy is the one that wins.
  Future<RemoteWrite?> _merge(
    SyncCollection collection,
    String id,
    RemoteDocument document,
    AccountSyncChanges changes, {
    bool legacyLocalWins = false,
  }) async {
    final String path = '${collection.remote}/$id';
    final Map<String, Object?>? local = _localJson(collection, id);
    final String? localPrint = local == null
        ? null
        : AccountSyncCodec.fingerprint(local);
    final Map<String, Object?>? remoteData = document.data;
    final String? remotePrint = remoteData == null
        ? null
        : AccountSyncCodec.fingerprint(remoteData);
    final SyncBase? base = ledger.base(path);

    final int? dirtyAt = ledger.dirtyAt(path);
    final int? remoteMillis = document.writtenAtMicros == null
        ? null
        : document.writtenAtMicros! ~/ 1000;
    final SyncDecision decision = AccountSyncCodec.decide(
      local: localPrint,
      remote: remotePrint,
      base: base,
      localChangedAt: dirtyAt ?? (legacyLocalWins ? _now() : null),
      remoteWrittenAt: remoteMillis,
    );

    switch (decision) {
      case SyncDecision.inSync:
        if (base == null ||
            base.local != localPrint ||
            base.remote != remotePrint) {
          await ledger.setBase(
            path,
            SyncBase(local: localPrint, remote: remotePrint),
          );
        }
        await _settle(path);
        return null;
      case SyncDecision.takeRemote:
        await _applyLocal(collection, id, remoteData, changes);
        final Map<String, Object?>? after = _localJson(collection, id);
        await ledger.setBase(
          path,
          SyncBase(
            local: after == null ? null : AccountSyncCodec.fingerprint(after),
            remote: remotePrint,
          ),
        );
        await _settle(path);
        _scheduleFiles();
        return null;
      case SyncDecision.pushLocal:
        await ledger.setBase(
          path,
          SyncBase(local: localPrint, remote: localPrint),
        );
        await _settle(path);
        return RemoteWrite(collection: collection, id: id, data: local);
    }
  }

  Future<void> _settle(String path) async {
    _dirty.remove(path);
    await ledger.clearDirty(path);
  }

  // --- Sending -------------------------------------------------------------------

  void _onLocal(SyncCollection collection, BoxEvent event) {
    final Object? key = event.key;
    if (key is! String) {
      return;
    }
    if (collection == SyncCollection.settings &&
        !AccountSyncCodec.isSyncedSetting(key)) {
      return;
    }
    final String id = collection == SyncCollection.settings
        ? AccountSyncCodec.settingsDocId(key)
        : key;
    final String path = '${collection.remote}/$id';
    _dirty.add(path);
    unawaited(ledger.markDirty(path, _now()));
    _scheduleFlush(flushDelay);
  }

  void _scheduleFlush(Duration delay) {
    if (_stopped) {
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(delay, () => unawaited(flush()));
  }

  /// Sends every local change that has not reached the account yet. Safe to
  /// call at any time; does nothing until the account has been read.
  Future<void> flush() {
    _flushTimer?.cancel();
    return _serial(() async {
      if (!_pulled) {
        return;
      }
      final Set<String> paths = <String>{..._dirty, ...ledger.dirtyPaths};
      _dirty.clear();
      final List<RemoteWrite> writes = <RemoteWrite>[];
      for (final String path in paths) {
        final int slash = path.indexOf('/');
        final SyncCollection? collection = SyncCollection.byRemote(
          path.substring(0, slash),
        );
        if (collection == null || _boxes[collection] == null) {
          await ledger.clearDirty(path);
          continue;
        }
        final String id = path.substring(slash + 1);
        final Map<String, Object?>? local = _localJson(collection, id);
        final String? print = local == null
            ? null
            : AccountSyncCodec.fingerprint(local);
        final SyncBase? base = ledger.base(path);
        if (print == base?.local) {
          await ledger.clearDirty(path);
          continue;
        }
        await ledger.setBase(path, SyncBase(local: print, remote: print));
        await ledger.clearDirty(path);
        writes.add(RemoteWrite(collection: collection, id: id, data: local));
      }
      _send(writes);
      _scheduleFiles();
    });
  }

  void _send(List<RemoteWrite> writes) {
    if (writes.isEmpty) {
      return;
    }
    remote.write(
      writes,
      deviceId: ledger.deviceId,
      onFailed: (List<String> paths, Object error) {
        lastError = error;
        // Forget that these were sent, so the next flush tries again.
        unawaited(
          _serial(() async {
            for (final String path in paths) {
              await ledger.setBase(
                path,
                const SyncBase(local: null, remote: null),
              );
              await ledger.markDirty(path, _now());
            }
          }),
        );
      },
    );
    _bump();
  }

  // --- Local records ---------------------------------------------------------------

  Iterable<String> _localIds(SyncCollection collection) sync* {
    final Box<dynamic> box = _boxes[collection]!;
    for (final dynamic key in box.keys) {
      if (key is! String) {
        continue;
      }
      if (collection == SyncCollection.settings) {
        if (AccountSyncCodec.isSyncedSetting(key)) {
          yield AccountSyncCodec.settingsDocId(key);
        }
      } else {
        yield key;
      }
    }
  }

  Map<String, Object?>? _localJson(SyncCollection collection, String id) {
    final Box<dynamic>? box = _boxes[collection];
    if (box == null) {
      return null;
    }
    if (collection == SyncCollection.settings) {
      final String key = Uri.decodeComponent(id);
      if (!AccountSyncCodec.isSyncedSetting(key) || !box.containsKey(key)) {
        return null;
      }
      return AccountSyncCodec.settingToRemote(key, box.get(key));
    }
    final Object? value = box.get(id);
    if (value == null) {
      return null;
    }
    return switch (collection) {
      SyncCollection.people => AccountSyncCodec.personToRemote(value as Person),
      SyncCollection.personNotes => AccountSyncCodec.personNoteToRemote(
        value as PersonNote,
      ),
      SyncCollection.personEvents => AccountSyncCodec.personEventToRemote(
        value as PersonEvent,
      ),
      SyncCollection.matches => AccountSyncCodec.matchToRemote(
        value as MatchIdea,
      ),
      SyncCollection.matchNotes => AccountSyncCodec.matchNoteToRemote(
        value as MatchNote,
      ),
      SyncCollection.matchStatusEvents =>
        AccountSyncCodec.matchStatusEventToRemote(value as MatchStatusEvent),
      SyncCollection.settings => null,
    };
  }

  Future<void> _applyLocal(
    SyncCollection collection,
    String id,
    Map<String, Object?>? data,
    AccountSyncChanges changes,
  ) async {
    final Box<dynamic> box = _boxes[collection]!;
    if (collection == SyncCollection.settings) {
      final ({String key, Object? value})? setting = data == null
          ? null
          : AccountSyncCodec.settingFromRemote(data, photosDirectory);
      final String key = setting?.key ?? Uri.decodeComponent(id);
      if (!AccountSyncCodec.isSyncedSetting(key)) {
        return;
      }
      if (setting == null) {
        if (data != null) {
          return; // Unreadable: leave the local value alone.
        }
        await box.delete(key);
      } else {
        await box.put(key, setting.value);
      }
      changes.settingKeys.add(key);
      changes.collections.add(collection);
      return;
    }

    if (data == null) {
      if (box.containsKey(id)) {
        await box.delete(id);
        changes.collections.add(collection);
      }
      return;
    }
    final Object? record = switch (collection) {
      SyncCollection.people => AccountSyncCodec.personFromRemote(
        data,
        photosDirectory,
      ),
      SyncCollection.personNotes => AccountSyncCodec.personNoteFromRemote(data),
      SyncCollection.personEvents => AccountSyncCodec.personEventFromRemote(
        data,
      ),
      SyncCollection.matches => AccountSyncCodec.matchFromRemote(data),
      SyncCollection.matchNotes => AccountSyncCodec.matchNoteFromRemote(data),
      SyncCollection.matchStatusEvents =>
        AccountSyncCodec.matchStatusEventFromRemote(data),
      SyncCollection.settings => null,
    };
    if (record == null) {
      return;
    }
    await box.put(id, record);
    changes.collections.add(collection);
  }

  void _announce(AccountSyncChanges changes) {
    if (changes.isEmpty) {
      return;
    }
    _bump();
    onRemoteApplied?.call(changes);
  }

  void _bump() => revision.value++;

  // --- Files -------------------------------------------------------------------

  void _scheduleFiles() {
    if (_stopped) {
      return;
    }
    _filesTimer?.cancel();
    _filesTimer = Timer(
      const Duration(seconds: 3),
      () => unawaited(syncFiles()),
    );
  }

  /// Uploads photos and recordings the account does not have yet, downloads
  /// the ones this device is missing, and removes from the account the ones
  /// nothing refers to any more.
  ///
  /// Best-effort and outside the record queue: files are the slow, large part,
  /// and a lost connection halfway through must cost nothing but a retry.
  Future<void> syncFiles() async {
    if (_filesRunning || !_pulled || _stopped) {
      return;
    }
    _filesRunning = true;
    bool downloaded = false;
    try {
      final Set<String> referenced = _referencedFiles();
      for (final String key in referenced) {
        if (_stopped) {
          return;
        }
        final File file = _fileFor(key);
        try {
          if (file.existsSync()) {
            final FileStat stat = file.statSync();
            final String print =
                '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
            final String? known = ledger.file(key);
            if (known == print) {
              continue;
            }
            // A file the account already holds at the same size — sent by an
            // older version, or by the phone it was downloaded from — is not
            // sent a second time.
            if (known == null && await remote.fileSize(key) == stat.size) {
              await ledger.setFile(key, print);
              continue;
            }
            await remote.upload(key, file, _contentType(key));
            await ledger.setFile(key, print);
          } else {
            if (_failedDownloads.contains(key)) {
              continue;
            }
            file.parent.createSync(recursive: true);
            if (await remote.download(key, file)) {
              final FileStat stat = file.statSync();
              await ledger.setFile(
                key,
                '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
              );
              downloaded = true;
            } else {
              _failedDownloads.add(key);
            }
          }
        } on Object catch (error) {
          debugPrint('ACCOUNT_SYNC file $key: $error');
          _failedDownloads.add(key);
        }
      }

      // A file this device once sent or fetched that no record refers to any
      // more was removed on purpose — here or on another phone, whose change
      // has already arrived.
      for (final String key in ledger.fileKeys.toList()) {
        if (_stopped) {
          return;
        }
        if (referenced.contains(key)) {
          continue;
        }
        try {
          await remote.deleteFile(key);
          await ledger.removeFile(key);
        } on Object catch (error) {
          debugPrint('ACCOUNT_SYNC file delete $key: $error');
        }
      }
    } finally {
      _filesRunning = false;
      if (downloaded) {
        _announce(
          AccountSyncChanges()
            ..collections.addAll(<SyncCollection>[
              SyncCollection.people,
              SyncCollection.personNotes,
              SyncCollection.settings,
            ]),
        );
      }
    }
  }

  Set<String> _referencedFiles() {
    final Set<String> keys = <String>{};
    final Box<dynamic>? people = _boxes[SyncCollection.people];
    if (people != null) {
      for (final dynamic value in people.values) {
        if (value is Person) {
          for (final String name in AccountSyncCodec.basenames(
            value.photosPaths,
          )) {
            keys.add('photos/$name');
          }
        }
      }
    }
    final Box<dynamic>? notes = _boxes[SyncCollection.personNotes];
    if (notes != null) {
      for (final dynamic value in notes.values) {
        final String? audio = value is PersonNote ? value.audioFile : null;
        if (audio != null && audio.isNotEmpty) {
          keys.add(
            'voice/${AccountSyncCodec.basenames(<String>[audio]).first}',
          );
        }
      }
    }
    final Box<dynamic>? settings = _boxes[SyncCollection.settings];
    if (settings != null) {
      for (final String key in <String>[
        AccountSyncCodec.profilePhotoKey,
        AccountSyncCodec.profileCardPhotosKey,
        AccountSyncCodec.personalCardKey,
      ]) {
        for (final String name in AccountSyncCodec.settingPhotoNames(
          key,
          settings.get(key),
        )) {
          keys.add('photos/$name');
        }
      }
    }
    return keys;
  }

  File _fileFor(String key) {
    final int slash = key.indexOf('/');
    final String folder = key.substring(0, slash);
    final String name = key.substring(slash + 1);
    return File(
      AccountSyncCodec.localPhotoPath(
        folder == 'voice' ? voiceDirectory : photosDirectory,
        name,
      ),
    );
  }

  static String _contentType(String key) {
    final String lower = key.toLowerCase();
    final String extension = lower.contains('.')
        ? lower.substring(lower.lastIndexOf('.') + 1)
        : '';
    if (lower.startsWith('voice/')) {
      return switch (extension) {
        'aac' => 'audio/aac',
        'opus' || 'ogg' || 'oga' => 'audio/ogg',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'amr' => 'audio/amr',
        '3gp' => 'audio/3gpp',
        _ => 'audio/mp4',
      };
    }
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }
}

/// What a batch of changes from the account touched.
class AccountSyncChanges {
  final Set<SyncCollection> collections = <SyncCollection>{};
  final Set<String> settingKeys = <String>{};

  bool get isEmpty => collections.isEmpty && settingKeys.isEmpty;
}
