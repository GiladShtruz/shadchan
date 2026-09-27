import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';

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
  }) {
    final DateTime? born = card.birthDate;
    return <String, Object?>{
      'ownerUid': ownerUid,
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
      'preferredReligiousLevelOtherLabels':
          card.preferredReligiousLevelOtherLabels,
      'photoPaths': photoPaths,
      // Kept apart from the card's fields because it behaves differently: a
      // matchmaker who stops syncing the card keeps receiving the owner's own
      // status changes.
      'status': card.profileStatus.name,
      'deleted': false,
      'updatedAt': FieldValue.serverTimestamp(),
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

  /// Uploads the card's photos and writes the card document.
  ///
  /// True when the server now holds exactly this card.
  static Future<bool> publishCard(Person card) async {
    final String? uid = await durableUid();
    if (uid == null) {
      return false;
    }
    try {
      final Reference root = FirebaseStorage.instance.ref(
        '$cardsCollection/$uid',
      );
      final Set<String> uploaded = _uploaded();
      final List<String> remotePaths = <String>[];
      for (final String localPath in card.photosPaths) {
        final String name = PhotoPickerService.basenameOf(localPath);
        // The stored path is absolute, and iOS moves the app's sandbox on an
        // update: a photo that is still there under a new prefix must not be
        // left off the card the matchmakers receive.
        File file = File(localPath);
        if (!file.existsSync()) {
          file = await PhotoPickerService.fileFor(name);
        }
        if (!uploaded.contains(name)) {
          if (!file.existsSync()) {
            continue;
          }
          await root
              .child(name)
              .putFile(file, SettableMetadata(contentType: 'image/jpeg'));
          uploaded.add(name);
        }
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
            ),
          );
      return true;
    } catch (error, stackTrace) {
      debugPrint('PersonalCardService.publishCard failed: $error');
      debugPrint('$stackTrace');
      return false;
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
