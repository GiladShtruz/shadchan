import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shadchan/services/device_facts.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// Where a report stands, as the person handling it sees it.
enum SupportReportStatus {
  /// Arrived, nobody has looked yet.
  isNew,

  /// Somebody is on it.
  inProgress,

  /// Answered, fixed, or decided against.
  done;

  static SupportReportStatus byName(String? name) {
    for (final SupportReportStatus status in SupportReportStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return SupportReportStatus.isNew;
  }

  String get label {
    switch (this) {
      case SupportReportStatus.isNew:
        return 'חדש';
      case SupportReportStatus.inProgress:
        return 'בטיפול';
      case SupportReportStatus.done:
        return 'טופל';
    }
  }
}

/// What a report is about, as the person sending it would describe it.
///
/// **A label on one form, not four forms.** Splitting the form asks the
/// reporter to classify their problem before they have described it, and the
/// answer is wrong often enough to matter. A single optional row of chips costs
/// the reporter one tap they may skip, and it is what turns the console from a
/// pile of messages into an inbox that can be worked through by kind — which is
/// the whole reason it exists.
///
/// [unsorted] is the default and a real answer: it means nobody said, and the
/// person triaging reads the words and decides.
enum SupportReportKind {
  /// "היה עוזר אם…" — a feature, a suggestion, a request.
  idea,

  /// A wording fix, a wrong detail, a small correction.
  note,

  /// Something is broken.
  bug,

  /// No answer given.
  unsorted;

  static SupportReportKind byName(String? name) {
    for (final SupportReportKind kind in SupportReportKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return SupportReportKind.unsorted;
  }

  /// What the reporter is offered on the form.
  String get label {
    switch (this) {
      case SupportReportKind.idea:
        return 'המלצה או רעיון';
      case SupportReportKind.note:
        return 'הערה או תיקון';
      case SupportReportKind.bug:
        return 'תקלה טכנית';
      case SupportReportKind.unsorted:
        return 'משהו אחר';
    }
  }

  /// What the console calls the group.
  String get pluralLabel {
    switch (this) {
      case SupportReportKind.idea:
        return 'המלצות ורעיונות';
      case SupportReportKind.note:
        return 'הערות ותיקונים';
      case SupportReportKind.bug:
        return 'תקלות ובאגים';
      case SupportReportKind.unsorted:
        return 'ללא סיווג';
    }
  }
}

/// One thing a matchmaker told the developers — a fault or an idea, on purpose
/// not split into two forms.
///
/// Splitting them asks the reporter to classify their own problem before they
/// have described it, and the answer is wrong about a third of the time: "it
/// would be better if…" is filed as an idea and turns out to be a bug, and "it
/// doesn't work" turns out to be a feature that was never built.
class SupportReport {
  const SupportReport({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorUid,
    required this.device,
    required this.os,
    required this.appVersion,
    required this.status,
    required this.createdAt,
    this.kind = SupportReportKind.unsorted,
    this.imagePath,
    this.imageUrl,
    this.lastMessageAt,
    this.lastMessageFromAdmin = false,
  });

  final String id;
  final String text;

  /// The name from the reporter's own profile. Stored on the report rather than
  /// looked up: the developer handling it has no way to read anybody's profile,
  /// and should not have one.
  final String authorName;

  final String authorUid;
  final String device;
  final String os;
  final String appVersion;
  final SupportReportStatus status;
  final DateTime createdAt;

  /// What the reporter said it is about. Absent on every report written before
  /// the chips existed, which reads back as [SupportReportKind.unsorted].
  final SupportReportKind kind;

  /// Where the attached screenshot lives in the bucket, if there is one. Read
  /// with [SupportService.loadScreenshot].
  final String? imagePath;

  /// The token URL older versions stored instead of a path. Kept only so
  /// reports written before [SupportService.loadScreenshot] existed still show
  /// their screenshot in the console; nothing writes it any more, and the
  /// tokens behind these should be revoked in the Firebase console.
  final String? imageUrl;

  /// When the last message in this report's thread was written, and whether it
  /// came from the administrator.
  ///
  /// Kept **on the report** rather than worked out from the thread, so listing
  /// "which of my reports has an answer waiting?" is one query over reports
  /// instead of one read per report per app open. Null on a report nobody has
  /// answered yet, which is most of them.
  final DateTime? lastMessageAt;
  final bool lastMessageFromAdmin;

  /// Whether there is a thread here at all.
  bool get hasConversation => lastMessageAt != null;

  /// A trimmed string, or null when the field is absent or blank. Blank and
  /// missing mean the same thing here and must not read differently.
  static String? _text(Object? value) {
    final String text = (value as String?)?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static SupportReport? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      return null;
    }
    final Object? createdAt = data['createdAt'];
    return SupportReport(
      id: doc.id,
      text: text.trim(),
      authorName: (data['authorName'] as String?)?.trim() ?? '',
      authorUid: (data['authorUid'] as String?) ?? '',
      device: (data['device'] as String?) ?? '',
      os: (data['os'] as String?) ?? '',
      appVersion: (data['appVersion'] as String?) ?? '',
      status: SupportReportStatus.byName(data['status'] as String?),
      kind: SupportReportKind.byName(data['kind'] as String?),
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      imagePath: _text(data['imagePath']),
      imageUrl: _text(data['imageUrl']),
      lastMessageAt: data['lastMessageAt'] is Timestamp
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
      lastMessageFromAdmin: data['lastMessageFromAdmin'] == true,
    );
  }
}

/// One line of the conversation hanging off a report.
///
/// **A report used to be a one-way message.** Somebody described a problem, it
/// landed in the console, and there was no way to ask "which screen?" without
/// their email address — which most reports do not carry, because most accounts
/// are anonymous. So a report now has a thread: the administrator writes back
/// into it, the person who sent the report sees the answer in their own app,
/// and both sides are talking about the report they are both looking at.
///
/// [fromAdmin] is what tells the two apart on screen. It is written by whoever
/// sends, and `firestore.rules` refuses a message that claims to be from an
/// administrator unless the token behind it is one.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.text,
    required this.fromAdmin,
    required this.authorName,
    required this.createdAt,
  });

  final String id;
  final String text;
  final bool fromAdmin;

  /// Who wrote it, for the line above the bubble. The administrator's side is
  /// deliberately generic — "צוות שדכן" — because a support answer is from the
  /// app, not from a named person whose address is then in somebody's hands.
  final String authorName;

  final DateTime createdAt;

  static SupportMessage? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      return null;
    }
    final Object? createdAt = data['createdAt'];
    return SupportMessage(
      id: doc.id,
      text: text.trim(),
      fromAdmin: data['fromAdmin'] == true,
      authorName: (data['authorName'] as String?)?.trim() ?? '',
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// One published "מה חדש?" note.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime publishedAt;

  static Announcement? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? title = data['title'];
    if (title is! String || title.trim().isEmpty) {
      return null;
    }
    final Object? publishedAt = data['publishedAt'];
    return Announcement(
      id: doc.id,
      title: title.trim(),
      body: (data['body'] as String?)?.trim() ?? '',
      publishedAt: publishedAt is Timestamp
          ? publishedAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// The support layer: reports in, announcements out, and the list of who is
/// allowed to see either.
///
/// Three flat collections outside `users/{uid}`, for the same reason `tips` is
/// one: they are shared by construction. **Nothing about a candidate is ever
/// written here** — a report carries the reporter's own name, their own words,
/// a screenshot they chose, and three facts about their phone.
///
/// Every permission is enforced in `firestore.rules`, not here. The checks in
/// this file decide what to *draw*; the rules decide what may be read and
/// written, so a patched client gets permission errors rather than data.
abstract final class SupportService {
  static const String reportsCollection = 'supportReports';
  static const String announcementsCollection = 'announcements';
  static const String adminsCollection = 'supportAdmins';

  /// The account that can add and remove the others. Mirrored in
  /// `firestore.rules`; it is the one administrator that cannot be removed from
  /// inside the app, so there is always a way back in.
  static const String rootAdminEmail = 'yitz292@gmail.com';

  /// A report has to be readable in one sitting by the person answering it.
  static const int maxReportLength = 3000;

  static bool isRootAdmin(String? email) =>
      (email ?? '').trim().toLowerCase() == rootAdminEmail;

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<User?> _requireAccount() async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    return FirebaseAuth.instance.currentUser;
  }

  // --- Reports -------------------------------------------------------------

  /// Sends a report. Returns false when there is no account at all to attach it
  /// to, or when the write was refused.
  ///
  /// An **anonymous** account is accepted here, unlike a tip: most matchmakers
  /// never sign in, and a product that only hears from the fraction who did is
  /// hearing from the wrong fraction. What is lost is the ability to write back
  /// — which is why the form says so.
  static Future<bool> submitReport({
    required String text,
    required String authorName,
    required DeviceFacts facts,
    SupportReportKind kind = SupportReportKind.unsorted,
    File? screenshot,
  }) async {
    final User? user = await _requireAccount();
    final String trimmed = text.trim();
    if (user == null || trimmed.isEmpty) {
      return false;
    }

    try {
      final DocumentReference<Map<String, dynamic>> doc = _db
          .collection(reportsCollection)
          .doc();

      // The image goes up first and under the report's own id, so a failed
      // upload costs the screenshot and not the report — the words are the part
      // that matters, and a report that vanished because a photo would not
      // upload is the worst possible outcome for the person sending it.
      String? imagePath;
      if (screenshot != null && await screenshot.exists()) {
        imagePath = await _uploadScreenshot(doc.id, screenshot);
      }

      await doc.set(<String, Object?>{
        'text': trimmed.length > maxReportLength
            ? trimmed.substring(0, maxReportLength)
            : trimmed,
        'authorName': authorName.trim(),
        'authorUid': user.uid,
        'device': facts.device,
        'os': facts.os,
        'appVersion': facts.appVersion,
        'status': SupportReportStatus.isNew.name,
        'kind': kind.name,
        'createdAt': FieldValue.serverTimestamp(),
        'imagePath': ?imagePath,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads the screenshot and returns its **path in the bucket**, never a
  /// download URL.
  ///
  /// `getDownloadURL()` does not hand back an address — it mints a permanent
  /// access token and bakes it into the URL. Anyone holding that URL can fetch
  /// the file without being signed in, without being an administrator, and
  /// without `storage.rules` being consulted at all, because the token is a
  /// second door that the rules do not stand in front of. The `allow read: if
  /// isSupportAdmin()` rule on this path would have looked like protection and
  /// not been it.
  ///
  /// A screenshot of a bug is, by definition, a picture of the screen the bug
  /// happened on — which in this app is usually a real list of real people. So
  /// the path is stored instead, and [loadScreenshot] reads the bytes through
  /// the SDK under the administrator's own credentials, which is the door the
  /// rules do guard.
  static Future<String?> _uploadScreenshot(String reportId, File file) async {
    try {
      final String extension = file.path.split('.').last.toLowerCase();
      final String path =
          'supportReports/$reportId.${extension.isEmpty ? 'jpg' : extension}';
      await FirebaseStorage.instance
          .ref(path)
          .putFile(
            file,
            SettableMetadata(
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
            ),
          );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Reads an attached screenshot for the feedback console.
  ///
  /// Authenticated: the request carries the caller's token, so `storage.rules`
  /// refuses it for anybody who is not an administrator. Returns null rather
  /// than throwing — a screenshot that will not load is a smaller problem than
  /// a console that will not open.
  static Future<Uint8List?> loadScreenshot(String path) async {
    if (path.trim().isEmpty) {
      return null;
    }
    try {
      // The same ceiling `storage.rules` puts on the upload, so a file that
      // was allowed in can always be read back out.
      return await FirebaseStorage.instance.ref(path).getData(12 * 1024 * 1024);
    } catch (_) {
      return null;
    }
  }

  /// The newest reports. Refused by the rules for anyone but an administrator.
  ///
  /// **The `orderBy` is the whole point of this query, not decoration.** It
  /// used to take `.limit(300)` with no ordering at all and sort the result on
  /// the device — which reads as "the newest 300, sorted" and is not. Without
  /// an `orderBy`, Firestore returns documents in document-id order, and these
  /// ids are random. So the console showed 300 *arbitrary* reports, neatly
  /// sorted, and past that number a report sent this morning could simply
  /// never appear.
  static Future<List<SupportReport>> fetchReports() async {
    if (await _requireAccount() == null) {
      return const <SupportReport>[];
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
        .collection(reportsCollection)
        .orderBy('createdAt', descending: true)
        .limit(300)
        .get();
    // No client-side sort any more: the server has already ordered these, and
    // a second sort here would only hide it if the ordering were ever lost.
    return <SupportReport>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (SupportReport.fromDocument(doc) case final SupportReport report)
          report,
    ];
  }

  static Future<bool> setReportStatus(
    String reportId,
    SupportReportStatus status,
  ) async {
    if (await _requireAccount() == null) {
      return false;
    }
    try {
      await _db.collection(reportsCollection).doc(reportId).update(
        <String, Object?>{
          'status': status.name,
          'reviewedAt': FieldValue.serverTimestamp(),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- The conversation on a report ---------------------------------------

  /// Where a report's thread lives: `supportReports/{id}/messages`.
  static const String messagesCollection = 'messages';

  /// What the administrator's side of a thread signs itself.
  ///
  /// Not a person's name and not an address. Whoever is on rota answers as the
  /// app, so nobody's personal details end up in a stranger's copy of a
  /// conversation, and so a reviewer leaving does not orphan a thread.
  static const String adminDisplayName = 'צוות שדכן';

  /// The reports this account sent, newest first — the reporter's own side of
  /// the console.
  ///
  /// A reporter could not read back even their own report until there was
  /// something to read back *for*. Now there is: an administrator can write
  /// into a thread, and an answer nobody can see is not an answer. The rule
  /// that allows it is still narrow — `authorUid == request.auth.uid`, one
  /// person's own submissions and nobody else's.
  static Future<List<SupportReport>> fetchMyReports({int limit = 20}) async {
    final User? user = await _requireAccount();
    if (user == null) {
      return const <SupportReport>[];
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(reportsCollection)
          .where('authorUid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return <SupportReport>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          if (SupportReport.fromDocument(doc) case final SupportReport report)
            report,
      ];
    } catch (_) {
      return const <SupportReport>[];
    }
  }

  /// One report's whole thread, oldest first — the order a conversation is
  /// read in.
  static Future<List<SupportMessage>> fetchMessages(String reportId) async {
    if (await _requireAccount() == null) {
      return const <SupportMessage>[];
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(reportsCollection)
          .doc(reportId)
          .collection(messagesCollection)
          .orderBy('createdAt')
          .limit(200)
          .get();
      return <SupportMessage>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          if (SupportMessage.fromDocument(doc) case final SupportMessage note)
            note,
      ];
    } catch (_) {
      return const <SupportMessage>[];
    }
  }

  /// Writes one message into a report's thread.
  ///
  /// The report document's `lastMessageAt` is stamped in the same breath. That
  /// denormalised pair is what makes "has anybody answered me?" a single query
  /// on both sides — see [SupportReport.lastMessageAt] — and it is written with
  /// `merge` so a message can never overwrite the report it hangs off.
  ///
  /// [fromAdmin] is claimed by the client and *checked on the server*: the rule
  /// refuses a message marked as coming from an administrator unless the token
  /// sending it belongs to one.
  static Future<bool> sendMessage({
    required String reportId,
    required String text,
    required bool fromAdmin,
    String authorName = '',
  }) async {
    final User? user = await _requireAccount();
    final String trimmed = text.trim();
    if (user == null || trimmed.isEmpty) {
      return false;
    }
    final String capped = trimmed.length > maxMessageLength
        ? trimmed.substring(0, maxMessageLength)
        : trimmed;
    try {
      final DocumentReference<Map<String, dynamic>> report = _db
          .collection(reportsCollection)
          .doc(reportId);
      await report.collection(messagesCollection).add(<String, Object?>{
        'text': capped,
        'fromAdmin': fromAdmin,
        'authorUid': user.uid,
        'authorName': fromAdmin ? adminDisplayName : authorName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await report.set(<String, Object?>{
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageFromAdmin': fromAdmin,
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A message has to be readable in a chat bubble.
  static const int maxMessageLength = 1500;

  // --- Administrators ------------------------------------------------------

  /// The extra administrators, by address. The root address is not in here and
  /// cannot be removed.
  static Future<List<String>> fetchAdmins() async {
    if (await _requireAccount() == null) {
      return const <String>[];
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(adminsCollection)
          .limit(50)
          .get();
      final List<String> emails = <String>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          doc.id,
      ]..sort();
      return emails;
    } catch (_) {
      return const <String>[];
    }
  }

  /// Whether [email] is an administrator — the root address, or one that has
  /// been added to the collection. Used to decide what to draw; the rules ask
  /// the same question of the verified token.
  static Future<bool> isAdmin(String? email) async {
    final String normalized = normalizeEmail(email ?? '');
    if (normalized.isEmpty) {
      return false;
    }
    if (isRootAdmin(normalized)) {
      return true;
    }
    if (await _requireAccount() == null) {
      return false;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await _db
          .collection(adminsCollection)
          .doc(normalized)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Adds an administrator by address. The document id *is* the address, so
  /// adding the same person twice is not a thing that can happen.
  static Future<bool> addAdmin(String email) async {
    final User? user = await _requireAccount();
    final String normalized = normalizeEmail(email);
    if (user == null || !normalized.contains('@')) {
      return false;
    }
    try {
      await _db.collection(adminsCollection).doc(normalized).set(
        <String, Object?>{
          'addedBy': user.email ?? user.uid,
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeAdmin(String email) async {
    if (await _requireAccount() == null) {
      return false;
    }
    final String normalized = normalizeEmail(email);
    if (isRootAdmin(normalized)) {
      return false;
    }
    try {
      await _db.collection(adminsCollection).doc(normalized).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Announcements -------------------------------------------------------

  /// The newest published note, or null when there is none.
  ///
  /// Ordered and limited on the server: this runs on app open, for everybody,
  /// and it must cost one small document rather than the whole collection.
  static Future<Announcement?> fetchLatestAnnouncement() async {
    if (await _requireAccount() == null) {
      return null;
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(announcementsCollection)
          .orderBy('publishedAt', descending: true)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) {
        return null;
      }
      return Announcement.fromDocument(snapshot.docs.first);
    } catch (_) {
      return null;
    }
  }

  /// Every published note, newest first — the administrator's own list.
  static Future<List<Announcement>> fetchAnnouncements() async {
    if (await _requireAccount() == null) {
      return const <Announcement>[];
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(announcementsCollection)
          .orderBy('publishedAt', descending: true)
          .limit(50)
          .get();
      return <Announcement>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          if (Announcement.fromDocument(doc) case final Announcement note) note,
      ];
    } catch (_) {
      return const <Announcement>[];
    }
  }

  static Future<bool> publishAnnouncement({
    required String title,
    required String body,
  }) async {
    if (await _requireAccount() == null) {
      return false;
    }
    final String trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return false;
    }
    try {
      await _db.collection(announcementsCollection).add(<String, Object?>{
        'title': trimmedTitle,
        'body': body.trim(),
        'publishedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteAnnouncement(String id) async {
    if (await _requireAccount() == null) {
      return false;
    }
    try {
      await _db.collection(announcementsCollection).doc(id).delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
