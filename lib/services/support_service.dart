import 'dart:io';

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
    this.imageUrl,
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

  /// A screenshot, if one was attached.
  final String? imageUrl;

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
      imageUrl: (data['imageUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : (data['imageUrl'] as String).trim(),
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
      String? imageUrl;
      if (screenshot != null && await screenshot.exists()) {
        imageUrl = await _uploadScreenshot(doc.id, screenshot);
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
        'imageUrl': ?imageUrl,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _uploadScreenshot(String reportId, File file) async {
    try {
      final String extension = file.path.split('.').last.toLowerCase();
      final Reference ref = FirebaseStorage.instance.ref(
        'supportReports/$reportId.${extension.isEmpty ? 'jpg' : extension}',
      );
      await ref.putFile(
        file,
        SettableMetadata(
          contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  /// Every report, newest first. Refused by the rules for anyone but an
  /// administrator.
  static Future<List<SupportReport>> fetchReports() async {
    if (await _requireAccount() == null) {
      return const <SupportReport>[];
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _db
        .collection(reportsCollection)
        .limit(300)
        .get();
    final List<SupportReport> reports = <SupportReport>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (SupportReport.fromDocument(doc) case final SupportReport report)
          report,
    ];
    reports.sort(
      (SupportReport a, SupportReport b) => b.createdAt.compareTo(a.createdAt),
    );
    return reports;
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
