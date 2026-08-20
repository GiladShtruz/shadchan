import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// Where a contributed tip stands.
enum TipStatus {
  /// Written and sent, waiting for the administrator.
  pending,

  /// Approved — in the rotation every matchmaker sees.
  approved,

  /// Turned down. Kept so the author is not left wondering, and so the same
  /// text is not resubmitted forever.
  rejected;

  static TipStatus byName(String? name) {
    for (final TipStatus status in TipStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return TipStatus.pending;
  }

  String get label {
    switch (this) {
      case TipStatus.pending:
        return 'ממתין לאישור';
      case TipStatus.approved:
        return 'אושר ומוצג לכולם';
      case TipStatus.rejected:
        return 'לא אושר';
    }
  }
}

/// One tip written by a matchmaker, for every matchmaker.
class CommunityTip {
  const CommunityTip({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorUid,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String text;

  /// First name and surname, as they are written on the author's own profile.
  /// Stored on the tip rather than looked up, because the tip outlives any
  /// reason for another matchmaker to be able to read someone else's profile.
  final String authorName;

  final String authorUid;
  final TipStatus status;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'text': text,
    'authorName': authorName,
    'authorUid': authorUid,
    'status': status.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static CommunityTip? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? text = raw['text'];
    if (id is! String || id.isEmpty || text is! String || text.trim().isEmpty) {
      return null;
    }
    final Object? at = raw['createdAt'];
    return CommunityTip(
      id: id,
      text: text.trim(),
      authorName: (raw['authorName'] as String?)?.trim() ?? '',
      authorUid: (raw['authorUid'] as String?) ?? '',
      status: TipStatus.byName(raw['status'] as String?),
      createdAt: at is int
          ? DateTime.fromMillisecondsSinceEpoch(at)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static CommunityTip? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      return null;
    }
    final Object? createdAt = data['createdAt'];
    return CommunityTip(
      id: doc.id,
      text: text.trim(),
      authorName: (data['authorName'] as String?)?.trim() ?? '',
      authorUid: (data['authorUid'] as String?) ?? '',
      status: TipStatus.byName(data['status'] as String?),
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// The community tips, in Firestore.
///
/// One flat `tips` collection rather than a per-user subtree, because this is
/// the one thing in the app that is deliberately *shared*: a tip is written by
/// one matchmaker and read by all of them. Nothing about a candidate ever
/// reaches it — the only personal data on a tip is the author's own name, which
/// they chose to put there.
///
/// Approval is enforced in `firestore.rules`, not here. A client-side check
/// decides what to draw; the rules decide what may be written, and only a
/// feedback-console administrator can move a tip out of `pending` — which is
/// what keeps an unreviewed tip out of every other matchmaker's rotation.
abstract final class TipsService {
  static const String _collection = 'tips';

  /// The root reviewer's address. Approval is no longer this address alone —
  /// the feedback console's administrator list decides, and `firestore.rules`
  /// asks that list — but the root address is on it by construction and cannot
  /// be removed, so there is always a way back in.
  static const String adminEmail = 'yitz292@gmail.com';

  /// A tip has to fit on the home screen and be readable in one breath.
  static const int maxLength = 400;

  static bool isAdminEmail(String? email) =>
      (email ?? '').trim().toLowerCase() == adminEmail;

  static CollectionReference<Map<String, dynamic>> get _tips =>
      FirebaseFirestore.instance.collection(_collection);

  static Future<User?> _requireAccount() async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    return FirebaseAuth.instance.currentUser;
  }

  /// Every approved tip. Read by any signed-in device, including an anonymous
  /// one — a matchmaker who never signed in still gets the community's tips.
  static Future<List<CommunityTip>> fetchApproved() async {
    if (await _requireAccount() == null) {
      return const <CommunityTip>[];
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _tips
        .where('status', isEqualTo: TipStatus.approved.name)
        .limit(200)
        .get();
    return _decode(snapshot);
  }

  /// The tips this account submitted, whatever became of them.
  static Future<List<CommunityTip>> fetchMine() async {
    final User? user = await _requireAccount();
    if (user == null) {
      return const <CommunityTip>[];
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _tips
        .where('authorUid', isEqualTo: user.uid)
        .limit(100)
        .get();
    final List<CommunityTip> mine = _decode(snapshot);
    mine.sort(
      (CommunityTip a, CommunityTip b) => b.createdAt.compareTo(a.createdAt),
    );
    return mine;
  }

  /// The approval queue. Readable only by the administrator — the rules refuse
  /// this query for anyone else.
  static Future<List<CommunityTip>> fetchPending() async {
    if (await _requireAccount() == null) {
      return const <CommunityTip>[];
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _tips
        .where('status', isEqualTo: TipStatus.pending.name)
        .limit(200)
        .get();
    final List<CommunityTip> pending = _decode(snapshot);
    pending.sort(
      (CommunityTip a, CommunityTip b) => a.createdAt.compareTo(b.createdAt),
    );
    return pending;
  }

  /// Sends a tip for approval. Returns false when there is no durable account
  /// to attribute it to — an anonymous device may read tips but not write one,
  /// in the rules as well as here.
  static Future<bool> submit({
    required String text,
    required String authorName,
  }) async {
    final User? user = await _requireAccount();
    final String trimmed = text.trim();
    if (user == null || user.isAnonymous || trimmed.isEmpty) {
      return false;
    }
    try {
      await _tips.add(<String, Object?>{
        'text': trimmed.length > maxLength
            ? trimmed.substring(0, maxLength)
            : trimmed,
        'authorName': authorName.trim(),
        'authorUid': user.uid,
        'status': TipStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Approves or rejects. Fails for anyone but the administrator — enforced by
  /// the rules, so a tampered client gets a permission error, not a result.
  static Future<bool> setStatus(String tipId, TipStatus status) async {
    if (await _requireAccount() == null) {
      return false;
    }
    try {
      await _tips.doc(tipId).update(<String, Object?>{
        'status': status.name,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static List<CommunityTip> _decode(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return <CommunityTip>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (CommunityTip.fromDocument(doc) case final CommunityTip tip) tip,
    ];
  }
}
