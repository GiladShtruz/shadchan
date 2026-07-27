import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';

/// Local JSON backup/restore of the whole database.
///
/// Design goals, after the backup format fell behind the data model:
/// - **Complete**: every persisted field is written, including flags that were
///   previously dropped (`hidden`, `needsReview`, reminders), so a restore
///   reproduces the original state instead of quietly changing it.
/// - **Crash-safe on import**: one malformed record can never abort the whole
///   restore. Records are parsed leniently and, if unrecoverable, skipped and
///   counted rather than thrown.
/// - **Forward/backward tolerant**: unknown enum values and unparseable dates
///   degrade to sensible defaults instead of failing, and older backups
///   (which stored a `birthDate` before ages replaced it) still import.
///
/// Note: photos are stored as file paths, not embedded bytes, so the images
/// themselves are not part of the backup — a restore on a different device (or
/// after an uninstall) keeps the people/matches/notes but not the photo files.
class BackupService {
  /// Bumped whenever the export shape changes. The importer stays lenient and
  /// accepts older versions too, so raising this never orphans old backups.
  static const int _currentVersion = 2;

  static Future<File> exportData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    final Map<String, Object?> payload = <String, Object?>{
      'version': _currentVersion,
      'exportDate': DateTime.now().toIso8601String(),
      'people': personRepo.getAll().map(_personToJson).toList(),
      'personNotes': personRepo.getAllNotes().map(_personNoteToJson).toList(),
      'matches': matchRepo.getAll().map(_matchToJson).toList(),
      'matchNotes': matchRepo.getAllNotes().map(_matchNoteToJson).toList(),
    };

    final Directory tempDirectory = await getTemporaryDirectory();
    final String formattedDate = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now());
    final File backupFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}shadchan_backup_$formattedDate.json',
    );

    await backupFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    return backupFile;
  }

  static Future<void> shareBackup(File backupFile) async {
    await Share.shareXFiles(<XFile>[
      XFile(backupFile.path),
    ], subject: 'גיבוי שדכן');
  }

  static Future<ImportResult> importData(
    File jsonFile,
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await jsonFile.readAsString());
    } catch (_) {
      throw const FormatException('קובץ הגיבוי אינו קריא');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('קובץ הגיבוי אינו תקין');
    }

    // Only refuse a file that has none of the sections we know how to read;
    // any recognizable backup is imported regardless of its version number.
    final bool looksLikeBackup =
        decoded.containsKey('people') ||
        decoded.containsKey('matches') ||
        decoded.containsKey('personNotes') ||
        decoded.containsKey('matchNotes');
    if (!looksLikeBackup) {
      throw const FormatException('קובץ הגיבוי אינו תקין');
    }

    int peopleAdded = 0;
    int matchesAdded = 0;
    int notesAdded = 0;
    int skipped = 0;

    for (final Map<String, dynamic> item in _records(decoded['people'])) {
      final Person? person = _tryParse(() => _personFromJson(item));
      if (person == null || personRepo.containsId(person.id)) {
        skipped++;
        continue;
      }
      await personRepo.addImported(person);
      peopleAdded++;
    }

    for (final Map<String, dynamic> item in _records(decoded['matches'])) {
      final MatchIdea? match = _tryParse(() => _matchFromJson(item));
      if (match == null ||
          !personRepo.containsId(match.personAId) ||
          !personRepo.containsId(match.personBId) ||
          matchRepo.containsMatchId(match.id)) {
        skipped++;
        continue;
      }
      await matchRepo.addImportedMatch(match);
      matchesAdded++;
    }

    for (final Map<String, dynamic> item in _records(decoded['personNotes'])) {
      final PersonNote? note = _tryParse(() => _personNoteFromJson(item));
      if (note == null ||
          !personRepo.containsId(note.personId) ||
          personRepo.containsNoteId(note.id)) {
        skipped++;
        continue;
      }
      await personRepo.addImportedNote(note);
      notesAdded++;
    }

    for (final Map<String, dynamic> item in _records(decoded['matchNotes'])) {
      final MatchNote? note = _tryParse(() => _matchNoteFromJson(item));
      if (note == null ||
          !matchRepo.containsMatchId(note.matchId) ||
          matchRepo.containsNoteId(note.id)) {
        skipped++;
        continue;
      }
      await matchRepo.addImportedNote(note);
      notesAdded++;
    }

    await personRepo.finishImport();
    await matchRepo.finishImport();

    return ImportResult(
      peopleAdded: peopleAdded,
      matchesAdded: matchesAdded,
      notesAdded: notesAdded,
      skipped: skipped,
    );
  }

  // --- Serialization ------------------------------------------------------

  static Map<String, Object?> _personToJson(Person person) {
    return <String, Object?>{
      'id': person.id,
      'firstName': person.firstName,
      'lastName': person.lastName,
      'gender': person.gender.name,
      'manualAge': person.manualAge,
      'manualAgeUpdatedAt': person.manualAgeUpdatedAt?.toIso8601String(),
      'religiousLevel': person.religiousLevel?.name,
      'religiousLevelOther': person.religiousLevelOther,
      'city': person.city,
      'phone': person.phone,
      'source': person.source,
      'notes': person.notes,
      'description': person.description,
      'inquiryContactName': person.inquiryContactName,
      'inquiryContactPhone': person.inquiryContactPhone,
      'heightCm': person.heightCm,
      'maritalStatus': person.maritalStatus?.name,
      'profileStatus': person.profileStatus.name,
      'photos': List<String>.from(person.photosPaths),
      'isFavorite': person.isFavorite,
      'needsReview': person.needsReview,
      'hidden': person.hidden,
      'avatarIndex': person.avatarIndex,
      'createdAt': person.createdAt.toIso8601String(),
      'updatedAt': person.updatedAt.toIso8601String(),
    };
  }

  static Map<String, Object?> _matchToJson(MatchIdea match) {
    return <String, Object?>{
      'id': match.id,
      'personAId': match.personAId,
      'personBId': match.personBId,
      'status': match.status.name,
      'currentHandler': match.currentHandler.name,
      'handlerName': match.handlerName,
      'reminderDate': match.reminderDate?.toIso8601String(),
      'reminderNote': match.reminderNote,
      'waitingReason': match.waitingReason,
      'progress': match.progress?.name,
      'progressOther': match.progressOther,
      'relatedContacts': match.relatedContacts
          .map(
            (MatchContact contact) => <String, Object?>{
              'name': contact.name,
              'phone': contact.phone,
              'description': contact.description,
            },
          )
          .toList(),
      'createdAt': match.createdAt.toIso8601String(),
      'updatedAt': match.updatedAt.toIso8601String(),
    };
  }

  static Map<String, Object?> _personNoteToJson(PersonNote note) {
    return <String, Object?>{
      'id': note.id,
      'personId': note.personId,
      'text': note.text,
      'createdAt': note.createdAt.toIso8601String(),
      'isAutomatic': note.isAutomatic,
    };
  }

  static Map<String, Object?> _matchNoteToJson(MatchNote note) {
    return <String, Object?>{
      'id': note.id,
      'matchId': note.matchId,
      'text': note.text,
      'createdAt': note.createdAt.toIso8601String(),
      'isAutomatic': note.isAutomatic,
    };
  }

  // --- Deserialization ----------------------------------------------------

  /// Returns null (skip) when the record has no id — nothing can reference or
  /// de-duplicate it. Every other field degrades to a default rather than
  /// throwing, so a slightly-off record still restores.
  static Person? _personFromJson(Map<String, dynamic> json) {
    final String? id = _string(json['id']);
    if (id == null) {
      return null;
    }

    final DateTime now = DateTime.now();
    return Person(
      id: id,
      firstName: _string(json['firstName']) ?? '',
      lastName: _string(json['lastName']) ?? '',
      gender: _enumByName(Gender.values, json['gender']) ?? Gender.unknown,
      // Backups written before birth dates were removed carry one instead of an
      // age, so it is converted here rather than dropped.
      manualAge:
          _int(json['manualAge']) ?? _ageFromLegacyBirthDate(json['birthDate']),
      manualAgeUpdatedAt:
          _date(json['manualAgeUpdatedAt']) ??
          (json['manualAge'] == null && json['birthDate'] != null ? now : null),
      religiousLevel: _enumByName(
        ReligiousLevel.values,
        json['religiousLevel'],
      ),
      religiousLevelOther: _string(json['religiousLevelOther']),
      city: _string(json['city']),
      phone: _string(json['phone']),
      source: _string(json['source']),
      notes: _string(json['notes']),
      description: _string(json['description']),
      inquiryContactName: _string(json['inquiryContactName']),
      inquiryContactPhone: _string(json['inquiryContactPhone']),
      heightCm: _int(json['heightCm']),
      maritalStatus: _enumByName(MaritalStatus.values, json['maritalStatus']),
      profileStatus:
          _enumByName(ProfileStatus.values, json['profileStatus']) ??
          ProfileStatus.available,
      photosPaths: _parsePhotos(json),
      isFavorite: _bool(json['isFavorite']),
      needsReview: _bool(json['needsReview']),
      hidden: _bool(json['hidden']),
      avatarIndex: _int(json['avatarIndex']),
      createdAt: _date(json['createdAt']) ?? now,
      updatedAt: _date(json['updatedAt']) ?? now,
    );
  }

  static MatchIdea? _matchFromJson(Map<String, dynamic> json) {
    final String? id = _string(json['id']);
    final String? personAId = _string(json['personAId']);
    final String? personBId = _string(json['personBId']);
    if (id == null || personAId == null || personBId == null) {
      return null;
    }

    final DateTime now = DateTime.now();
    return MatchIdea(
      id: id,
      personAId: personAId,
      personBId: personBId,
      status:
          _enumByName(MatchStatus.values, json['status']) ?? MatchStatus.idea,
      currentHandler:
          _enumByName(CurrentHandler.values, json['currentHandler']) ??
          CurrentHandler.me,
      handlerName: _string(json['handlerName']),
      reminderDate: _date(json['reminderDate']),
      reminderNote: _string(json['reminderNote']),
      waitingReason: _string(json['waitingReason']),
      progress: _enumByName(MatchProgress.values, json['progress']),
      progressOther: _string(json['progressOther']),
      relatedContacts: _matchContacts(json['relatedContacts']),
      createdAt: _date(json['createdAt']) ?? now,
      updatedAt: _date(json['updatedAt']) ?? now,
    );
  }

  static List<MatchContact> _matchContacts(Object? raw) {
    if (raw is! List<dynamic>) {
      return const <MatchContact>[];
    }
    return raw.whereType<Map<dynamic, dynamic>>().map((
      Map<dynamic, dynamic> item,
    ) {
      return MatchContact(
        name: _string(item['name']) ?? '',
        phone: _string(item['phone']) ?? '',
        description: _string(item['description']),
      );
    }).toList();
  }

  static PersonNote? _personNoteFromJson(Map<String, dynamic> json) {
    final String? id = _string(json['id']);
    final String? personId = _string(json['personId']);
    if (id == null || personId == null) {
      return null;
    }

    return PersonNote(
      id: id,
      personId: personId,
      text: _string(json['text']) ?? '',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      isAutomatic: _bool(json['isAutomatic']),
    );
  }

  static MatchNote? _matchNoteFromJson(Map<String, dynamic> json) {
    final String? id = _string(json['id']);
    final String? matchId = _string(json['matchId']);
    if (id == null || matchId == null) {
      return null;
    }

    return MatchNote(
      id: id,
      matchId: matchId,
      text: _string(json['text']) ?? '',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      isAutomatic: _bool(json['isAutomatic']),
    );
  }

  // --- Lenient parsing helpers -------------------------------------------

  /// Runs a record parser, turning any unexpected failure into a skipped
  /// record (null) instead of aborting the whole import.
  static T? _tryParse<T>(T? Function() parse) {
    try {
      return parse();
    } catch (error, stackTrace) {
      debugPrint('BackupService: skipped a record: $error\n$stackTrace');
      return null;
    }
  }

  /// Coerces a decoded JSON list into a list of string-keyed maps, ignoring any
  /// non-map entries. Missing/!list values yield an empty list.
  static Iterable<Map<String, dynamic>> _records(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value.whereType<Map<String, dynamic>>();
  }

  static String? _string(Object? value) {
    if (value is String) {
      return value.isEmpty ? null : value;
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }
    return fallback;
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  /// Matches an enum by its [Enum.name]; unknown values return null instead of
  /// throwing (which is what `values.byName` does).
  static T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    for (final T value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }

  static int? _ageFromLegacyBirthDate(Object? value) {
    final DateTime? birthDate = _date(value);
    return birthDate == null ? null : AppDateUtils.calculateAge(birthDate);
  }

  static List<String> _parsePhotos(Map<String, dynamic> json) {
    final Object? raw = json['photos'] ?? json['photosPaths'];
    if (raw is! List) {
      return <String>[];
    }
    return raw.whereType<String>().toList();
  }
}

class ImportResult {
  const ImportResult({
    required this.peopleAdded,
    required this.matchesAdded,
    required this.notesAdded,
    required this.skipped,
  });

  final int peopleAdded;
  final int matchesAdded;
  final int notesAdded;
  final int skipped;
}
