import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/read_throttle.dart';
import 'package:shadchan/services/telemetry.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_tags.dart';

/// How far [PersonalCardService.publishCard] got.
enum CardPublish {
  /// Nothing reached the server.
  failed,

  /// The card is on the server, but a photo was not on this device yet.
  missingPhotos,

  /// The server holds exactly this card, every photo included.
  complete;

  bool get reachedServer => this != CardPublish.failed;
}

/// The fields of a personal card that travel to the matchmakers its owner
/// approves — and nothing else.
///
/// **A whitelist, mirrored in `firestore.rules`.** A card is edited on the
/// same page as a friend in a matchmaker's database, and that page also
/// holds things that must never leave the device they were written on: a
/// matchmaker's private notes, the go-between's number, the database's own
/// bookkeeping. Listing what *may* go is the only way a field added to
/// [Person] later cannot start travelling by accident.
abstract final class PersonalCardCodec {
  /// The fewest words of card text a live card carries.
  static const int minWords = 20;

  /// The most photos a card carries — also enforced by `firestore.rules`.
  static const int maxPhotos = 4;

  /// Words in [text]: whitespace-separated runs, exactly as `firestore.rules`
  /// (`activeCard`) and `functions/src/card_activity.ts` count them.
  static int wordCount(String? text) {
    final String trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// **A card is live only with both a photo and [minWords] words of text.**
  ///
  /// Until then it is a draft: no matchmaker is told about it, it is not on
  /// anybody's "חברים שלי שהוסיפו כרטיס אישי", and nobody can ask for access
  /// to it — a name and a picture, or a paragraph with no face, is not yet a
  /// card a matchmaker can think about. The server holds the same line
  /// (`isActiveCard` in the functions, `activeCard` in the rules), so a client
  /// that drew it differently could still not announce a draft.
  static bool isActive(Person card) =>
      card.photosPaths.isNotEmpty && wordCount(card.description) >= minWords;

  /// What a draft card still lacks, in the owner's words — or null when the
  /// card is live. Both conditions are named when both are missing, so the
  /// owner is never told "add a photo", does so, and only then learns about
  /// the words.
  static String? draftHint(Person card) {
    if (isActive(card)) {
      return null;
    }
    final bool photo = card.photosPaths.isNotEmpty;
    final int missingWords = minWords - wordCount(card.description);
    final String words = missingWords == 1
        ? 'עוד מילה אחת'
        : 'עוד $missingWords מילים';
    final String need = !photo && missingWords > 0
        ? 'להוסיף תמונה אחת לפחות ו־$words בטקסט הכרטיס'
        : !photo
        ? 'להוסיף תמונה אחת לפחות'
        : '$words בטקסט הכרטיס';
    return 'הכרטיס עדיין בטיוטה ולא מוצג לשדכנים. כדי להפעיל אותו צריך $need '
        '(לפחות תמונה אחת ו־$minWords מילים).';
  }

  static const List<String> cardFields = <String>[
    'firstName',
    'lastName',
    'gender',
    'dateOfBirth',
    'religiousLevel',
    'religiousLevelOther',
    'city',
    'description',
    'heightCm',
    'maritalStatus',
    'region',
    'preferredMinAge',
    'preferredMaxAge',
    'preferredMinHeightCm',
    'preferredMaxHeightCm',
    'preferredRegions',
    'preferredMaritalStatuses',
    'preferredReligiousLevels',
    'preferredReligiousLevelOtherLabels',
  ];

  /// The document written to `personalCards/{uid}`.
  static Map<String, Object?> toRemote(
    Person card, {
    required String ownerUid,
    required List<String> photoPaths,
    bool photosShareable = true,
  }) {
    return <String, Object?>{
      'ownerUid': ownerUid,
      ...cardValues(card),
      'photoPaths': photoPaths,
      // "התמונה שלי לא ניתנת לשיתוף": matchmakers see the photos inside the
      // app; their app never attaches them to a share. See CardPhotoPrivacy.
      'photosShareable': photosShareable,
      // The tags the owner chose to describe themselves, from the shared
      // list (`TagCatalog`). Kept apart from [cardFields]: on a matchmaker's
      // copy they are merged with the matchmaker's own private tags rather
      // than replacing them — see [mergeTags].
      'tags': tagsOf(<String, Object?>{'tags': card.tags}),
      // Kept apart from the card's fields because it behaves differently: a
      // matchmaker's own status for the friend stands until the owner's
      // status actually changes.
      'status': card.profileStatus.name,
      'deleted': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Just the card's own fields ([cardFields]) of [card], encoded exactly as
  /// the document carries them — so a matchmaker's copy can be compared with
  /// what the owner sent, field by field.
  static Map<String, Object?> cardValues(Person card) {
    final DateTime? born = card.birthDate;
    return <String, Object?>{
      'firstName': card.firstName.trim(),
      'lastName': card.lastName.trim(),
      'gender': card.gender.name,
      // A plain date, not a timestamp: a birthday has no time zone, and the
      // Hebrew birthday is computed on the server from exactly this.
      'dateOfBirth': born == null
          ? null
          : '${born.year.toString().padLeft(4, '0')}-'
                '${born.month.toString().padLeft(2, '0')}-'
                '${born.day.toString().padLeft(2, '0')}',
      'religiousLevel': card.religiousLevel?.name,
      'religiousLevelOther': card.religiousLevelOther,
      'city': card.city,
      'description': card.description,
      'heightCm': card.heightCm,
      'maritalStatus': card.maritalStatus?.name,
      'region': card.region?.name,
      'preferredMinAge': card.preferredMinAge,
      'preferredMaxAge': card.preferredMaxAge,
      'preferredMinHeightCm': card.preferredMinHeightCm,
      'preferredMaxHeightCm': card.preferredMaxHeightCm,
      'preferredRegions': <String>[
        for (final Region region in card.preferredRegions) region.name,
      ],
      'preferredMaritalStatuses': <String>[
        for (final MaritalStatus status in card.preferredMaritalStatuses)
          status.name,
      ],
      'preferredReligiousLevels': <String>[
        for (final ReligiousLevel level in card.preferredReligiousLevels)
          level.name,
      ],
      'preferredReligiousLevelOtherLabels': List<String>.from(
        card.preferredReligiousLevelOtherLabels,
      ),
    };
  }

  static T? _enum<T extends Enum>(List<T> values, Object? name) {
    for (final T value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }

  static List<T> _enums<T extends Enum>(List<T> values, Object? names) {
    if (names is! List) {
      return <T>[];
    }
    return <T>[
      for (final Object? name in names)
        if (_enum(values, name) != null) _enum(values, name)!,
    ];
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static String? _string(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Copies the card's fields from [data] onto [target], leaving everything
  /// that belongs to the matchmaker — notes, reminders, the go-between, the
  /// phone number they saved — exactly as it was.
  static void applyTo(Person target, Map<String, dynamic> data) {
    final Object? born = data['dateOfBirth'];
    target
      ..firstName = _string(data['firstName']) ?? target.firstName
      ..lastName = _string(data['lastName']) ?? target.lastName
      ..gender = _enum(Gender.values, data['gender']) ?? target.gender
      ..birthDate = born is String ? DateTime.tryParse(born) : null
      ..religiousLevel = _enum(ReligiousLevel.values, data['religiousLevel'])
      ..religiousLevelOther = _string(data['religiousLevelOther'])
      ..city = _string(data['city'])
      ..description = _string(data['description'])
      ..heightCm = _int(data['heightCm'])
      ..maritalStatus = _enum(MaritalStatus.values, data['maritalStatus'])
      ..region = _enum(Region.values, data['region'])
      ..preferredMinAge = _int(data['preferredMinAge'])
      ..preferredMaxAge = _int(data['preferredMaxAge'])
      ..preferredMinHeightCm = _int(data['preferredMinHeightCm'])
      ..preferredMaxHeightCm = _int(data['preferredMaxHeightCm'])
      ..preferredRegions = _enums(Region.values, data['preferredRegions'])
      ..preferredMaritalStatuses = _enums(
        MaritalStatus.values,
        data['preferredMaritalStatuses'],
      )
      ..preferredReligiousLevels = _enums(
        ReligiousLevel.values,
        data['preferredReligiousLevels'],
      )
      ..preferredReligiousLevelOtherLabels = <String>[
        for (final Object? label
            in (data['preferredReligiousLevelOtherLabels'] as List?) ??
                const <Object?>[])
          if (label is String && label.trim().isNotEmpty) label.trim(),
      ];
    if (born != null && target.birthDate != null) {
      // The card's date of birth is the age; a manual age beside it could
      // only disagree with it.
      target.setManualAge(null);
    }
  }

  /// The most tags a card carries.
  static const int maxTags = 12;

  /// The tags in a card document (or a baseline of one), cleaned.
  static List<String> tagsOf(Map<String, dynamic> data) {
    final Object? raw = data['tags'];
    if (raw is! List) {
      return <String>[];
    }
    final Set<String> seen = <String>{};
    final List<String> tags = <String>[];
    for (final Object? item in raw) {
      if (item is! String) continue;
      final String tag = PersonTags.normalize(item);
      if (tag.isEmpty ||
          tag.length > PersonTags.maxLength ||
          !seen.add(PersonTags.keyOf(tag))) {
        continue;
      }
      tags.add(tag);
      if (tags.length >= maxTags) break;
    }
    return tags;
  }

  /// The matchmaker's tags on a friend after the owner's card moved from
  /// [previousRemote] to [remote]: the matchmaker's own private tags stay,
  /// tags the owner removed go, tags the owner added arrive.
  static List<String> mergeTags({
    required List<String> local,
    required List<String> previousRemote,
    required List<String> remote,
  }) {
    final Set<String> removed = <String>{
      for (final String tag in previousRemote) PersonTags.keyOf(tag),
    }..removeAll(remote.map(PersonTags.keyOf));
    final Set<String> seen = <String>{};
    return <String>[
      for (final String tag in local)
        if (!removed.contains(PersonTags.keyOf(tag)) &&
            seen.add(PersonTags.keyOf(tag)))
          tag,
      for (final String tag in remote)
        if (seen.add(PersonTags.keyOf(tag))) tag,
    ];
  }

  /// The owner's own status, read on its own — it keeps arriving even after
  /// a matchmaker stops syncing the rest of the card.
  static ProfileStatus? statusOf(Map<String, dynamic> data) =>
      _enum(ProfileStatus.values, data['status']);
}

/// Everything the personal card does on the server, from the device's side.
///
/// Every call returns quietly when there is no durable account or no Firebase:
/// the card is always saved on the device first (see [PersonalCardProvider]),
/// and publishing is retried on the next app open.
abstract final class PersonalCardService {
  static const String cardsCollection = 'personalCards';
  static const String accessCollection = 'cardAccess';
  static const String directoryCollection = 'phoneDirectory';
  static const String userPhonesCollection = 'userPhones';
  static const String contactsCollection = 'contactHashes';
  static const String tokensCollection = 'fcmTokens';

  /// The photos already in Storage, by basename, so an edit that changes one
  /// word does not upload the gallery again.
  static const String _uploadedKey = 'personalCard.uploadedPhotos';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The signed-in, non-anonymous account, or null.
  static Future<String?> durableUid() async {
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

  /// The id of the access document between [ownerUid] and [matchmakerUid].
  /// One document per pair, named by both, so a request and a grant can never
  /// exist twice and the rules can find it without a query.
  static String accessId(String ownerUid, String matchmakerUid) =>
      '${ownerUid}_$matchmakerUid';

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static Set<String> _uploaded() {
    final Object? raw = _settings?.get(_uploadedKey);
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  static Future<bool> _existsInStorage(Reference ref) async {
    try {
      await ref.getMetadata();
      return true;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return false;
      }
      rethrow;
    }
  }

  /// Downloads one photo of [ownerUid]'s card into [target], through
  /// [partial] so a cut-off write never leaves a file that looks like a
  /// cached photo. True when [target] now holds it.
  ///
  /// **Storage first, then the server.** The direct read is decided by the
  /// Storage rule, which has to consult Firestore across services — an IAM
  /// grant and a per-request read budget that, when either is missing,
  /// refuse every matchmaker and leave them with a card's text and none of
  /// its photos. When the direct read is refused the `cardPhoto` function is
  /// asked instead: it checks the same grant the card's text is read under,
  /// with no cross-service dependency, and returns the bytes.
  static Future<bool> fetchCardPhoto({
    required String ownerUid,
    required String remotePath,
    required File partial,
    required File target,
    void Function(Object error)? log,
  }) async {
    Future<void> settle() async {
      if (await partial.length() == 0) {
        throw StateError('Empty card photo');
      }
      await partial.rename(target.path);
    }

    Future<void> discard() async {
      if (await partial.exists()) await partial.delete();
    }

    bool tryServer = true;
    // Twice, a moment apart: a cut-off mobile connection is the common
    // reason a card arrives with its text and without its pictures.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        await FirebaseStorage.instance.ref(remotePath).writeToFile(partial);
        await settle();
        return true;
      } catch (error) {
        await discard();
        log?.call(error);
        if (error is FirebaseException) {
          // Not in Storage at all: the server has nothing better to offer.
          if (error.code == 'object-not-found') {
            tryServer = false;
            break;
          }
          // Refused is refused; trying again a second later changes nothing.
          if (error.code == 'unauthorized' ||
              error.code == 'permission-denied') {
            break;
          }
        }
      }
    }
    if (!tryServer) {
      return false;
    }
    try {
      Telemetry.meter(functions: 1);
      final HttpsCallableResult<dynamic>
      result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            'cardPhoto',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          )
          .call(<String, Object?>{'ownerUid': ownerUid, 'path': remotePath});
      final Object? data = result.data;
      final Object? encoded = data is Map ? data['data'] : null;
      if (encoded is! String || encoded.isEmpty) {
        return false;
      }
      await partial.writeAsBytes(base64Decode(encoded), flush: true);
      await settle();
      return true;
    } catch (error) {
      await discard();
      log?.call(error);
      return false;
    }
  }

  /// Uploads the card's photos and writes the card document.
  ///
  /// [CardPublish.complete] when the server now holds exactly this card,
  /// photos included. [CardPublish.missingPhotos] when the document went up
  /// but a photo of the card was not on this device to upload — typically a
  /// second phone of the same account, where the account sync has brought the
  /// card's text and is still downloading its pictures. The text is worth
  /// sending at once; the publish is simply not finished, and the caller must
  /// not remember it as done, or the matchmakers keep a card without its
  /// photos until the owner next edits it.
  static Future<CardPublish> publishCard(Person card) async {
    final String? uid = await durableUid();
    if (uid == null) {
      return CardPublish.failed;
    }
    try {
      final Reference root = FirebaseStorage.instance.ref(
        '$cardsCollection/$uid',
      );
      final Set<String> uploaded = _uploaded();
      final List<String> remotePaths = <String>[];
      bool missing = false;
      final Set<String> seen = <String>{};
      for (final String localPath in card.photosPaths) {
        if (remotePaths.length >= PersonalCardCodec.maxPhotos) {
          break;
        }
        final String name = PhotoPickerService.basenameOf(localPath);
        if (!seen.add(name)) {
          continue;
        }
        // The stored path is absolute, and iOS moves the app's sandbox on an
        // update: a photo that is still there under a new prefix must not be
        // left off the card the matchmakers receive.
        File file = File(localPath);
        if (!file.existsSync()) {
          file = await PhotoPickerService.fileFor(name);
        }
        // **What is in Storage is checked, never assumed.** The ledger of
        // what this phone uploaded said "done" for photos that were not
        // there — uploaded under an account since signed out of, removed by
        // another phone, lost to a failed write — and the card then listed
        // photos no matchmaker could ever fetch. One metadata read per photo
        // per publish costs little; a card without its face costs the card.
        // It also lets a phone that has not received a photo file yet keep
        // it on the card when Storage already holds it.
        final Reference ref = root.child(name);
        final bool onServer = await _existsInStorage(ref);
        if (!onServer) {
          if (!file.existsSync() || file.lengthSync() == 0) {
            missing = true;
            continue;
          }
          await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
        }
        uploaded.add(name);
        remotePaths.add('$cardsCollection/$uid/$name');
      }
      // A photo the owner took off the card comes down from Storage too — it
      // is their face, and "removed" has to mean removed.
      final Set<String> current = <String>{
        for (final String path in remotePaths) path.split('/').last,
      };
      for (final String name in uploaded.difference(current).toList()) {
        try {
          await root.child(name).delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') {
            rethrow;
          }
        }
        uploaded.remove(name);
      }
      await _settings?.put(_uploadedKey, uploaded.toList());

      await _db
          .collection(cardsCollection)
          .doc(uid)
          .set(
            PersonalCardCodec.toRemote(
              card,
              ownerUid: uid,
              photoPaths: remotePaths,
              photosShareable: PersonalCardProvider.photosShareableIn(
                _settings,
              ),
            ),
            SetOptions(merge: true),
          );
      return missing ? CardPublish.missingPhotos : CardPublish.complete;
    } catch (error, stackTrace) {
      debugPrint('PersonalCardService.publishCard failed: $error');
      debugPrint('$stackTrace');
      return CardPublish.failed;
    }
  }

  /// Marks the card deleted — kept, never erased, so it can be restored.
  /// The rules stop every matchmaker reading a deleted card at once.
  static Future<bool> setCardDeleted(bool deleted) async {
    final String? uid = await durableUid();
    if (uid == null) {
      return false;
    }
    try {
      await _db.collection(cardsCollection).doc(uid).update(<String, Object?>{
        'deleted': deleted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (error) {
      // A card that never reached the server has nothing there to flag.
      if (error.code == 'not-found') {
        return true;
      }
      debugPrint('PersonalCardService.setCardDeleted failed: $error');
      return false;
    } catch (error) {
      debugPrint('PersonalCardService.setCardDeleted failed: $error');
      return false;
    }
  }

  /// Publishes who this account is, by phone: the lookup a matchmaker's copy
  /// of a friend uses to find the friend's card, and the one a card owner's
  /// address book uses to find the matchmakers in it.
  ///
  /// [previousHash] is the entry to take down when the number changed.
  static Future<bool> publishIdentity({
    required String phoneHash,
    required String name,
    required bool matchmaker,
    required bool hasCard,
    bool acceptsRequests = true,
    bool announces = true,
    String? previousHash,
  }) async {
    final String? uid = await durableUid();
    if (uid == null) {
      return false;
    }
    try {
      final WriteBatch batch = _db.batch();
      if (previousHash != null && previousHash != phoneHash) {
        batch.delete(_db.collection(directoryCollection).doc(previousHash));
      }
      batch.set(
        _db.collection(directoryCollection).doc(phoneHash),
        <String, Object?>{
          'uid': uid,
          'name': name,
          'matchmaker': matchmaker,
          'hasCard': hasCard,
          // Off: no matchmaker may ask, and the card shows to none of them —
          // see `CardInviteFlow.cardVisible`. The rules enforce the asking.
          'acceptsRequests': acceptsRequests,
          // Off: no matchmaker is told the card exists (`announceOnce`).
          'announces': announces,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.set(
        _db.collection(userPhonesCollection).doc(uid),
        <String, Object?>{
          'phoneHash': phoneHash,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
      return true;
    } catch (error) {
      debugPrint('PersonalCardService.publishIdentity failed: $error');
      return false;
    }
  }

  /// Who owns [phoneHash], if anybody has published it.
  static Future<Map<String, dynamic>?> lookup(String phoneHash) async {
    if (await durableUid() == null) {
      return null;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _db
          .collection(directoryCollection)
          .doc(phoneHash)
          .get();
      return snapshot.data();
    } catch (error) {
      debugPrint('PersonalCardService.lookup failed: $error');
      return null;
    }
  }

  /// The card owner's address book, as hashes only. The server checks a
  /// matchmaker's access request against it: only somebody saved in the
  /// owner's contacts may ask.
  static Future<bool> publishContactHashes(Iterable<String> hashes) async {
    final String? uid = await durableUid();
    if (uid == null) {
      return false;
    }
    final List<String> unique = hashes.toSet().toList()..sort();
    try {
      await _db.collection(contactsCollection).doc(uid).set(<String, Object?>{
        'hashes': unique,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (error) {
      debugPrint('PersonalCardService.publishContactHashes failed: $error');
      return false;
    }
  }

  /// Current database size and an actual foreground/activity timestamp.
  /// Readable only by this account and its explicitly approved card owners.
  ///
  /// **At most once an hour** ([activityEvery]), or ten minutes after the
  /// last one when the database size changed ([activityCountEvery]). It used
  /// to be written on every open, resume, exit and burst of edits — ~25 times
  /// a day per matchmaker — and every write woke a server trigger that read
  /// thousands of documents (2026-11-22). "Last active" is shown to the hour
  /// at best, so an hour is all the precision it needs.
  static Future<void> publishActivity(
    int databaseCount, {
    DateTime? now,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final DateTime at = now ?? DateTime.now();
    if (!activityWorthWriting(
      last: ReadThrottle.lastAt(_activityClock),
      lastCount: ReadThrottle.value(_activityClock),
      count: databaseCount,
      now: at,
    )) {
      return;
    }
    final uid = await durableUid();
    if (uid == null) return;
    // Marked before the write, so the two callers of an app open cannot both
    // send one; taken back if the write fails.
    ReadThrottle.mark(_activityClock, at: at, value: '$databaseCount');
    try {
      await _db.doc('matchmakerActivity/$uid').set({
        'databaseCount': databaseCount,
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      ReadThrottle.mark(
        _activityClock,
        at: DateTime.fromMillisecondsSinceEpoch(0),
        value: '',
      );
      debugPrint('Matchmaker activity was not refreshed: $error');
    }
  }

  static const String _activityClock = 'activity';

  /// "Last active" is refreshed at most this often.
  static const Duration activityEvery = Duration(hours: 1);

  /// ...or this soon, when the database size moved.
  static const Duration activityCountEvery = Duration(minutes: 10);

  /// Whether [publishActivity] should write now.
  @visibleForTesting
  static bool activityWorthWriting({
    required DateTime? last,
    required String? lastCount,
    required int count,
    required DateTime now,
  }) {
    if (ReadThrottle.isDue(last: last, every: activityEvery, now: now)) {
      return true;
    }
    return lastCount != '$count' &&
        ReadThrottle.isDue(last: last, every: activityCountEvery, now: now);
  }

  /// Registers this device for push notifications under the account.
  static Future<void> saveDeviceToken(String token) async {
    final String? uid = await durableUid();
    if (uid == null || token.isEmpty) {
      return;
    }
    try {
      await _db.collection(tokensCollection).doc(uid).set(<String, Object?>{
        'tokens': FieldValue.arrayUnion(<String>[token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('PersonalCardService.saveDeviceToken failed: $error');
    }
  }

  /// The kinds of notification switched off in the settings, published where
  /// the server reads them before a push (`notify` in functions/notices.ts,
  /// `sendReminders` in functions/reminders.ts). Pushes only — the inbox row
  /// is still written, and the app hides it.
  static Future<void> saveNotificationMutes(List<String> muted) async {
    final String? uid = await durableUid();
    if (uid == null) {
      return;
    }
    try {
      await _db.collection(tokensCollection).doc(uid).set(<String, Object?>{
        'muted': muted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('PersonalCardService.saveNotificationMutes failed: $error');
    }
  }

  /// Takes this device off the account's push list, for a sign-out.
  static Future<void> removeDeviceToken(String token) async {
    final String? uid = await durableUid();
    if (uid == null || token.isEmpty) {
      return;
    }
    try {
      await _db.collection(tokensCollection).doc(uid).set(<String, Object?>{
        'tokens': FieldValue.arrayRemove(<String>[token]),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('PersonalCardService.removeDeviceToken failed: $error');
    }
  }
}
