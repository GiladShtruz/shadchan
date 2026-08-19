import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// One couple's good news, as the community sees it.
class CommunityEngagement {
  const CommunityEngagement({
    required this.id,
    required this.authorUid,
    required this.at,
    this.firstNames = '',
    this.matchmakerName = '',
    this.photoUrl = '',
    this.matchId = '',
  });

  static CommunityEngagement? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? at = data['createdAt'];
    if (at is! Timestamp) {
      // Written a moment ago by this very device and not yet stamped by the
      // server. It has no age, so it cannot be judged fresh or stale.
      return null;
    }
    return CommunityEngagement(
      id: doc.id,
      authorUid: (data['authorUid'] as String?) ?? '',
      at: at.toDate(),
      firstNames: ((data['firstNames'] as String?) ?? '').trim(),
      matchmakerName: ((data['matchmakerName'] as String?) ?? '').trim(),
      photoUrl: ((data['photoUrl'] as String?) ?? '').trim(),
      matchId: ((data['matchId'] as String?) ?? '').trim(),
    );
  }

  final String id;
  final String authorUid;
  final DateTime at;

  /// "יעל ואבי" — first names only, and only when the couple agreed. Empty on
  /// an anonymous record, which is the default and the common case.
  final String firstNames;

  final String matchmakerName;
  final String photoUrl;

  /// The author's own id for the proposal, carried so a congratulation can be
  /// delivered into the journal of the couple it is about.
  ///
  /// **It says nothing about anybody.** It is a uuid generated on the author's
  /// phone, meaningless without their database, and it is the only thing that
  /// makes "שלחו מזל טוב" possible without inventing a messaging system with
  /// threads and identities in it. Empty when the author is not accepting
  /// congratulations, which is what hides the button.
  final String matchId;

  /// Whether anybody can be congratulated for this. Both halves are needed: an
  /// author to address and a proposal to file it under.
  bool get canBeCongratulated => authorUid.isNotEmpty && matchId.isNotEmpty;

  /// Whether this carries anything about anybody. An anonymous record is a
  /// timestamp and nothing else, and reads as "somebody, somewhere".
  bool get isNamed => firstNames.isNotEmpty;
}

/// "מזל טוב! זוג חדש התארס!"
///
/// **This is the first thing in the app that can put a real candidate's name
/// and face onto a server other people read**, and the whole design is shaped
/// by keeping that door as narrow as it can be while still opening.
///
/// 1. **The default record is anonymous, and it is the only one written
///    automatically.** Marking a proposal as a wedding writes a document
///    carrying a timestamp and the matchmaker's own uid — no name, no photo, no
///    proposal id, nothing about either candidate. That is what every other
///    user is shown: *a* couple got engaged.
///
/// 2. **Names and a photo are a second, separate, deliberate act.** They are
///    only ever written by [publish], which refuses to run without
///    `coupleApproved`, and the screen that calls it makes the matchmaker tick
///    that box themselves. First names only — a full name is an identification,
///    a first name is an announcement.
///
/// 3. **Nothing here is an archive.** Reads are capped at [freshFor], so a
///    record stops being shown a week after it was written whether or not
///    anybody deletes it, and there is no screen anywhere in the app that lists
///    past engagements. The feature is a passing "מזל טוב", not a public
///    register of who married whom.
///
/// 4. **The matchmaker can take it back.** [withdraw] deletes the document and
///    the photo with it, which is the only honest answer to a couple who
///    changed their mind after saying yes.
abstract final class CommunityEngagementsService {
  static const String collection = 'communityEngagements';

  /// How long a record is worth showing. A week: long enough that somebody who
  /// opens the app on Fridays still hears about Sunday's couple, short enough
  /// that nothing here is ever a history.
  static const Duration freshFor = Duration(days: 7);

  /// The ceiling the rules also enforce. First names, not full ones.
  static const int maxNamesLength = 80;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<User?> _account() async {
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    return FirebaseAuth.instance.currentUser;
  }

  /// Records that a couple got engaged, anonymously, and returns the new
  /// document's id so the matchmaker can be offered the chance to say more.
  ///
  /// Returns null when there is no account or the write failed — good news is
  /// never worth an error in front of somebody who is having a good day.
  /// [matchId] is the author's own proposal id, written so other matchmakers
  /// can send a "מזל טוב" back to the right couple's journal. [matchmakerName]
  /// is written only when the caller has established that this matchmaker
  /// publishes their name at all — the announcement is anonymous otherwise,
  /// and the button on it still works, because a message is addressed by uid
  /// rather than by name.
  static Future<String?> record({
    String matchId = '',
    String matchmakerName = '',
  }) async {
    final User? user = await _account();
    if (user == null) {
      return null;
    }
    try {
      final DocumentReference<Map<String, dynamic>> doc = _db
          .collection(collection)
          .doc();
      await doc.set(<String, Object?>{
        'authorUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        // Written explicitly rather than left absent so that the shape of an
        // anonymous record and a published one is the same document with
        // different values in it, and the rules can check one set of fields.
        'firstNames': '',
        'matchmakerName': matchmakerName.trim(),
        'photoUrl': '',
        'matchId': matchId.trim(),
      });
      return doc.id;
    } catch (_) {
      return null;
    }
  }

  /// Whether this device may put names to a couple at all.
  ///
  /// A durable account, for the same reason writing a tip needs one: an
  /// anonymous uid dies with the install, and two people's names published
  /// under one could never afterwards be withdrawn by the person who put them
  /// there. The rules refuse it too; this is what stops the app *offering* it.
  static Future<bool> canPublishNames() async {
    final User? user = await _account();
    return user != null && !user.isAnonymous;
  }

  /// Adds the couple's first names, the matchmaker's name and an optional photo
  /// to a record made by [record].
  ///
  /// [coupleApproved] is not a formality and not a default. It is false unless
  /// the matchmaker has ticked the box themselves, and this returns false
  /// without writing anything when it is — the same check the security rules
  /// make, made here too so a bug cannot reach the network.
  static Future<bool> publish({
    required String engagementId,
    required String firstNames,
    required String matchmakerName,
    required bool coupleApproved,
    File? photo,
  }) async {
    final User? user = await _account();
    if (user == null || user.isAnonymous || !coupleApproved) {
      return false;
    }
    final String names = firstNames.trim();
    if (names.isEmpty || names.length > maxNamesLength) {
      return false;
    }

    try {
      final String photoUrl = photo == null
          ? ''
          : await _uploadPhoto(user.uid, engagementId, photo) ?? '';

      await _db.collection(collection).doc(engagementId).set(<String, Object?>{
        'firstNames': names,
        'matchmakerName': matchmakerName.trim(),
        'photoUrl': photoUrl,
        'coupleApproved': true,
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the record and its photo. Used when a couple changes its mind.
  static Future<bool> withdraw(String engagementId) async {
    final User? user = await _account();
    if (user == null) {
      return false;
    }
    try {
      await _db.collection(collection).doc(engagementId).delete();
      // Best effort, and after the document: the record being gone is what the
      // couple asked for, and an orphaned file nobody has a URL to is a smaller
      // failure than a document that outlives its deletion.
      try {
        await _photoRef(user.uid, engagementId).delete();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  static Reference _photoRef(String uid, String engagementId) =>
      FirebaseStorage.instance.ref('$collection/$uid/$engagementId.jpg');

  static Future<String?> _uploadPhoto(
    String uid,
    String engagementId,
    File photo,
  ) async {
    try {
      final Reference ref = _photoRef(uid, engagementId);
      await ref.putFile(photo, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (_) {
      // A published couple with no picture is still a published couple. The
      // names go up either way rather than the whole thing failing on a photo.
      return null;
    }
  }

  /// The newest engagement this device has not been told about, or null.
  ///
  /// **Your own couple is skipped.** You were there; being congratulated by
  /// your own phone about news you entered ten minutes ago reads as a bug.
  ///
  /// A handful of documents rather than one, because the newest may well be
  /// yours or may be one you have already seen, and a second round trip to find
  /// that out costs more than four extra documents.
  static Future<CommunityEngagement?> latestUnseen({
    required String seenId,
    DateTime? now,
  }) async {
    final User? user = await _account();
    if (user == null) {
      return null;
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(collection)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      final DateTime cutoff = (now ?? DateTime.now()).subtract(freshFor);
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final CommunityEngagement? engagement =
            CommunityEngagement.fromDocument(doc);
        if (engagement == null || engagement.at.isBefore(cutoff)) {
          continue;
        }
        if (engagement.id == seenId || engagement.authorUid == user.uid) {
          continue;
        }
        return engagement;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
