import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// One "מזל טוב" on its way from one matchmaker to another.
class MazelTovMessage {
  const MazelTovMessage({
    required this.id,
    required this.matchId,
    required this.fromName,
    required this.text,
    required this.at,
  });

  static MazelTovMessage? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String matchId = ((data['matchId'] as String?) ?? '').trim();
    final String text = ((data['text'] as String?) ?? '').trim();
    if (matchId.isEmpty || text.isEmpty) {
      return null;
    }
    final Object? at = data['createdAt'];
    return MazelTovMessage(
      id: doc.id,
      matchId: matchId,
      // A sender who is hidden from the leaderboard sent this without a name,
      // and the journal line says "משדכן מהקהילה" rather than inventing one.
      fromName: ((data['fromName'] as String?) ?? '').trim(),
      text: text,
      at: at is Timestamp ? at.toDate() : DateTime.now(),
    );
  }

  final String id;

  /// The recipient's own proposal id, carried out and back so the message can
  /// land in the journal of the couple it is about.
  final String matchId;

  final String fromName;
  final String text;
  final DateTime at;
}

/// "שלחו מזל טוב" — matchmakers congratulating each other on a wedding.
///
/// **Addressed post, not a chat.** Every document here has exactly one
/// recipient and is readable by nobody else, including the sender: the rules
/// allow a read only when `toUid == request.auth.uid`. There is no thread, no
/// reply, no presence and no way to see anything anybody sent to anyone else.
/// The app has one messaging surface and it is the proposal journal that
/// already existed — see [MatchRepository.addMazelTov], which is where these
/// end up.
///
/// **What travels is deliberately thin.** A proposal id, a line of text, and
/// the sender's own name if they publish one. Nothing about either candidate:
/// the id is a local uuid that means nothing without the recipient's own
/// database, and the sender never learns who the couple are — the whole
/// announcement they are answering says "a couple got married".
///
/// **The recipient empties their own postbox.** Messages are read once, written
/// into the local journal and then deleted from the server, so the collection
/// holds only what has not yet been delivered and nothing accumulates against
/// anybody's uid.
abstract final class MazelTovService {
  static const String collection = 'communityMazelTov';

  /// Long enough for a sentence with a bracha in it, short enough that this can
  /// never become a message board. The rules enforce the same ceiling.
  static const int maxLength = 200;

  /// How many are drained in one go. A wedding might collect a dozen; a
  /// hundred would be a bug, and reading them a page at a time is what stops
  /// one from costing a hundred reads on every launch.
  static const int inboxLimit = 30;

  /// How long an *uncollected* message is kept before Firestore's TTL sweep
  /// removes it.
  ///
  /// The postbox is emptied by its recipient, which handles every message that
  /// reaches somebody. It does nothing for a message sent to a matchmaker who
  /// never opens the app again — that one sat here for ever, addressed to a
  /// person who will not come for it, in a collection whose whole point is
  /// that it holds only undelivered post.
  ///
  /// Three months is far longer than anybody's idea of "away", and short
  /// enough that this never becomes a record of who wished whom well.
  static const Duration retainFor = Duration(days: 90);

  /// The ready-made lines, for the matchmaker who wants to say the usual thing
  /// and get on with their day. Tapping one sends it; there is no second step.
  static const List<String> suggestions = <String>[
    'מזל טוב! שיזכו לבנות בית נאמן בישראל 🎉',
    'איזה יופי! כל הכבוד על העבודה 💛',
    'מזל טוב! שנשמע רק בשורות טובות',
    'ישר כוח! שתזכה לעוד הרבה זוגות',
  ];

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The account this goes out under, or null.
  ///
  /// A durable one, for the same reason a tip needs one: an anonymous uid dies
  /// with the install, so a message sent under it could never be traced back
  /// to a person by the one part of the system that has to — the recipient
  /// reading who wished them well.
  static Future<User?> _account() async {
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user;
  }

  /// Sends one congratulation. Returns false when it did not go out.
  ///
  /// Refuses to send to yourself — the announcement never shows you your own
  /// couple, but a stale card and a fast finger should not be able to put a
  /// message from you into your own journal.
  static Future<bool> send({
    required String toUid,
    required String matchId,
    required String text,
    required String fromName,
  }) async {
    final User? user = await _account();
    final String message = text.trim();
    if (user == null ||
        toUid.isEmpty ||
        toUid == user.uid ||
        matchId.isEmpty ||
        message.isEmpty ||
        message.length > maxLength) {
      return false;
    }

    try {
      await _db.collection(collection).add(<String, Object?>{
        'toUid': toUid,
        'fromUid': user.uid,
        'fromName': fromName.trim(),
        'matchId': matchId,
        'text': message,
        'createdAt': FieldValue.serverTimestamp(),
        // See [retainFor], and the note on the same field in
        // `CommunityEngagementsService.record` for why this is a client-side
        // date rather than a server sentinel.
        'expiresAt': Timestamp.fromDate(DateTime.now().toUtc().add(retainFor)),
      });
      return true;
    } catch (_) {
      // Good wishes are never worth an error in front of the person sending
      // them. The caller says "נשלח" only on true.
      return false;
    }
  }

  /// Everything addressed to this device that has not been collected yet.
  ///
  /// Empty on every failure and for every matchmaker without an account, which
  /// is the same thing as "no post today" and needs no handling anywhere.
  static Future<List<MazelTovMessage>> inbox() async {
    final User? user = await _account();
    if (user == null) {
      return const <MazelTovMessage>[];
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(collection)
          .where('toUid', isEqualTo: user.uid)
          .orderBy('createdAt')
          .limit(inboxLimit)
          .get();
      return <MazelTovMessage>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          if (MazelTovMessage.fromDocument(doc) case final MazelTovMessage m) m,
      ];
    } catch (_) {
      return const <MazelTovMessage>[];
    }
  }

  /// Clears delivered messages off the server.
  ///
  /// Called only after they are safely in the local journal. A failure here is
  /// harmless twice over: the ids are also remembered on the device, so a
  /// message that survives deletion is not written into the journal a second
  /// time.
  static Future<void> markDelivered(Iterable<String> ids) async {
    final User? user = await _account();
    if (user == null) {
      return;
    }
    final List<String> pending = ids.toList();
    if (pending.isEmpty) {
      return;
    }
    // One batch rather than a round trip per message. A wedding can collect a
    // dozen brachot, and deleting them one at a time meant a dozen sequential
    // requests on the launch that collected them — over whatever connection
    // the phone happens to have, at the moment the app is starting up.
    //
    // Chunked at Firestore's own ceiling, though [inboxLimit] means one batch
    // in practice. A batch that fails leaves every message in it on the
    // server, which is exactly what the per-message version did too: they are
    // already in the journal, already remembered by id, and skipped rather
    // than filed twice on the next drain.
    for (int start = 0; start < pending.length; start += 450) {
      final int end = start + 450 > pending.length ? pending.length : start + 450;
      try {
        final WriteBatch batch = _db.batch();
        for (final String id in pending.sublist(start, end)) {
          batch.delete(_db.collection(collection).doc(id));
        }
        await batch.commit();
      } catch (_) {
        // Left for the next drain.
      }
    }
  }
}
