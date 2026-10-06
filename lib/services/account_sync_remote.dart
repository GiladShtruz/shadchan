import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/account_sync_codec.dart';

/// The account's side of the sync, as [AccountSyncEngine] sees it.
///
/// An interface so the engine — which decides whether somebody's work
/// survives — can be tested against an in-memory account with two "phones"
/// on it, rather than only against a network nobody can run in a test.
abstract class AccountSyncRemote {
  /// Every document in [collection], tombstones included. Throws when the
  /// server cannot be reached: an answer from a cache is not an answer to
  /// "what does the account hold".
  Future<Map<String, RemoteDocument>> fetchAll(SyncCollection collection);

  /// Changes in [collection] written after [afterMicros] (or all, when null),
  /// as they happen.
  Stream<List<RemoteChange>> watch(SyncCollection collection, int? afterMicros);

  /// Writes documents (a null `data` writes a tombstone). Returns without
  /// waiting for the server: the write is queued locally and sent whenever
  /// there is a connection. [onFailed] hears about a write the server refused.
  void write(
    List<RemoteWrite> writes, {
    required String deviceId,
    required void Function(List<String> paths, Object error) onFailed,
  });

  /// The legacy single profile document (`profile/main`) older versions
  /// wrote, or null.
  Future<Map<String, Object?>?> fetchLegacyProfile();

  // --- Files ---------------------------------------------------------------

  /// The size of a stored file, or null when there is none.
  Future<int?> fileSize(String key);

  Future<void> upload(String key, File file, String contentType);

  /// Downloads into [target]. False when the account has no such file.
  Future<bool> download(String key, File target);

  Future<void> deleteFile(String key);
}

class RemoteDocument {
  const RemoteDocument({required this.data, this.writtenAtMicros});

  /// The record, or null for a tombstone.
  final Map<String, Object?>? data;

  final int? writtenAtMicros;
}

class RemoteChange {
  const RemoteChange({
    required this.id,
    required this.document,
    this.fromThisDevice = false,
  });

  final String id;
  final RemoteDocument document;

  /// A write of ours the server has not confirmed yet. Already accounted for.
  final bool fromThisDevice;
}

class RemoteWrite {
  const RemoteWrite({
    required this.collection,
    required this.id,
    required this.data,
  });

  final SyncCollection collection;
  final String id;

  /// Null writes a tombstone.
  final Map<String, Object?>? data;

  String get path => '${collection.remote}/$id';
}

/// The real account: Firestore under `users/{uid}`, Storage under the same.
class FirestoreAccountSyncRemote implements AccountSyncRemote {
  FirestoreAccountSyncRemote(this.uid);

  final String uid;

  /// Firestore refuses a batch of more than 500 operations.
  static const int _batchLimit = 450;

  DocumentReference<Map<String, dynamic>> get _root =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  @override
  Future<Map<String, RemoteDocument>> fetchAll(
    SyncCollection collection,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _root
        .collection(collection.remote)
        .get(const GetOptions(source: Source.server));
    return <String, RemoteDocument>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        doc.id: _document(doc.data()),
    };
  }

  @override
  Stream<List<RemoteChange>> watch(
    SyncCollection collection,
    int? afterMicros,
  ) {
    Query<Map<String, dynamic>> query = _root.collection(collection.remote);
    if (afterMicros != null) {
      query = query.where(
        AccountSyncCodec.writtenAtField,
        isGreaterThan: Timestamp.fromMicrosecondsSinceEpoch(afterMicros),
      );
    }
    return query.snapshots(includeMetadataChanges: false).map((
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) {
      return <RemoteChange>[
        for (final DocumentChange<Map<String, dynamic>> change
            in snapshot.docChanges)
          RemoteChange(
            id: change.doc.id,
            fromThisDevice: change.doc.metadata.hasPendingWrites,
            document: change.type == DocumentChangeType.removed
                ? const RemoteDocument(data: null)
                : _document(change.doc.data() ?? <String, dynamic>{}),
          ),
      ];
    });
  }

  static RemoteDocument _document(Map<String, dynamic> raw) {
    final Object? written = raw[AccountSyncCodec.writtenAtField];
    return RemoteDocument(
      data: AccountSyncCodec.isTombstone(raw)
          ? null
          : Map<String, Object?>.from(raw),
      writtenAtMicros: written is Timestamp
          ? written.microsecondsSinceEpoch
          : null,
    );
  }

  @override
  void write(
    List<RemoteWrite> writes, {
    required String deviceId,
    required void Function(List<String> paths, Object error) onFailed,
  }) {
    for (int start = 0; start < writes.length; start += _batchLimit) {
      final List<RemoteWrite> chunk = writes.sublist(
        start,
        start + _batchLimit > writes.length
            ? writes.length
            : start + _batchLimit,
      );
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final RemoteWrite write in chunk) {
        final Map<String, Object?> meta = <String, Object?>{
          AccountSyncCodec.writtenAtField: FieldValue.serverTimestamp(),
          AccountSyncCodec.deviceField: deviceId,
        };
        batch.set(
          _root.collection(write.collection.remote).doc(write.id),
          write.data == null
              ? <String, Object?>{AccountSyncCodec.deletedField: true, ...meta}
              : <String, Object?>{...write.data!, ...meta},
        );
      }
      // Not awaited: it completes when the server confirms, which offline is
      // whenever the phone next has a connection. Firestore has already put
      // the write in its own on-disk queue, so it survives the app closing.
      unawaited(
        batch.commit().catchError((Object error) {
          debugPrint('ACCOUNT_SYNC write refused: $error');
          onFailed(<String>[for (final RemoteWrite w in chunk) w.path], error);
        }),
      );
    }
  }

  @override
  Future<Map<String, Object?>?> fetchLegacyProfile() async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _root
        .collection('profile')
        .doc('main')
        .get(const GetOptions(source: Source.server));
    return snapshot.exists ? snapshot.data() : null;
  }

  Reference _ref(String key) => FirebaseStorage.instance.ref('users/$uid/$key');

  @override
  Future<int?> fileSize(String key) async {
    try {
      final FullMetadata metadata = await _ref(key).getMetadata();
      return metadata.size;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return null;
      }
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
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String key) async {
    try {
      await _ref(key).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        rethrow;
      }
    }
  }
}
