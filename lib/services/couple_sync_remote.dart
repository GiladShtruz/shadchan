import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_remote.dart';
import 'package:shadchan/services/couple_workspace_service.dart';

/// Shared records and board, private settings/reminders/auth/contact books.
class CoupleSyncRemote implements AccountSyncRemote {
  CoupleSyncRemote(this.uid, this.databaseUid);
  final String uid;
  final String databaseUid;
  Map<String, Map<String, Object?>>? _reminders;
  late final _personal = FirestoreAccountSyncRemote(uid);
  late final _shared = FirestoreAccountSyncRemote(databaseUid);
  CollectionReference<Map<String, dynamic>> get _settings => FirebaseFirestore
      .instance
      .collection('coupleData/${CoupleWorkspaceService.workspaceId}/settings');
  bool _isShared(String id) =>
      CoupleWorkspaceService.sharedSetting(Uri.decodeComponent(id));
  RemoteDocument _decode(Map<String, dynamic> data) => RemoteDocument(
    data: data['_deleted'] == true ? null : data,
    writtenAtMicros: (data['_w'] as Timestamp?)?.microsecondsSinceEpoch,
  );
  RemoteDocument _record(SyncCollection c, String id, RemoteDocument doc) {
    final data = doc.data;
    if (data == null) return doc;
    CoupleWorkspaceService.remember(
      c.remote,
      id,
      Map<String, dynamic>.from(data),
    );
    return RemoteDocument(
      data: c == SyncCollection.matches
          ? {
              ...data,
              ...(_reminders?[id] ?? CoupleWorkspaceService.reminder(id)),
            }
          : data,
      writtenAtMicros: doc.writtenAtMicros,
    );
  }

  @override
  Future<Map<String, RemoteDocument>> fetchAll(SyncCollection c) async {
    if (c == SyncCollection.matches && _reminders == null) {
      final settings = await _personal.fetchAll(SyncCollection.settings);
      _reminders = {};
      for (final item in settings.values) {
        final data = item.data;
        if (data == null) continue;
        final key = data['k'];
        if (key is String && key.startsWith('couple.reminder.')) {
          final value = AccountSyncCodec.settingFromRemote(data, '');
          if (value?.value is String) {
            _reminders![key.substring(
              'couple.reminder.'.length,
            )] = Map<String, Object?>.from(
              jsonDecode(value!.value as String) as Map,
            );
          }
        }
      }
    }
    if (c != SyncCollection.settings) {
      return (await _shared.fetchAll(
        c,
      )).map((id, doc) => MapEntry(id, _record(c, id, doc)));
    }
    final personal = await _personal.fetchAll(c);
    personal.removeWhere((id, _) => _isShared(id));
    final shared = await _settings.get(const GetOptions(source: Source.server));
    return {...personal, for (final d in shared.docs) d.id: _decode(d.data())};
  }

  @override
  Stream<List<RemoteChange>> watch(SyncCollection c, int? afterMicros) {
    if (c == SyncCollection.matches) {
      late StreamController<List<RemoteChange>> controller;
      final subscriptions = <StreamSubscription>[];
      controller = StreamController(
        onListen: () {
          subscriptions.add(
            _shared.watch(c, afterMicros).listen((changes) {
              controller.add([
                for (final change in changes)
                  RemoteChange(
                    id: change.id,
                    document: _record(c, change.id, change.document),
                    fromThisDevice: change.fromThisDevice,
                  ),
              ]);
            }, onError: controller.addError),
          );
          subscriptions.add(
            _personal.watch(SyncCollection.settings, null).listen((changes) {
              for (final change in changes) {
                final key =
                    change.document.data?['k'] ??
                    Uri.decodeComponent(change.id);
                if (key is! String || !key.startsWith('couple.reminder.')) {
                  continue;
                }
                final id = key.substring('couple.reminder.'.length);
                final setting = change.document.data == null
                    ? null
                    : AccountSyncCodec.settingFromRemote(
                        change.document.data!,
                        '',
                      );
                Map<String, Object?> reminder = {
                  'reminderDate': null,
                  'reminderNote': null,
                };
                try {
                  if (setting?.value is String) {
                    reminder = Map<String, Object?>.from(
                      jsonDecode(setting!.value as String) as Map,
                    );
                  }
                } catch (_) {
                  continue;
                }
                (_reminders ??= {})[id] = reminder;
                final record = CoupleWorkspaceService.metadata['matches/$id'];
                if (record != null && !change.fromThisDevice) {
                  controller.add([
                    RemoteChange(
                      id: id,
                      document: RemoteDocument(
                        data: {...record, ...reminder},
                        writtenAtMicros: change.document.writtenAtMicros,
                      ),
                    ),
                  ]);
                }
              }
            }, onError: controller.addError),
          );
        },
        onCancel: () async {
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
        },
      );
      return controller.stream;
    }
    if (c != SyncCollection.settings) {
      return _shared
          .watch(c, afterMicros)
          .map(
            (changes) => [
              for (final d in changes)
                RemoteChange(
                  id: d.id,
                  document: _record(c, d.id, d.document),
                  fromThisDevice: d.fromThisDevice,
                ),
            ],
          );
    }
    late StreamController<List<RemoteChange>> controller;
    final subs = <StreamSubscription>[];
    controller = StreamController(
      onListen: () {
        subs.add(
          _personal
              .watch(c, afterMicros)
              .listen(
                (rows) => controller.add(
                  rows.where((d) => !_isShared(d.id)).toList(),
                ),
                onError: controller.addError,
              ),
        );
        // No cursor across two independent streams: an equal timestamp must not hide an update.
        subs.add(
          _settings.snapshots().listen(
            (snap) => controller.add([
              for (final d in snap.docChanges)
                RemoteChange(
                  id: d.doc.id,
                  document: _decode(d.doc.data() ?? {'_deleted': true}),
                  fromThisDevice: d.doc.metadata.hasPendingWrites,
                ),
            ]),
            onError: controller.addError,
          ),
        );
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  void write(
    List<RemoteWrite> writes, {
    required String deviceId,
    required void Function(List<String>, Object) onFailed,
  }) {
    final personal = <RemoteWrite>[];
    for (final write in writes) {
      if (write.collection == SyncCollection.settings && !_isShared(write.id)) {
        personal.add(write);
        continue;
      }
      final data = write.data == null
          ? <String, Object?>{'_deleted': true}
          : <String, Object?>{...write.data!, '_deleted': false};
      if (write.collection == SyncCollection.matches && write.data != null) {
        _reminders?[write.id] = {
          'reminderDate': data['reminderDate'],
          'reminderNote': data['reminderNote'],
        };
        unawaited(CoupleWorkspaceService.saveReminder(write.id, data));
        data.remove('reminderDate');
        data.remove('reminderNote');
      }
      final known = CoupleWorkspaceService.metadata[write.path];
      data.addAll({
        '_w': FieldValue.serverTimestamp(),
        '_d': deviceId,
        '_actorUid': uid,
        '_sources': FieldValue.arrayUnion(
          (known?['_sources'] as List?) ?? [uid],
        ),
        '_authorUid': known?['_authorUid'] ?? uid,
      });
      final ref = write.collection == SyncCollection.settings
          ? _settings.doc(write.id)
          : FirebaseFirestore.instance.doc('users/$databaseUid/${write.path}');
      // Preserve source/conflict metadata omitted by the portable record codec.
      unawaited(
        ref
            .set(data, SetOptions(merge: true))
            .catchError((Object e) => onFailed([write.path], e)),
      );
    }
    _personal.write(personal, deviceId: deviceId, onFailed: onFailed);
  }

  @override
  Future<Map<String, Object?>?> fetchLegacyProfile() =>
      _personal.fetchLegacyProfile();
  bool _sharedFile(String key) {
    final name = key.split('/').last;
    if (key.startsWith('photos/') && Hive.isBoxOpen('people')) {
      return Hive.box<Person>(
        'people',
      ).values.any((p) => p.photosPaths.any((f) => f.split('/').last == name));
    }
    if (key.startsWith('voice/') && Hive.isBoxOpen('person_notes')) {
      return Hive.box<PersonNote>(
        'person_notes',
      ).values.any((n) => n.audioFile == name);
    }
    return false;
  }

  Reference _ref(String key) => FirebaseStorage.instance.ref(
    '${_sharedFile(key) ? 'coupleFiles/${CoupleWorkspaceService.workspaceId}' : 'users/$uid'}/$key',
  );
  @override
  Future<int?> fileSize(String key) async {
    try {
      return (await _ref(key).getMetadata()).size;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
  }

  @override
  Future<void> upload(String key, File file, String contentType) async {
    await _ref(key).putFile(file, SettableMetadata(contentType: contentType));
  }

  @override
  Future<bool> download(String key, File target) async {
    try {
      await _ref(key).writeToFile(target);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return false;
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String key) async {
    // Shared media is retained through merge/split recovery, not garbage-collected by one spouse's stale copy.
    if (!_sharedFile(key)) await _personal.deleteFile(key);
  }
}
