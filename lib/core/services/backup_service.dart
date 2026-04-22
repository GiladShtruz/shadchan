import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/data/models/match_idea.dart';
import 'package:shadchan/data/models/match_note.dart';
import 'package:shadchan/data/models/person.dart';
import 'package:shadchan/data/repositories/match_repository.dart';
import 'package:shadchan/data/repositories/person_repository.dart';

class BackupService {
  static Future<File> exportData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    final Map<String, Object?> payload = <String, Object?>{
      'version': 1,
      'exportDate': DateTime.now().toIso8601String(),
      'people': personRepo.getAll().map(_personToJson).toList(),
      'matches': matchRepo.getAll().map(_matchToJson).toList(),
      'matchNotes': matchRepo.getAllNotes().map(_noteToJson).toList(),
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
    final Object? decoded = jsonDecode(await jsonFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('קובץ הגיבוי אינו תקין');
    }

    if (decoded['version'] != 1) {
      throw const FormatException('גרסת הגיבוי אינה נתמכת');
    }

    int peopleAdded = 0;
    int matchesAdded = 0;
    int notesAdded = 0;
    int skipped = 0;

    final List<dynamic> peopleJson =
        decoded['people'] as List<dynamic>? ?? <dynamic>[];
    for (final Object? item in peopleJson) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }

      final Person person = _personFromJson(item);
      if (personRepo.containsId(person.id)) {
        skipped++;
        continue;
      }

      await personRepo.addImported(person);
      peopleAdded++;
    }

    final List<dynamic> matchesJson =
        decoded['matches'] as List<dynamic>? ?? <dynamic>[];
    for (final Object? item in matchesJson) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }

      final MatchIdea match = _matchFromJson(item);
      if (!personRepo.containsId(match.personAId) ||
          !personRepo.containsId(match.personBId)) {
        skipped++;
        continue;
      }

      if (matchRepo.containsMatchId(match.id)) {
        skipped++;
        continue;
      }

      await matchRepo.addImportedMatch(match);
      matchesAdded++;
    }

    final List<dynamic> notesJson =
        decoded['matchNotes'] as List<dynamic>? ?? <dynamic>[];
    for (final Object? item in notesJson) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }

      final MatchNote note = _noteFromJson(item);
      if (!matchRepo.containsMatchId(note.matchId)) {
        skipped++;
        continue;
      }

      if (matchRepo.containsNoteId(note.id)) {
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

  static Map<String, Object?> _personToJson(Person person) {
    return <String, Object?>{
      'id': person.id,
      'firstName': person.firstName,
      'lastName': person.lastName,
      'gender': person.gender.name,
      'birthDate': person.birthDate?.toIso8601String(),
      'manualAge': person.manualAge,
      'religiousLevel': person.religiousLevel?.name,
      'city': person.city,
      'phone': person.phone,
      'source': person.source,
      'notes': person.notes,
      'description': person.description,
      'profileStatus': person.profileStatus.name,
      'hebrewBirthYear': person.hebrewBirthYear,
      'hebrewBirthMonth': person.hebrewBirthMonth,
      'hebrewBirthDay': person.hebrewBirthDay,
      'photos': List<String>.from(person.photosPaths),
      'isFavorite': person.isFavorite,
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
      'createdAt': match.createdAt.toIso8601String(),
      'updatedAt': match.updatedAt.toIso8601String(),
    };
  }

  static Map<String, Object?> _noteToJson(MatchNote note) {
    return <String, Object?>{
      'id': note.id,
      'matchId': note.matchId,
      'text': note.text,
      'createdAt': note.createdAt.toIso8601String(),
      'isAutomatic': note.isAutomatic,
    };
  }

  static Person _personFromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      gender: Gender.values.byName(json['gender'] as String),
      birthDate: _parseNullableDate(json['birthDate']),
      manualAge: json['manualAge'] as int?,
      religiousLevel: _parseNullableReligiousLevel(json['religiousLevel']),
      city: json['city'] as String?,
      phone: json['phone'] as String?,
      source: json['source'] as String?,
      notes: json['notes'] as String?,
      description: json['description'] as String?,
      profileStatus: _parseProfileStatus(json['profileStatus']),
      hebrewBirthYear: json['hebrewBirthYear'] as int?,
      hebrewBirthMonth: json['hebrewBirthMonth'] as int?,
      hebrewBirthDay: json['hebrewBirthDay'] as int?,
      photosPaths: _parsePhotos(json),
      isFavorite: json['isFavorite'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static MatchIdea _matchFromJson(Map<String, dynamic> json) {
    return MatchIdea(
      id: json['id'] as String,
      personAId: json['personAId'] as String,
      personBId: json['personBId'] as String,
      status: MatchStatus.values.byName(json['status'] as String),
      currentHandler: CurrentHandler.values.byName(
        json['currentHandler'] as String,
      ),
      handlerName: json['handlerName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static MatchNote _noteFromJson(Map<String, dynamic> json) {
    return MatchNote(
      id: json['id'] as String,
      matchId: json['matchId'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isAutomatic: json['isAutomatic'] as bool? ?? false,
    );
  }

  static DateTime? _parseNullableDate(Object? value) {
    final String? rawValue = value as String?;
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    return DateTime.parse(rawValue);
  }

  static ReligiousLevel? _parseNullableReligiousLevel(Object? value) {
    final String? rawValue = value as String?;
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    return ReligiousLevel.values.byName(rawValue);
  }

  static ProfileStatus _parseProfileStatus(Object? value) {
    final String? rawValue = value as String?;
    if (rawValue == null || rawValue.isEmpty) {
      return ProfileStatus.available;
    }
    return ProfileStatus.values.byName(rawValue);
  }

  static List<String> _parsePhotos(Map<String, dynamic> json) {
    final List<dynamic> rawPhotos =
        (json['photos'] ?? json['photosPaths']) as List<dynamic>? ??
        <dynamic>[];
    return rawPhotos.map((dynamic item) => item as String).toList();
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
