import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/cloud_sync_service.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// Removes every server-side record that belongs to the current account.
///
/// This runs while the Firebase user is still authenticated. That order is
/// essential: once [User.delete] succeeds the security rules can no longer
/// prove ownership, and a deleted authentication row with a live backup below
/// it would be impossible for the account holder to clean up themselves.
///
/// Support reports are the one deliberate exception. They are correspondence
/// with the app team, may include an administrator's reply, and are retained
/// for support and abuse-prevention purposes as described in the privacy
/// policy. They can still be removed early by contacting the address shown
/// there.
abstract final class AccountRemoteDataService {
  static const int _batchLimit = 100;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// True only when the whole erasure completed.
  ///
  /// Every operation is idempotent. If a connection drops after two
  /// collections were removed, the authentication account and the local
  /// database stay in place; a second attempt safely continues from what is
  /// left rather than turning a partial deletion into an orphaned account.
  static Future<bool> deleteAll() async {
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
      if (!await CloudSyncService.deleteBackup()) {
        return false;
      }
      if (!await CommunityService.deleteMyData()) {
        return false;
      }

      await _deleteWhere(
        collection: 'communityEngagements',
        field: 'authorUid',
        uid: uid,
      );
      await _deleteWhere(collection: 'tips', field: 'authorUid', uid: uid);

      // Delete both sides of the temporary congratulations postbox. Outgoing
      // messages still identify this uid as their sender; incoming ones would
      // otherwise remain addressed to an account that no longer exists.
      await _deleteWhere(
        collection: 'communityMazelTov',
        field: 'fromUid',
        uid: uid,
      );
      await _deleteWhere(
        collection: 'communityMazelTov',
        field: 'toUid',
        uid: uid,
      );
      return true;
    } on FirebaseException catch (error) {
      debugPrint(
        'ACCOUNT remote data deletion failed: ${error.code} ${error.message}',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('ACCOUNT remote data deletion failed: $error\n$stackTrace');
      return false;
    }
  }

  static Future<void> _deleteWhere({
    required String collection,
    required String field,
    required String uid,
  }) async {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> page = await _db
          .collection(collection)
          .where(field, isEqualTo: uid)
          .limit(_batchLimit)
          .get();
      if (page.docs.isEmpty) {
        return;
      }
      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (page.docs.length < _batchLimit) {
        return;
      }
    }
  }
}
