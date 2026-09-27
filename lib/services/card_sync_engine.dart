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
    this.minorUpdates = const <String>[],
  });

  /// Whether anything on the record moved, so it needs saving.
  final bool changed;

  /// The meaningful changes, for the profile's "new updates" — "דניאל מחק
  /// תמונה", "דניאל עדכן את טקסט הכרטיס". Empty on the first link, which logs
  /// its own line.
  final List<String> updates;

  /// Small changes — a word fixed, a sentence reworded, the photos reordered.
  /// Kept in the card's full change history only.
  final List<String> minorUpdates;

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
    final List<String> minorUpdates = <String>[];
    final String before = _cardPrint(person);
    final Map<String, Object?> jsonBefore = BackupService.personToJson(person);
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
        final Gender gender = person.gender;
        String say(String template) => '$name $template'.forGender(gender);
        if (photosChanged) {
          final ({String line, bool major}) photos = describePhotoChange(
            photosBefore,
            person.photosPaths,
          );
          (photos.major ? updates : minorUpdates).add(say(photos.line));
        }
        if (detailsChanged) {
          final Map<String, Object?> jsonAfter = BackupService.personToJson(
            person,
          );
          final ({String line, bool major})? text = describeTextChange(
            jsonBefore['description'] as String?,
            jsonAfter['description'] as String?,
          );
          if (text != null) {
            (text.major ? updates : minorUpdates).add(say(text.line));
          }
          for (final String line in _describeFieldChanges(
            jsonBefore,
            jsonAfter,
          )) {
            updates.add(say(line));
          }
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
      minorUpdates: minorUpdates,
      statusChanged: statusChanged,
    );
  }

  /// How the photos changed — a template for `forGender`, without the name.
  /// Only a reordering that keeps the main photo is minor.
  static ({String line, bool major}) describePhotoChange(
    List<String> before,
    List<String> after,
  ) {
    final List<String> a = <String>[
      for (final String path in before) PhotoPickerService.basenameOf(path),
    ];
    final List<String> b = <String>[
      for (final String path in after) PhotoPickerService.basenameOf(path),
    ];
    final Set<String> removed = a.toSet().difference(b.toSet());
    final Set<String> added = b.toSet().difference(a.toSet());
    if (removed.isNotEmpty && added.isEmpty) {
      return (
        line: removed.length == 1
            ? '{מחק|מחקה} תמונה'
            : '{מחק|מחקה} ${removed.length} תמונות',
        major: true,
      );
    }
    if (added.isNotEmpty && removed.isEmpty) {
      return (
        line: added.length == 1
            ? '{הוסיף|הוסיפה} תמונה'
            : '{הוסיף|הוסיפה} ${added.length} תמונות',
        major: true,
      );
    }
    if (added.isNotEmpty) {
      return (
        line: added.length == 1 && removed.length == 1
            ? '{החליף|החליפה} תמונה'
            : '{החליף|החליפה} תמונות',
        major: true,
      );
    }
    if (a.isNotEmpty && b.isNotEmpty && a.first != b.first) {
      return (line: '{החליף|החליפה} את התמונה הראשית', major: true);
    }
    return (line: '{שינה|שינתה} את סדר התמונות', major: false);
  }

  /// A change to the card's free text of at least this share of its words is
  /// a rewrite worth telling the matchmaker about. Anything smaller — a word,
  /// a phrasing, one sentence in a card of several — is a correction.
  static const double majorTextChange = 0.4;

  /// How the card's free text changed, or null when it did not. A template
  /// for `forGender`, without the name.
  static ({String line, bool major})? describeTextChange(
    String? before,
    String? after,
  ) {
    final String a = (before ?? '').trim();
    final String b = (after ?? '').trim();
    if (a == b) {
      return null;
    }
    if (a.isEmpty) {
      return (line: '{הוסיף|הוסיפה} טקסט לכרטיס', major: true);
    }
    if (b.isEmpty) {
      return (line: '{מחק|מחקה} את טקסט הכרטיס', major: true);
    }
    return textChangeRatio(a, b) >= majorTextChange
        ? (line: '{עדכן|עדכנה} את טקסט הכרטיס', major: true)
        : (line: '{תיקן|תיקנה} את טקסט הכרטיס', major: false);
  }

  static final RegExp _space = RegExp(r'\s+');
  static final RegExp _punctuation = RegExp('[.,;:!?()"׳״\\-–—]');

  /// The share of words that differ between [a] and [b], from 0 (the same
  /// words in the same order) to 1 (nothing in common): one minus their
  /// longest common run of words over the longer text.
  static double textChangeRatio(String a, String b) {
    List<String> words(String text) => text
        .split(_space)
        .map((String w) => w.replaceAll(_punctuation, ''))
        .where((String w) => w.isNotEmpty)
        .toList();
    final List<String> x = words(a);
    final List<String> y = words(b);
    final int longest = x.length > y.length ? x.length : y.length;
    if (longest == 0) {
      return 0;
    }
    // Longest common subsequence of words, one row at a time.
    List<int> previous = List<int>.filled(y.length + 1, 0);
    for (int i = 1; i <= x.length; i++) {
      final List<int> row = List<int>.filled(y.length + 1, 0);
      for (int j = 1; j <= y.length; j++) {
        row[j] = x[i - 1] == y[j - 1]
            ? previous[j - 1] + 1
            : (row[j - 1] > previous[j] ? row[j - 1] : previous[j]);
      }
      previous = row;
    }
    return 1 - previous[y.length] / longest;
  }

  /// The card's structured details, in the words a matchmaker would use.
  static const Map<String, String> _detailLabels = <String, String>{
    'firstName': 'השם',
    'lastName': 'השם',
    'gender': 'המגדר',
    'dateOfBirth': 'תאריך הלידה',
    'religiousLevel': 'הסגנון הדתי',
    'religiousLevelOther': 'הסגנון הדתי',
    'city': 'העיר',
    'heightCm': 'הגובה',
    'maritalStatus': 'המצב המשפחתי',
    'region': 'האזור',
  };

  /// "עדכן את העיר והגובה", and "עדכן את מה שהוא מחפש" for the preferences —
  /// templates for `forGender`, without the name.
  static List<String> _describeFieldChanges(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    String encode(Object? value) => jsonEncode(value);
    final List<String> labels = <String>[];
    bool preferences = false;
    for (final String key in PersonalCardCodec.cardFields) {
      if (key == 'description' || encode(before[key]) == encode(after[key])) {
        continue;
      }
      if (key.startsWith('preferred')) {
        preferences = true;
        continue;
      }
      final String? label = _detailLabels[key];
      if (label != null && !labels.contains(label)) {
        labels.add(label);
      }
    }
    final List<String> lines = <String>[];
    if (labels.isNotEmpty) {
      final String joined = labels.length == 1
          ? labels.single
          : '${labels.sublist(0, labels.length - 1).join(', ')} ו${labels.last}';
      lines.add('{עדכן|עדכנה} את $joined');
    }
    if (preferences) {
      lines.add('{עדכן|עדכנה} את מה {שהוא מחפש|שהיא מחפשת}');
    }
    return lines;
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
  /// * Either way the friend is left **in** the database: withdrawing access
  ///   takes the owner's card away, never the friend. A record that was kept
  ///   out of המאגר שלי before the link (a name on an idea, a draft) joined it
  ///   when the card arrived, and does not drop back out when it leaves.
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
      ..cardRemoteStatus = null
      ..hidden = false
      ..needsReview = false;
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
