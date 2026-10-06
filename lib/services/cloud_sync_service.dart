import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// Erasing an account's database from the server.
///
/// This used to be the whole cloud backup — push on open and close, restore on
/// request. The database now lives in the account and is kept in step by
/// `AccountSyncEngine`; what is left here is the one thing that engine never
/// does: removing all of it, for an account that is being deleted for good.
abstract final class CloudSyncService {
  /// Firestore cannot enumerate a document's subcollections from a client, so
  /// an erasure that missed one would leave it behind silently, for ever. Every
  /// collection the sync writes, plus `profile` (written by older versions).
  static final List<String> _collections = <String>[
    for (final SyncCollection collection in SyncCollection.values)
      collection.remote,
    'profile',
  ];

  /// The two Storage folders under `users/{uid}`.
  static const List<String> _fileFolders = <String>['photos', 'voice'];

  static const int _batchLimit = 450;

  /// Deletes this account's whole database from the server — every record,
  /// every tombstone, the profile, and every photo and recording.
  ///
  /// **Reports its failures**: somebody who has just been told their data is
  /// gone must never be told it wrongly, so a partial deletion answers false.
  static Future<bool> deleteBackup() async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return false;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return false;
    }
    final String uid = user.uid;

    try {
      final DocumentReference<Map<String, dynamic>> root = FirebaseFirestore
          .instance
          .collection('users')
          .doc(uid);
      // The records first, then the root document. Interrupted, that leaves a
      // root describing a tree already gone, rather than orphaned records under
      // no root that nothing would ever visit again.
      for (final String collection in _collections) {
        await _deleteCollection(root.collection(collection));
      }
      for (final String folder in _fileFolders) {
        await _deleteFolder(FirebaseStorage.instance.ref('users/$uid/$folder'));
      }
      await root.delete();
      return true;
    } on FirebaseException catch (error) {
      debugPrint('CLOUD_DELETE failed: ${error.code} ${error.message}');
      return false;
    } catch (error, stackTrace) {
      debugPrint('CLOUD_DELETE failed: $error\n$stackTrace');
      return false;
    }
  }

  /// Empties one collection a page at a time — there is no recursive delete
  /// on the client.
  static Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> page = await collection
          .limit(_batchLimit)
          .get(const GetOptions(source: Source.server));
      if (page.docs.isEmpty) {
        return;
      }
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (page.docs.length < _batchLimit) {
        return;
      }
    }
  }

  /// Listed from Storage rather than derived from the records: a file left
  /// behind by an interrupted delete is exactly the one that would otherwise
  /// outlive the request to remove it.
  static Future<void> _deleteFolder(Reference folder) async {
    ListResult page = await folder.list(const ListOptions(maxResults: 100));
    while (true) {
      for (final Reference item in page.items) {
        await item.delete();
      }
      final String? token = page.nextPageToken;
      if (token == null) {
        return;
      }
      page = await folder.list(ListOptions(maxResults: 100, pageToken: token));
    }
  }
}
