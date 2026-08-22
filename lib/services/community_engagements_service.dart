import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// One couple's good news, as the community sees it.
class CommunityEngagement {
  const CommunityEngagement({
    required this.id,
    required this.authorUid,
    required this.at,
    this.matchmakerName = '',
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
      matchmakerName: ((data['matchmakerName'] as String?) ?? '').trim(),
      matchId: ((data['matchId'] as String?) ?? '').trim(),
    );
  }

  final String id;
  final String authorUid;
  final DateTime at;

  /// The matchmaker's own name, and the only name this record can ever carry.
  /// Empty unless they were asked and said yes — see [attachMatchmakerName].
  final String matchmakerName;

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
}

/// "מזל טוב! זוג חדש התארס!"
///
/// **Nothing about either member of the couple ever reaches this server.** Not
/// a name, not a first name, not a photograph, not an age. The app once offered
/// to publish the couple's first names and a picture with their permission; the
/// feature was removed, because "with their permission" rests on one person
/// ticking a box about two other people who are not users, never agreed to
/// anything, and would have no way of knowing. The announcement is worth having
/// and the identification never was.
///
/// What a record carries:
///
/// 1. **A wedding happened.** A timestamp, the matchmaker's uid, and their own
///    proposal id so a bracha can be delivered back. That is what every other
///    user is shown: *a* couple got married.
///
/// 2. **The matchmaker's own name, if they said yes.** Written only by
///    [attachMatchmakerName], only after [MatchmakerNameDialog] asked, and
///    asked afresh for every wedding — appearing on a leaderboard is a standing
///    preference and this is one sentence on one day.
///
/// 3. **Nothing here is an archive.** Reads are capped at [freshFor], so a
///    record stops being shown a week after it was written whether or not
///    anybody deletes it, and there is no screen anywhere in the app that lists
///    past weddings.
///
/// 4. **The name can be taken back.** [detachMatchmakerName] removes it and
///    leaves the anonymous announcement standing.
abstract final class CommunityEngagementsService {
  static const String collection = 'communityEngagements';

  /// How long a record is worth showing. A week: long enough that somebody who
  /// opens the app on Fridays still hears about Sunday's couple, short enough
  /// that nothing here is ever a history.
  static const Duration freshFor = Duration(days: 7);

  /// How long a record is kept at all, before Firestore's own TTL sweep
  /// removes it.
  ///
  /// **Because [freshFor] only stopped the app from *showing* a record — it
  /// never deleted one.** No screen in the app lists past weddings, so every
  /// document older than a week was data nobody could reach and nobody would
  /// ever look at, kept for ever against a matchmaker's uid. Keeping what you
  /// have stopped using is exactly what data minimisation forbids, and it also
  /// meant this collection only ever grew.
  ///
  /// Four times [freshFor] rather than exactly it, so a record is deleted well
  /// after the last device could still have wanted it — a phone with a slow
  /// clock or a long sleep must never watch a record vanish mid-read.
  static const Duration retainFor = Duration(days: 28);

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
  /// can send a "מזל טוב" back to the right couple's journal.
  ///
  /// **The record carries no name.** It used to take the matchmaker's name
  /// whenever they were visible on the leaderboard, which meant the
  /// "anonymous" announcement went out reading "X made a match" without anybody
  /// having been asked. The name is now attached afterwards, and only by
  /// [attachMatchmakerName], and only after the matchmaker says yes.
  static Future<String?> record({String matchId = ''}) async {
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
        // When Firestore's TTL sweep should delete this record. A date the
        // client computes rather than a server sentinel, because a TTL policy
        // deletes a document *at* the moment its chosen field names — so the
        // field has to hold the expiry, not the birthday. Pointing a policy at
        // `createdAt` would delete every record the instant it was written.
        //
        // A phone with a badly wrong clock therefore writes a badly wrong
        // expiry. The rules refuse one in the past, and the consequence of the
        // remaining cases is a record that lingers or goes early — never
        // anybody else's data, and never a record that outlives its author's
        // ability to delete it.
        'expiresAt': Timestamp.fromDate(DateTime.now().toUtc().add(retainFor)),
        // Written explicitly rather than left absent so that every record in
        // the collection has the same shape and the rules can check one set of
        // fields.
        'matchmakerName': '',
        'matchId': matchId.trim(),
      });
      return doc.id;
    } catch (_) {
      return null;
    }
  }

  /// Puts the matchmaker's own name on a record made by [record].
  ///
  /// Asked of everybody who reaches a wedding, and never assumed: being visible
  /// on the leaderboard is a standing preference about a list of names, and
  /// this is one sentence about one couple on one day.
  ///
  /// A durable account is required because a name published under a uid that
  /// dies with the install can never afterwards be taken down by the person who
  /// put it there.
  static Future<bool> attachMatchmakerName({
    required String engagementId,
    required String matchmakerName,
  }) async {
    final User? user = await _account();
    final String name = matchmakerName.trim();
    if (user == null || user.isAnonymous || name.isEmpty) {
      return false;
    }
    try {
      await _db.collection(collection).doc(engagementId).set(<String, Object?>{
        'matchmakerName': name,
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether this device may put a name on a record at all.
  ///
  /// A durable account, for the same reason writing a tip needs one: an
  /// anonymous uid dies with the install, and a name published under one could
  /// never afterwards be withdrawn by the person who put it there. The rules
  /// refuse it too; this is what stops the app *asking*.
  static Future<bool> canBeNamed() async {
    final User? user = await _account();
    return user != null && !user.isAnonymous;
  }

  /// Takes the matchmaker's name back off a record, leaving the announcement
  /// itself standing.
  ///
  /// The record is worth keeping either way — the community heard that a couple
  /// got married, and that was never the part anybody could regret. What can be
  /// regretted is having said "yes, say it was me", so that is the only part
  /// this removes.
  static Future<bool> detachMatchmakerName(String engagementId) async {
    final User? user = await _account();
    if (user == null) {
      return false;
    }
    try {
      await _db.collection(collection).doc(engagementId).set(<String, Object?>{
        'matchmakerName': '',
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
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
