import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/backup_service.dart';

/// A copy of this device's database taken **before** it is first merged into
/// an account.
///
/// The merge itself never deletes a record that exists only here (see
/// `AccountSyncCodec.decide`: a side that has a record the other never had
/// always sends it), so this is a second line of defence rather than the
/// first: should a migration be interrupted, refused by the server or turn out
/// wrong, the database as it stood is still on the phone, in the ordinary
/// backup format, and can be imported again from the settings.
///
/// It is let go once the account has been counted and found to hold
/// everything (`AccountSyncEngine.verify`), and in any case after
/// [keepFor] — it is a full copy of the database, and nobody should keep one
/// lying around for longer than it is useful.
abstract final class MigrationSnapshot {
  static const Duration keepFor = Duration(days: 30);
  static const String _folder = 'migration_snapshots';

  /// Where snapshots live. Overridable in tests.
  @visibleForTesting
  static Future<Directory> Function() directoryProvider = () async {
    final Directory base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}$_folder');
  };

  /// Whether [boxes] hold anything worth keeping a copy of.
  static bool hasRecords(Map<SyncCollection, Box<dynamic>> boxes) {
    for (final MapEntry<SyncCollection, Box<dynamic>> entry in boxes.entries) {
      if (entry.key != SyncCollection.settings && entry.value.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Writes the snapshot for [uid] and returns its file, or null when it could
  /// not be written (which never stops the migration — the merge is safe on
  /// its own; this only makes it safer).
  static Future<File?> take(
    String uid,
    Map<SyncCollection, Box<dynamic>> boxes,
  ) async {
    try {
      final Directory folder = await directoryProvider();
      folder.createSync(recursive: true);
      final Map<String, Object?> payload = build(boxes);
      final File file = File(
        '${folder.path}${Platform.pathSeparator}'
        '${uid}_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(payload), flush: true);
      return file;
    } on Object catch (error) {
      debugPrint('ACCOUNT_SYNC snapshot not written: $error');
      return null;
    }
  }

  /// The database in the backup file's shape (so the existing import reads
  /// it), plus the synced settings.
  @visibleForTesting
  static Map<String, Object?> build(Map<SyncCollection, Box<dynamic>> boxes) {
    List<Map<String, Object?>> records<T>(
      SyncCollection collection,
      Map<String, Object?> Function(T value) toJson,
    ) {
      final Box<dynamic>? box = boxes[collection];
      if (box == null) {
        return <Map<String, Object?>>[];
      }
      return <Map<String, Object?>>[
        for (final dynamic value in box.values)
          if (value is T) toJson(value),
      ];
    }

    final Map<String, Object?> settings = <String, Object?>{};
    final Box<dynamic>? settingsBox = boxes[SyncCollection.settings];
    if (settingsBox != null) {
      for (final dynamic key in settingsBox.keys) {
        if (key is String && AccountSyncCodec.isSyncedSetting(key)) {
          final Object? value = settingsBox.get(key);
          try {
            jsonEncode(value);
            settings[key] = value;
          } on Object {
            // A value JSON cannot hold is not synced either.
          }
        }
      }
    }

    return <String, Object?>{
      'version': 2,
      'exportDate': DateTime.now().toIso8601String(),
      'kind': 'migrationSnapshot',
      'people': records<Person>(
        SyncCollection.people,
        BackupService.personToJson,
      ),
      'personNotes': records<PersonNote>(
        SyncCollection.personNotes,
        BackupService.personNoteToJson,
      ),
      'personEvents': records<PersonEvent>(
        SyncCollection.personEvents,
        BackupService.personEventToJson,
      ),
      'matches': records<MatchIdea>(
        SyncCollection.matches,
        AccountSyncCodec.matchToRemote,
      ),
      'matchNotes': records<MatchNote>(
        SyncCollection.matchNotes,
        BackupService.matchNoteToJson,
      ),
      'matchStatusEvents': records<MatchStatusEvent>(
        SyncCollection.matchStatusEvents,
        BackupService.matchStatusEventToJson,
      ),
      'settings': settings,
    };
  }

  /// The snapshots kept for [uid], newest first.
  static Future<List<File>> list(String uid) async {
    try {
      final Directory folder = await directoryProvider();
      if (!folder.existsSync()) {
        return <File>[];
      }
      final List<File> files =
          folder
              .listSync()
              .whereType<File>()
              .where((File f) => _name(f).startsWith('${uid}_'))
              .toList()
            ..sort((File a, File b) => _name(b).compareTo(_name(a)));
      return files;
    } on Object {
      return <File>[];
    }
  }

  /// Lets go of [uid]'s snapshots — the account has been verified to hold
  /// everything they contain.
  static Future<void> release(String uid) async {
    for (final File file in await list(uid)) {
      try {
        file.deleteSync();
      } on Object catch (error) {
        debugPrint('ACCOUNT_SYNC snapshot not removed: $error');
      }
    }
  }

  /// Removes every snapshot older than [keepFor], whoever it belongs to.
  static Future<void> expire({DateTime? now}) async {
    try {
      final Directory folder = await directoryProvider();
      if (!folder.existsSync()) {
        return;
      }
      final DateTime cutoff = (now ?? DateTime.now()).subtract(keepFor);
      for (final File file in folder.listSync().whereType<File>()) {
        final int? millis = int.tryParse(
          _name(file).split('_').last.replaceAll('.json', ''),
        );
        if (millis != null &&
            DateTime.fromMillisecondsSinceEpoch(millis).isBefore(cutoff)) {
          file.deleteSync();
        }
      }
    } on Object catch (error) {
      debugPrint('ACCOUNT_SYNC snapshot expiry failed: $error');
    }
  }

  static String _name(File file) => file.uri.pathSegments.last;
}
