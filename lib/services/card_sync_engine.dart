import 'dart:convert';

import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// What applying one version of an owner's card changed on the matchmaker's
/// copy.
class CardSyncResult {
  const CardSyncResult({
    required this.changed,
    required this.updates,
    required this.statusChanged,
  });

  /// Whether anything on the record moved, so it needs saving.
  final bool changed;

  /// The short lines for the profile's "recent updates" — "דניאל החליף
  /// תמונה". Empty on the first link, which logs its own line.
  final List<String> updates;

  final bool statusChanged;
}

/// The rules for a matchmaker's copy of a friend who manages their own card.
///
/// No Firebase in here: the provider fetches the card and its photos and hands
/// them over, and this decides what happens to the record — which is the part
/// worth testing.
abstract final class CardSyncEngine {
  /// The prefix of every photo file downloaded from an owner's card, so those
  /// files can be told apart from the matchmaker's own and removed when the
  /// sync ends.
  static String photoFileName(String ownerUid, String remoteName) =>
      'card_${ownerUid}_$remoteName';

  static bool isCardPhoto(String path) =>
      PhotoPickerService.basenameOf(path).startsWith('card_');

  /// The friend in [people] that [ownerUid]'s card belongs to, if the
  /// matchmaker already has them — so granting access links the card to the
  /// existing record instead of adding the friend a second time.
  ///
  /// In order: the record already linked to this card; a record whose saved
  /// number is the owner's ([ownerPhoneHash]) — the real identity, and the
  /// same one a later import from the contacts is checked against; and, only
  /// for a record with no number at all, exactly one record with the card's
  /// full name. A record with some *other* number is a different person with
  /// the same name, and is never taken. Visible records win over hidden ones.
  static Person? findExisting(
    Iterable<Person> people, {
    required String ownerUid,
    required String? ownerPhoneHash,
    required String firstName,
    required String lastName,
  }) {
    for (final Person person in people) {
      if (person.cardOwnerUid == ownerUid) {
        return person;
      }
    }
    final List<Person> free = people
        .where((Person p) => p.cardOwnerUid == null)
        .toList();
    int rank(Person p) => p.hidden ? 1 : 0;
    int byPreference(Person a, Person b) {
      final int hidden = rank(a).compareTo(rank(b));
      return hidden != 0 ? hidden : b.updatedAt.compareTo(a.updatedAt);
    }

    if (ownerPhoneHash != null) {
      final List<Person> byPhone =
          free
              .where(
                (Person p) => PhoneIdentity.hash(p.phone) == ownerPhoneHash,
              )
              .toList()
            ..sort(byPreference);
      if (byPhone.isNotEmpty) {
        return byPhone.first;
      }
    }

    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      return null;
    }
    final String wanted = _nameKey(firstName, lastName);
    final List<Person> byName = free
        .where(
          (Person p) =>
              !p.hidden &&
              (p.phone ?? '').trim().isEmpty &&
              _nameKey(p.firstName, p.lastName) == wanted,
        )
        .toList();
    return byName.length == 1 ? byName.first : null;
  }

  static String _nameKey(String first, String last) =>
      '${first.trim()} ${last.trim()}'.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Whether the matchmaker had written anything about this person beyond a
  /// name — the condition for keeping a snapshot to restore later.
  static bool hasOwnContent(Person person) {
    return (person.description ?? '').trim().isNotEmpty ||
        person.photosPaths.isNotEmpty ||
        person.manualAge != null ||
        person.religiousLevel != null ||
        (person.city ?? '').trim().isNotEmpty ||
        person.heightCm != null ||
        person.maritalStatus != null ||
        person.region != null ||
        person.preferredMinAge != null ||
        person.preferredMaxAge != null ||
        person.preferredRegions.isNotEmpty ||
        person.preferredReligiousLevels.isNotEmpty;
  }

  /// The card as it currently stands on [person] — its fields and its
  /// photos. Compared against the print taken when the owner's version was
  /// last applied, it tells a matchmaker's own edit apart from a save that
  /// changed nothing on the card (a reminder, a favourite, a note).
  static String printOf(Person person) {
    final Map<String, Object?> json = BackupService.personToJson(person);
    return SyncStateStore.fingerprint(<String, Object?>{
      for (final String key in PersonalCardCodec.cardFields) key: json[key],
      'photos': <String>[
        for (final String path in person.photosPaths)
          PhotoPickerService.basenameOf(path),
      ],
    });
  }

  static String _cardPrint(Person person) {
    final Map<String, Object?> json = BackupService.personToJson(person);
    return SyncStateStore.fingerprint(<String, Object?>{
      for (final String key in PersonalCardCodec.cardFields) key: json[key],
    });
  }

  /// Applies the card [data] (a `personalCards` document) to [person].
  ///
  /// The first time, the record is linked to [ownerUid] and — if the
  /// matchmaker had written anything of their own — a snapshot of it is kept
  /// to put back later. A record whose sync was detached takes the owner's
  /// status and nothing else.
  static CardSyncResult apply(
    Person person,
    Map<String, dynamic> data, {
    required String ownerUid,
    required List<String> localPhotoPaths,
  }) {
    bool changed = false;
    final bool firstLink = person.cardOwnerUid != ownerUid;
    if (firstLink) {
      person
        ..preSyncSnapshot = hasOwnContent(person)
            ? jsonEncode(BackupService.personToJson(person))
            : null
        ..cardOwnerUid = ownerUid
        ..cardSyncDetached = false
        ..cardRemoteStatus = null;
      changed = true;
    }

    final List<String> updates = <String>[];
    final String before = _cardPrint(person);
    final List<String> photosBefore = List<String>.from(person.photosPaths);

    if (!person.cardSyncDetached) {
      PersonalCardCodec.applyTo(person, data);
      person.photosPaths = List<String>.from(localPhotoPaths);
      final bool photosChanged = !_samePhotos(photosBefore, person.photosPaths);
      final bool detailsChanged = before != _cardPrint(person);
      if (photosChanged || detailsChanged) {
        changed = true;
      }
      if (!firstLink) {
        final String name = person.firstName.trim();
        if (photosChanged) {
          updates.add('$name {החליף|החליפה} תמונה'.forGender(person.gender));
        }
        if (detailsChanged) {
          updates.add(
            '$name {עדכן|עדכנה} את הפרטים {שלו|שלה}'.forGender(person.gender),
          );
        }
      }
    }

    bool statusChanged = false;
    final ProfileStatus? remote = PersonalCardCodec.statusOf(data);
    if (remote != null && person.cardRemoteStatus != remote.name) {
      final bool differs = person.profileStatus != remote;
      person
        ..profileStatus = remote
        ..cardRemoteStatus = remote.name;
      changed = true;
      statusChanged = differs;
      if (differs && !firstLink) {
        updates.add(
          '${person.firstName.trim()} {עדכן|עדכנה} את הסטטוס ל־${remote.displayName}'
              .forGender(person.gender),
        );
      }
    }

    return CardSyncResult(
      changed: changed,
      updates: updates,
      statusChanged: statusChanged,
    );
  }

  static bool _samePhotos(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (PhotoPickerService.basenameOf(a[i]) !=
          PhotoPickerService.basenameOf(b[i])) {
        return false;
      }
    }
    return true;
  }

  /// Ends the link, when access is withdrawn or the card is deleted.
  ///
  /// * A detached record is the matchmaker's own version by their choice, and
  ///   stays exactly as it is; only the link goes.
  /// * Otherwise the snapshot taken before the sync is put back, if there was
  ///   one.
  /// * With no snapshot, the owner's details come off and the person stays in
  ///   the database with their name — and with everything the matchmaker
  ///   wrote privately, which never lived on this record anyway.
  ///
  /// Returns the downloaded card photos to delete from the device: nothing
  /// received from the owner may linger once access is gone.
  static List<String> unlink(Person person) {
    final List<String> toDelete = <String>[];
    if (!person.cardSyncDetached) {
      toDelete.addAll(person.photosPaths.where(isCardPhoto));
      final String? snapshot = person.preSyncSnapshot;
      Person? previous;
      if (snapshot != null) {
        try {
          final Object? json = jsonDecode(snapshot);
          if (json is Map<String, dynamic>) {
            previous = BackupService.personFromJson(json);
          }
        } on FormatException {
          previous = null;
        }
      }
      if (previous != null) {
        person
          ..firstName = previous.firstName
          ..lastName = previous.lastName
          ..gender = previous.gender
          ..birthDate = previous.birthDate
          ..manualAge = previous.manualAge
          ..manualAgeUpdatedAt = previous.manualAgeUpdatedAt;
        _copyCardFields(from: previous, to: person);
      } else {
        person
          ..birthDate = null
          ..setManualAge(null);
        _clearCardFields(person);
      }
    }
    person
      ..cardOwnerUid = null
      ..cardSyncDetached = false
      ..preSyncSnapshot = null
      ..cardRemoteStatus = null;
    return toDelete;
  }

  static void _copyCardFields({required Person from, required Person to}) {
    to
      ..religiousLevel = from.religiousLevel
      ..religiousLevelOther = from.religiousLevelOther
      ..city = from.city
      ..description = from.description
      ..heightCm = from.heightCm
      ..maritalStatus = from.maritalStatus
      ..region = from.region
      ..preferredMinAge = from.preferredMinAge
      ..preferredMaxAge = from.preferredMaxAge
      ..preferredMinHeightCm = from.preferredMinHeightCm
      ..preferredMaxHeightCm = from.preferredMaxHeightCm
      ..preferredRegions = List<Region>.from(from.preferredRegions)
      ..preferredMaritalStatuses = List<MaritalStatus>.from(
        from.preferredMaritalStatuses,
      )
      ..preferredReligiousLevels = List<ReligiousLevel>.from(
        from.preferredReligiousLevels,
      )
      ..preferredReligiousLevelOtherLabels = List<String>.from(
        from.preferredReligiousLevelOtherLabels,
      )
      ..photosPaths = List<String>.from(from.photosPaths);
  }

  static void _clearCardFields(Person person) {
    person
      ..religiousLevel = null
      ..religiousLevelOther = null
      ..city = null
      ..description = null
      ..heightCm = null
      ..maritalStatus = null
      ..region = null
      ..preferredMinAge = null
      ..preferredMaxAge = null
      ..preferredMinHeightCm = null
      ..preferredMaxHeightCm = null
      ..preferredRegions = <Region>[]
      ..preferredMaritalStatuses = <MaritalStatus>[]
      ..preferredReligiousLevels = <ReligiousLevel>[]
      ..preferredReligiousLevelOtherLabels = <String>[]
      ..photosPaths = <String>[];
  }
}
