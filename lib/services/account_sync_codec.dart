import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';

/// Everything about the account sync that needs no Firebase: what a record
/// looks like in the cloud, what counts as a change, and who wins when two
/// devices changed the same thing.
///
/// Kept apart from [AccountSyncEngine] so the rules that decide whether
/// somebody's work survives can be tested without a network, a platform
/// channel or a clock.
abstract final class AccountSyncCodec {
  /// The collections under `users/{uid}`, each mirroring one local Hive box.
  ///
  /// The box keys are the record ids, so a box key and a document id are the
  /// same string — which is what lets a Hive `watch()` event name the document
  /// it dirtied. `settings` is the exception: its keys are free text, so the
  /// document id is the key escaped (see [settingsDocId]).
  static const List<SyncCollection> collections = SyncCollection.values;

  /// A field the sync writes on every document beside the record itself:
  /// `_w` the server time of the write, `_d` the device that wrote it, and
  /// `_deleted` on a tombstone. Every one starts with an underscore and no
  /// record field does, which is how they are kept out of a fingerprint.
  static const String writtenAtField = '_w';
  static const String deviceField = '_d';
  static const String deletedField = '_deleted';

  // --- Fingerprints --------------------------------------------------------

  /// A stable fingerprint of one record's own fields.
  ///
  /// **Canonical at every depth**, not only at the top: Firestore does not
  /// promise to hand a nested map back in the order it was written, and a
  /// fingerprint that moved with key order would mark an untouched record as
  /// changed the first time it came back from the cloud. Sync metadata — the
  /// underscore fields — is dropped first for the same reason.
  static String fingerprint(Map<String, Object?> record) {
    return md5
        .convert(utf8.encode(jsonEncode(_canonical(stripMeta(record)))))
        .toString();
  }

  static Map<String, Object?> stripMeta(Map<String, Object?> record) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in record.entries)
        if (!entry.key.startsWith('_')) entry.key: entry.value,
    };
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final List<String> keys = value.keys.map((Object? key) => '$key').toList()
        ..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) {
      return value.map(_canonical).toList();
    }
    // A whole number Firestore hands back as a double (or the other way
    // round) is the same value, and must fingerprint the same.
    if (value is double && value == value.roundToDouble() && value.isFinite) {
      return value.toInt();
    }
    return value;
  }

  /// Whether a remote document is a deletion marker rather than a record.
  static bool isTombstone(Map<String, Object?>? data) {
    return data == null || data[deletedField] == true;
  }

  // --- Records ---------------------------------------------------------------

  /// One person as it travels: the backup JSON with photo paths reduced to
  /// basenames. An absolute path from this phone's sandbox is meaningless on
  /// the next one, and changes on iOS with every reinstall.
  static Map<String, Object?> personToRemote(Person person) {
    final Map<String, Object?> json = BackupService.personToJson(person);
    json['photos'] = basenames(json['photos']);
    return json;
  }

  static Person? personFromRemote(
    Map<String, Object?> json,
    String photosDirectory,
  ) {
    final Map<String, dynamic> local = Map<String, dynamic>.from(
      stripMeta(json),
    );
    local['photos'] = <String>[
      for (final String name in basenames(json['photos']))
        localPhotoPath(photosDirectory, name),
    ];
    return BackupService.personFromJson(local);
  }

  /// A proposal as it travels.
  ///
  /// **More than [BackupService.matchToJson]**, and on purpose: that shape is
  /// the contract the web client checks (`check:contract`), and it leaves out
  /// who has been asked, the check-in cadence and the dating span. A backup
  /// could lose those; a database the matchmaker opens on a second phone
  /// cannot, so they ride along here under their own keys.
  static Map<String, Object?> matchToRemote(MatchIdea match) {
    return <String, Object?>{
      ...BackupService.matchToJson(match),
      'askedMaleAt': match.askedMaleAt?.toIso8601String(),
      'askedFemaleAt': match.askedFemaleAt?.toIso8601String(),
      'checkInEveryDays': match.checkInEveryDays,
      'datingStartedAt': match.datingStartedAt?.toIso8601String(),
      'datingEndedAt': match.datingEndedAt?.toIso8601String(),
    };
  }

  static MatchIdea? matchFromRemote(Map<String, Object?> json) {
    final MatchIdea? match = BackupService.matchFromJson(
      Map<String, dynamic>.from(stripMeta(json)),
    );
    if (match == null) {
      return null;
    }
    match
      ..askedMaleAt = _date(json['askedMaleAt'])
      ..askedFemaleAt = _date(json['askedFemaleAt'])
      ..checkInEveryDays = json['checkInEveryDays'] is num
          ? (json['checkInEveryDays']! as num).toInt()
          : null
      ..datingStartedAt = _date(json['datingStartedAt'])
      ..datingEndedAt = _date(json['datingEndedAt']);
    return match;
  }

  static Map<String, Object?> personNoteToRemote(PersonNote note) =>
      BackupService.personNoteToJson(note);

  static PersonNote? personNoteFromRemote(Map<String, Object?> json) =>
      BackupService.personNoteFromJson(
        Map<String, dynamic>.from(stripMeta(json)),
      );

  static Map<String, Object?> matchNoteToRemote(MatchNote note) =>
      BackupService.matchNoteToJson(note);

  static MatchNote? matchNoteFromRemote(Map<String, Object?> json) =>
      BackupService.matchNoteFromJson(
        Map<String, dynamic>.from(stripMeta(json)),
      );

  static Map<String, Object?> personEventToRemote(PersonEvent event) =>
      BackupService.personEventToJson(event);

  static PersonEvent? personEventFromRemote(Map<String, Object?> json) =>
      BackupService.personEventFromJson(
        Map<String, dynamic>.from(stripMeta(json)),
      );

  static Map<String, Object?> matchStatusEventToRemote(
    MatchStatusEvent event,
  ) => BackupService.matchStatusEventToJson(event);

  static MatchStatusEvent? matchStatusEventFromRemote(
    Map<String, Object?> json,
  ) => BackupService.matchStatusEventFromJson(
    Map<String, dynamic>.from(stripMeta(json)),
  );

  // --- Settings --------------------------------------------------------------

  /// Settings that describe **this device**, not the account, and so never
  /// travel. Everything else in the `settings` box does — a board, a
  /// reminder, a dismissed suggestion, a tag, the matchmaker's own profile —
  /// which is the point: an allow-list would have to be remembered every time
  /// somebody adds a setting, and the cost of forgetting is a preference that
  /// silently differs between two phones. A deny-list fails safe in the other
  /// direction.
  static const List<String> _deviceOnlyPrefixes = <String>[
    // The sync's own ledger and the sign-in gate are about this phone.
    'cloudSync',
    'accountSync.',
    'signIn.',
    // Fingerprints of what *this* device last published somewhere else.
    'contactHashes.',
    'databaseHashes.',
    'tags.publishedPrint',
    'personalCard.publishedPrint',
    'personalCard.identityPrint',
    'personalCard.identityHash',
    'personalCard.uploadedPhotos',
    'community.publishedFingerprint',
    'community.avatarLocalPath',
    'community.avatarUrl',
    'community.pendingBulkImport',
    'community.joinedAtWritten',
    // Caches keyed by a local file path.
    'faceAlign.',
    // One-time migrations describe the data on this disk.
    'migrated',
    // An invitation link opened on this phone.
    'invite.',
    'tips.approvedCache',
    'support_seen_',
  ];

  static bool isSyncedSetting(String key) {
    for (final String prefix in _deviceOnlyPrefixes) {
      if (key.startsWith(prefix)) {
        return false;
      }
    }
    return true;
  }

  /// The three settings that hold photo paths. They travel as basenames, like
  /// a person's photos, and their files ride the same Storage folder.
  static const String profilePhotoKey = 'userPhotoPath';
  static const String profileCardPhotosKey = 'userPersonalCardPhotos';
  static const String personalCardKey = 'personalCard.person';

  /// A setting key made safe for a document id. Keys may carry anything a
  /// developer once thought of, including a `/`; the original key is kept in
  /// the document itself.
  static String settingsDocId(String key) => Uri.encodeComponent(key);

  /// One setting as it travels, or null when its value cannot (a type JSON
  /// has no word for). The value is carried as JSON text so a bool stays a
  /// bool and a list stays a list, whatever Firestore makes of them.
  static Map<String, Object?>? settingToRemote(String key, Object? value) {
    final Object? portable = _photosOut(key, value);
    try {
      return <String, Object?>{'k': key, 'v': jsonEncode(portable)};
    } on Object {
      return null;
    }
  }

  /// The local key and value of a remote setting, or null when the document
  /// is not one this app can read.
  static ({String key, Object? value})? settingFromRemote(
    Map<String, Object?> data,
    String photosDirectory,
  ) {
    final Object? key = data['k'];
    final Object? raw = data['v'];
    if (key is! String || raw is! String) {
      return null;
    }
    try {
      return (
        key: key,
        value: _photosIn(key, jsonDecode(raw), photosDirectory),
      );
    } on Object {
      return null;
    }
  }

  /// Every photo basename a setting refers to, for the uploader to find.
  static List<String> settingPhotoNames(String key, Object? value) {
    final Object? portable = _photosOut(key, value);
    if (key == profilePhotoKey && portable is String) {
      return <String>[portable];
    }
    if (key == profileCardPhotosKey && portable is List) {
      return portable.whereType<String>().toList();
    }
    if (key == personalCardKey && portable is String) {
      try {
        final Object? json = jsonDecode(portable);
        if (json is Map) {
          return basenames(json['photos']);
        }
      } on Object {
        return const <String>[];
      }
    }
    return const <String>[];
  }

  static Object? _photosOut(String key, Object? value) {
    if (key == profilePhotoKey && value is String && value.isNotEmpty) {
      return PhotoPickerService.basenameOf(value);
    }
    if (key == profileCardPhotosKey && value is Iterable) {
      return basenames(value.toList());
    }
    if (key == personalCardKey && value is String) {
      try {
        final Object? json = jsonDecode(value);
        if (json is Map) {
          final Map<String, Object?> copy = Map<String, Object?>.from(json);
          copy['photos'] = basenames(copy['photos']);
          return jsonEncode(copy);
        }
      } on Object {
        return value;
      }
    }
    return value;
  }

  static Object? _photosIn(String key, Object? value, String directory) {
    if (key == profilePhotoKey && value is String && value.isNotEmpty) {
      return localPhotoPath(directory, value);
    }
    if (key == profileCardPhotosKey && value is List) {
      return <String>[
        for (final String name in value.whereType<String>())
          localPhotoPath(directory, name),
      ];
    }
    if (key == personalCardKey && value is String) {
      try {
        final Object? json = jsonDecode(value);
        if (json is Map) {
          final Map<String, Object?> copy = Map<String, Object?>.from(json);
          copy['photos'] = <String>[
            for (final String name in basenames(copy['photos']))
              localPhotoPath(directory, name),
          ];
          return jsonEncode(copy);
        }
      } on Object {
        return value;
      }
    }
    return value;
  }

  // --- Photos ----------------------------------------------------------------

  static List<String> basenames(Object? paths) {
    if (paths is! List) {
      return <String>[];
    }
    return <String>[
      for (final String path in paths.whereType<String>())
        if (path.trim().isNotEmpty) PhotoPickerService.basenameOf(path),
    ];
  }

  static String localPhotoPath(String directory, String basename) {
    final String separator = directory.contains(r'\') ? r'\' : '/';
    return '$directory$separator$basename';
  }

  static DateTime? _date(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }

  // --- The merge -------------------------------------------------------------

  /// What to do about one document, given where both sides stand and where
  /// they stood the last time they agreed.
  ///
  /// A three-way merge, with [base] as the common ancestor. A side that still
  /// matches the base did not change, so whatever the other side did wins —
  /// that one rule covers an edit, an insert (nothing on either side at the
  /// base) and a deletion (nothing on one side now). Only when **both** moved
  /// is there a conflict, and then:
  ///
  /// * an edit beats a deletion, on either side — losing a record somebody
  ///   was still working on is worse than resurrecting one somebody removed;
  /// * between two edits, the later one wins. [localChangedAt] is when this
  ///   device noticed its own change, [remoteWrittenAt] the server's time on
  ///   the other one; a missing time loses.
  static SyncDecision decide({
    required String? local,
    required String? remote,
    required SyncBase? base,
    int? localChangedAt,
    int? remoteWrittenAt,
  }) {
    if (local == remote) {
      return SyncDecision.inSync;
    }
    final bool localMoved = local != base?.local;
    final bool remoteMoved = remote != base?.remote;
    if (!localMoved && remoteMoved) {
      return SyncDecision.takeRemote;
    }
    if (localMoved && !remoteMoved) {
      return SyncDecision.pushLocal;
    }
    if (!localMoved && !remoteMoved) {
      // Both sides exactly as they were when they last agreed. They differ
      // only because the local copy of that remote record does not
      // round-trip byte for byte (see [SyncBase]) — nothing happened.
      return SyncDecision.inSync;
    }
    if (local == null) {
      return SyncDecision.takeRemote;
    }
    if (remote == null) {
      return SyncDecision.pushLocal;
    }
    if ((localChangedAt ?? 0) > (remoteWrittenAt ?? 0)) {
      return SyncDecision.pushLocal;
    }
    return SyncDecision.takeRemote;
  }
}

/// The seven synced collections, with the Hive box each mirrors.
enum SyncCollection {
  people('people', 'people'),
  personNotes('personNotes', 'person_notes'),
  personEvents('personEvents', 'person_events'),
  matches('matches', 'matches'),
  matchNotes('matchNotes', 'match_notes'),
  matchStatusEvents('matchStatusEvents', 'match_status_events'),
  settings('settings', 'settings');

  const SyncCollection(this.remote, this.box);

  /// The Firestore collection under `users/{uid}`.
  final String remote;

  /// The local Hive box.
  final String box;

  static SyncCollection? byRemote(String name) {
    for (final SyncCollection collection in values) {
      if (collection.remote == name) {
        return collection;
      }
    }
    return null;
  }
}

/// Where a document stood the last time both sides agreed: the fingerprint
/// of the local record and of the remote document at that moment. They are
/// usually equal; they differ when the local copy of a remote record does not
/// round-trip byte for byte, and keeping both stops that difference from
/// looking like a change on either side.
class SyncBase {
  const SyncBase({required this.local, required this.remote});

  final String? local;
  final String? remote;

  static SyncBase? parse(Object? stored) {
    if (stored is! String) {
      return null;
    }
    final int bar = stored.indexOf('|');
    if (bar < 0) {
      return null;
    }
    String? part(String value) => value.isEmpty ? null : value;
    return SyncBase(
      local: part(stored.substring(0, bar)),
      remote: part(stored.substring(bar + 1)),
    );
  }

  String encode() => '${local ?? ''}|${remote ?? ''}';
}

enum SyncDecision { inSync, takeRemote, pushLocal }
