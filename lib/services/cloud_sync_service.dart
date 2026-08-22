import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/profile_backup.dart';
import 'package:shadchan/services/sync_state_store.dart';

/// Mirrors the local database into Firestore, and back again.
///
/// **Hive stays the source of truth.** Nothing here is ever read to answer a
/// question the app asks during normal use: the screens read Hive, the sync
/// pushes Hive upward, and the only downward path is an explicit restore the
/// matchmaker asks for. That is what keeps the app working identically with no
/// network, and what means a Firestore outage can slow a backup but can never
/// show someone a stale candidate.
///
/// The shape in Firestore is one document per record under the signed-in uid:
///
/// ```
/// users/{uid}                 → when the last backup ran, and what it held
/// users/{uid}/people/{id}
/// users/{uid}/personNotes/{id}
/// users/{uid}/matches/{id}
/// users/{uid}/matchNotes/{id}
/// users/{uid}/profile/main    → the matchmaker's own profile
/// ```
///
/// One document per record rather than one big blob, because the blob would
/// have to be rewritten in full for a single edited note, and would eventually
/// meet Firestore's 1MB document ceiling on a large database.
///
/// Photos are the exception the JSON backup never solved: it stored file
/// *paths*, so a restore on a new phone produced people with no faces. Here
/// the files go to Cloud Storage under `users/{uid}/photos/{basename}` and the
/// documents carry basenames, which are rebuilt into local paths on the way
/// back down.
abstract final class CloudSyncService {
  static const String _photosField = 'photos';

  /// The four record collections under `users/{uid}`, named in one place.
  ///
  /// Listed rather than discovered because Firestore cannot enumerate the
  /// subcollections of a document from a client — so an erasure that missed
  /// one would leave it behind silently, for ever. A fifth collection added
  /// later has to be added here too, which is the point.
  static const List<String> _syncedCollections = <String>[
    'people',
    'personNotes',
    'matches',
    'matchNotes',
  ];

  /// Firestore refuses a batch of more than 500 operations.
  static const int _batchLimit = 450;

  /// Guards against the two triggers overlapping. The app syncs on open and on
  /// close, and a quick background-foreground bounce can fire both before the
  /// first has finished; a second concurrent pass would diff against a ledger
  /// the first one is still writing.
  static Future<CloudSyncResult>? _running;

  static bool get isSyncing => _running != null;

  /// Pushes everything that changed since the last sync.
  ///
  /// Never throws. A backup that fails is a line in Settings, not an
  /// interruption — it runs on app open and close, where there is no one to
  /// show an error to and nothing that should be blocked by one.
  static Future<CloudSyncResult> syncNow({
    required PersonRepository personRepo,
    required MatchRepository matchRepo,
    required UserProfileProvider profile,
    required SyncStateStore state,
  }) {
    return _running ??= _run(
      personRepo: personRepo,
      matchRepo: matchRepo,
      profile: profile,
      state: state,
    ).whenComplete(() => _running = null);
  }

  static Future<CloudSyncResult> _run({
    required PersonRepository personRepo,
    required MatchRepository matchRepo,
    required UserProfileProvider profile,
    required SyncStateStore state,
  }) async {
    final String? uid = await _requireAccount();
    if (uid == null) {
      return CloudSyncResult.skipped;
    }

    try {
      final Map<String, Map<String, Object?>> records = _collectRecords(
        personRepo,
        matchRepo,
        profile,
      );

      final Map<String, String> previous = await state.fingerprintsFor(uid);
      final Map<String, String> current = <String, String>{
        for (final MapEntry<String, Map<String, Object?>> entry
            in records.entries)
          entry.key: SyncStateStore.fingerprint(entry.value),
      };

      final List<String> changed = <String>[
        for (final String path in current.keys)
          if (previous[path] != current[path]) path,
      ];
      // Anything the ledger still lists that the database no longer has was
      // deleted locally, and a backup that keeps deleted people is not a
      // mirror of anything.
      final List<String> removed = <String>[
        for (final String path in previous.keys)
          if (!current.containsKey(path) && !path.startsWith('photos/')) path,
      ];

      await _writeDocuments(uid, records, changed, removed);
      await _syncPhotos(uid, records, previous, current);

      // The ledger before and after, compared once. It is the only thing that
      // knows about *every* kind of change: `changed` and `removed` cover the
      // documents, and the photo pass adds and drops entries of its own — a
      // re-cropped photo keeps its basename, so the person's document is
      // untouched and the upload showed up nowhere in the two lists above.
      //
      // Two things hang off it. The meta document is only written when
      // something actually reached the cloud, which takes an unconditional
      // write per app open *and* per app close off every account in the app —
      // four writes a day for a database nobody touched. And a sync that
      // uploaded nothing but a photo now reports `success` rather than
      // `upToDate`, which is what Settings tells the matchmaker.
      final bool uploadedSomething = !mapEquals(previous, current);
      if (uploadedSomething) {
        await _writeMeta(uid, records);
      }
      await state.commit(current);

      debugPrint(
        'CLOUD_SYNC uploaded ${changed.length}, removed ${removed.length}',
      );
      return uploadedSomething
          ? CloudSyncResult.success
          : CloudSyncResult.upToDate;
    } on FirebaseException catch (error) {
      debugPrint('CLOUD_SYNC failed: ${error.code} ${error.message}');
      return error.code == 'permission-denied'
          ? CloudSyncResult.notPermitted
          : CloudSyncResult.failed;
    } catch (error, stackTrace) {
      debugPrint('CLOUD_SYNC failed: $error\n$stackTrace');
      return CloudSyncResult.failed;
    }
  }

  /// Every record in the database, keyed by its Firestore path.
  ///
  /// Photo paths are reduced to basenames on the way out: an absolute path
  /// from this phone's sandbox is meaningless on the next one, and it also
  /// changes on iOS every time the app is reinstalled, which would mark every
  /// person as changed for no reason.
  static Map<String, Map<String, Object?>> _collectRecords(
    PersonRepository personRepo,
    MatchRepository matchRepo,
    UserProfileProvider profile,
  ) {
    final Map<String, Map<String, Object?>> records =
        <String, Map<String, Object?>>{};

    records[ProfileBackup.documentPath] = ProfileBackup.toJson(profile);

    for (final person in personRepo.getAll()) {
      final Map<String, Object?> json = BackupService.personToJson(person);
      json[_photosField] = _basenames(json[_photosField]);
      records['people/${person.id}'] = json;
    }
    for (final note in personRepo.getAllNotes()) {
      records['personNotes/${note.id}'] = BackupService.personNoteToJson(note);
    }
    for (final match in matchRepo.getAll()) {
      records['matches/${match.id}'] = BackupService.matchToJson(match);
    }
    for (final note in matchRepo.getAllNotes()) {
      records['matchNotes/${note.id}'] = BackupService.matchNoteToJson(note);
    }

    return records;
  }

  static Future<void> _writeDocuments(
    String uid,
    Map<String, Map<String, Object?>> records,
    List<String> changed,
    List<String> removed,
  ) async {
    final DocumentReference<Map<String, dynamic>> root = _root(uid);

    for (final List<String> chunk in _chunks(changed)) {
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final String path in chunk) {
        batch.set(root.collection(_collectionOf(path)).doc(_idOf(path)), {
          ...records[path]!,
        });
      }
      await batch.commit();
    }

    for (final List<String> chunk in _chunks(removed)) {
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final String path in chunk) {
        batch.delete(root.collection(_collectionOf(path)).doc(_idOf(path)));
      }
      await batch.commit();
    }
  }

  /// Uploads photo files that are not in the cloud yet, and drops the ones no
  /// record refers to any more.
  ///
  /// Deliberately best-effort and last: photos are far and away the slowest
  /// and largest part of a sync, and a phone that loses its connection halfway
  /// through should keep the documents it already uploaded rather than fail
  /// the whole backup. Whatever did not make it is simply still missing from
  /// the ledger, so the next sync picks it up.
  static Future<void> _syncPhotos(
    String uid,
    Map<String, Map<String, Object?>> records,
    Map<String, String> previous,
    Map<String, String> current,
  ) async {
    final Directory photosDirectory =
        await PhotoPickerService.ensurePhotosDirectory();
    final Reference root = FirebaseStorage.instance.ref('users/$uid/photos');

    final Set<String> referenced = <String>{};
    for (final MapEntry<String, Map<String, Object?>> entry
        in records.entries) {
      if (entry.key == ProfileBackup.documentPath) {
        referenced.addAll(ProfileBackup.photoNames(entry.value));
        continue;
      }
      if (!entry.key.startsWith('people/')) {
        continue;
      }
      final Object? names = entry.value[_photosField];
      if (names is List) {
        referenced.addAll(names.whereType<String>());
      }
    }

    for (final String name in referenced) {
      final String key = 'photos/$name';
      final File file = File(
        '${photosDirectory.path}${Platform.pathSeparator}$name',
      );
      if (!file.existsSync()) {
        // Still referenced by a person, but gone from this phone — a restore
        // whose download failed, or a file the OS reclaimed. Whatever is in
        // the cloud is now the *only* copy, so the ledger entry is carried
        // forward to keep the delete pass below away from it. Dropping the key
        // here is what used to make a missing local file delete the backup of
        // itself.
        if (previous[key] case final String kept) {
          current[key] = kept;
        }
        continue;
      }
      // Length and mtime together: the photo editor rewrites a file in place,
      // and a crop that happens to land on the same byte count still moves the
      // timestamp.
      final FileStat stat = file.statSync();
      final String fingerprint =
          '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
      current[key] = fingerprint;
      if (previous[key] == fingerprint) {
        continue;
      }
      try {
        await root.child(name).putFile(file);
      } catch (error) {
        debugPrint('CLOUD_SYNC photo upload failed for $name: $error');
        // The *old* fingerprint, not none at all. Forgetting the key entirely
        // sent the photo to the delete pass below, so a phone that lost its
        // connection midway through re-uploading an edited photo destroyed the
        // copy it had successfully backed up before — a transient network
        // failure losing a face for good. Keeping the stale fingerprint
        // protects that copy and still differs from the file on disk, so the
        // next sync retries the upload.
        if (previous[key] case final String kept) {
          current[key] = kept;
        } else {
          current.remove(key);
        }
      }
    }

    for (final String key in previous.keys) {
      if (!key.startsWith('photos/') || current.containsKey(key)) {
        continue;
      }
      try {
        await root.child(key.substring('photos/'.length)).delete();
      } catch (error) {
        debugPrint('CLOUD_SYNC photo delete failed for $key: $error');
      }
    }
  }

  static Future<void> _writeMeta(
    String uid,
    Map<String, Map<String, Object?>> records,
  ) async {
    int count(String prefix) {
      return records.keys
          .where((String path) => path.startsWith(prefix))
          .length;
    }

    await _root(uid).set(<String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
      'people': count('people/'),
      'personNotes': count('personNotes/'),
      'matches': count('matches/'),
      'matchNotes': count('matchNotes/'),
      'profile': records.containsKey(ProfileBackup.documentPath),
    }, SetOptions(merge: true));
  }

  // --- Erasure ------------------------------------------------------------

  /// Deletes this account's whole cloud backup — every record, the profile,
  /// and every photo file.
  ///
  /// **The database on this phone is not touched.** Somebody asking to delete
  /// their backup is asking for the copy on the server to be gone, not to lose
  /// their own work; the app carries on exactly as it did before it was ever
  /// connected to an account, and the next sync simply uploads everything
  /// again unless they sign out first.
  ///
  /// Why it exists at all: this is the only permanent copy of other people's
  /// names, telephone numbers, religious level and private notes — people who
  /// are not users of this app, never agreed to anything, and have no way of
  /// knowing it is here. `communityMembers` has had a delete button since the
  /// beginning, and that row is nothing but counters; the sensitive half of
  /// the system had no way to be erased short of writing to the developer.
  ///
  /// Deliberately unlike the rest of this class, it **reports its failures**.
  /// A sync that quietly fails is retried in a minute and costs nothing, but
  /// somebody who has just been told their data is gone must never be told it
  /// wrongly — so a partial deletion answers false and the caller says to try
  /// again.
  static Future<bool> deleteBackup() async {
    final String? uid = await _requireAccount();
    if (uid == null) {
      return false;
    }

    try {
      final DocumentReference<Map<String, dynamic>> root = _root(uid);

      // The records first, then the root document. In that order, an
      // interruption leaves a root document describing a tree that is already
      // gone — which the next sync corrects — rather than orphaned records
      // under no root, which nothing would ever visit again.
      for (final String collection in _syncedCollections) {
        await _deleteCollection(root.collection(collection));
      }
      await _deleteCollection(
        root.collection(ProfileBackup.documentPath.split('/').first),
      );
      await _deletePhotos(uid);
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

  /// Empties one collection, a page at a time.
  ///
  /// Firestore has no recursive delete on the client — that lives in the admin
  /// SDK — so the documents are listed and deleted in batches. Paged rather
  /// than read whole because a large database would otherwise be pulled into
  /// memory in one go just to be thrown away.
  static Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> page = await collection
          .limit(_batchLimit)
          .get();
      if (page.docs.isEmpty) {
        return;
      }
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      // A short page means that was the last of them. Checked after the
      // delete rather than before, so a collection that is an exact multiple
      // of the page size still terminates.
      if (page.docs.length < _batchLimit) {
        return;
      }
    }
  }

  /// Removes every photo this account has in the bucket.
  ///
  /// Listed from Storage rather than derived from the records, deliberately:
  /// a file whose person was deleted locally before the last sync ran, or one
  /// left behind by an interrupted delete, is exactly the file that would
  /// survive an erasure driven by the database — and a face is the last thing
  /// that should outlive the request to remove it.
  static Future<void> _deletePhotos(String uid) async {
    final Reference root = FirebaseStorage.instance.ref('users/$uid/photos');
    ListResult page = await root.list(const ListOptions(maxResults: 100));
    while (true) {
      for (final Reference item in page.items) {
        await item.delete();
      }
      final String? token = page.nextPageToken;
      if (token == null) {
        return;
      }
      page = await root.list(
        ListOptions(maxResults: 100, pageToken: token),
      );
    }
  }

  // --- Restore ------------------------------------------------------------

  /// Pulls the cloud backup down and merges it into Hive.
  ///
  /// Additive, through the same [BackupService.importPayload] the file import
  /// uses: an id that already exists locally is left alone. Restore is
  /// therefore safe to run on a database that is not empty, and it can never
  /// overwrite something the matchmaker has on this phone with an older cloud
  /// copy. The profile follows the same principle one level down, filling
  /// empty fields only — see [ProfileBackup.applyMissing].
  static Future<CloudRestoreOutcome> restore({
    required PersonRepository personRepo,
    required MatchRepository matchRepo,
    required UserProfileProvider profile,
  }) async {
    final String? uid = await _requireAccount();
    if (uid == null) {
      return const CloudRestoreOutcome.failure(CloudSyncResult.skipped);
    }

    try {
      final DocumentReference<Map<String, dynamic>> root = _root(uid);
      final List<Map<String, dynamic>> people = await _readAll(root, 'people');
      final List<Map<String, dynamic>> personNotes = await _readAll(
        root,
        'personNotes',
      );
      final List<Map<String, dynamic>> matches = await _readAll(
        root,
        'matches',
      );
      final List<Map<String, dynamic>> matchNotes = await _readAll(
        root,
        'matchNotes',
      );

      final Map<String, dynamic>? profileJson = await _readProfile(root);

      if (people.isEmpty &&
          personNotes.isEmpty &&
          matches.isEmpty &&
          matchNotes.isEmpty &&
          profileJson == null) {
        return const CloudRestoreOutcome.failure(CloudSyncResult.empty);
      }

      await _downloadPhotos(uid, people);

      final ImportResult result = await BackupService.importPayload(
        <String, dynamic>{
          'people': people,
          'personNotes': personNotes,
          'matches': matches,
          'matchNotes': matchNotes,
        },
        personRepo,
        matchRepo,
      );

      int profileFieldsRestored = 0;
      if (profileJson != null) {
        profileFieldsRestored = await ProfileBackup.applyMissing(
          profile,
          profileJson,
          resolvePhoto: (String basename) => _fetchPhoto(uid, basename),
        );
      }

      return CloudRestoreOutcome.success(result, profileFieldsRestored);
    } on FirebaseException catch (error) {
      debugPrint('CLOUD_RESTORE failed: ${error.code} ${error.message}');
      return CloudRestoreOutcome.failure(
        error.code == 'permission-denied'
            ? CloudSyncResult.notPermitted
            : CloudSyncResult.failed,
      );
    } catch (error, stackTrace) {
      debugPrint('CLOUD_RESTORE failed: $error\n$stackTrace');
      return const CloudRestoreOutcome.failure(CloudSyncResult.failed);
    }
  }

  /// Fetches each person's photos and rewrites the basenames back into paths
  /// on this device.
  ///
  /// A photo that will not download is dropped from the person rather than
  /// left as a path to a file that is not there — the whole reason photos are
  /// in the backup at all is that the JSON export's dangling paths were worse
  /// than nothing.
  static Future<void> _downloadPhotos(
    String uid,
    List<Map<String, dynamic>> people,
  ) async {
    for (final Map<String, dynamic> person in people) {
      final Object? names = person[_photosField];
      if (names is! List) {
        person[_photosField] = <String>[];
        continue;
      }

      final List<String> restored = <String>[];
      for (final String name in names.whereType<String>()) {
        final String? path = await _fetchPhoto(uid, name);
        if (path != null) {
          restored.add(path);
        }
      }
      person[_photosField] = restored;
    }
  }

  /// The profile document, or null when this backup predates it or was never
  /// written. Absence is ordinary, not an error.
  static Future<Map<String, dynamic>?> _readProfile(
    DocumentReference<Map<String, dynamic>> root,
  ) async {
    final String collection = ProfileBackup.documentPath.split('/').first;
    final String id = ProfileBackup.documentPath.split('/').last;
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await root
        .collection(collection)
        .doc(id)
        .get();
    return snapshot.exists ? snapshot.data() : null;
  }

  /// Downloads one photo by basename and returns its local path, or null when
  /// it could not be fetched. A file already on disk is kept as it is — the
  /// basenames are unique per photo, so a match means the same image.
  static Future<String?> _fetchPhoto(String uid, String basename) async {
    final File file = await PhotoPickerService.fileFor(basename);
    if (file.existsSync()) {
      return file.path;
    }
    try {
      await FirebaseStorage.instance
          .ref('users/$uid/photos/$basename')
          .writeToFile(file);
      return file.path;
    } catch (error) {
      debugPrint('CLOUD_RESTORE photo download failed for $basename: $error');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _readAll(
    DocumentReference<Map<String, dynamic>> root,
    String collection,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await root
        .collection(collection)
        .get();
    return <Map<String, dynamic>>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        doc.data(),
    ];
  }

  // --- Plumbing -----------------------------------------------------------

  /// The uid to sync under, or null when there is nothing to sync to.
  ///
  /// An anonymous account is explicitly *not* good enough: it dies with the
  /// install, so a backup written under it could never be restored, and
  /// writing one would be worse than not writing one — it would look like the
  /// database was safe.
  static Future<String?> _requireAccount() async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return null;
    }
    return user.uid;
  }

  static DocumentReference<Map<String, dynamic>> _root(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static List<String> _basenames(Object? paths) {
    if (paths is! List) {
      return <String>[];
    }
    return <String>[
      for (final String path in paths.whereType<String>())
        PhotoPickerService.basenameOf(path),
    ];
  }

  static String _collectionOf(String path) => path.split('/').first;

  static String _idOf(String path) => path.substring(path.indexOf('/') + 1);

  static Iterable<List<String>> _chunks(List<String> paths) sync* {
    for (int start = 0; start < paths.length; start += _batchLimit) {
      yield paths.sublist(
        start,
        start + _batchLimit > paths.length ? paths.length : start + _batchLimit,
      );
    }
  }
}

/// How a sync ended, in the terms the Settings line has to report.
enum CloudSyncResult {
  /// Uploaded at least one change.
  success,

  /// Ran, and there was nothing to send.
  upToDate,

  /// Not signed in, or Firebase never came up. Not an error — the ordinary
  /// state of an app that has not been connected to an account.
  skipped,

  /// The security rules refused the write. Almost always a project that has
  /// not had its rules published yet.
  notPermitted,

  /// The cloud holds no backup to restore from.
  empty,

  failed,
}

class CloudRestoreOutcome {
  const CloudRestoreOutcome.success(
    ImportResult this.result, [
    this.profileFieldsRestored = 0,
  ]) : status = CloudSyncResult.success;

  const CloudRestoreOutcome.failure(this.status)
    : result = null,
      profileFieldsRestored = 0;

  final CloudSyncResult status;

  /// What was merged, on success only.
  final ImportResult? result;

  /// How many empty profile fields the backup filled in. Zero is the normal
  /// answer on a phone whose profile was already complete.
  final int profileFieldsRestored;
}
