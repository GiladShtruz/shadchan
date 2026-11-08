import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/date_utils.dart';

/// One-time data migrations that run at startup, before the UI is built.
abstract final class PersonMigrations {
  @visibleForTesting
  static const String birthDateMigrationKey = 'migratedBirthDatesToAges';

  /// Converts the birth dates stored by older versions into a plain age.
  ///
  /// Birth dates were removed from the app, so a person's age is now just
  /// `manualAge` + `manualAgeUpdatedAt` (which advances the age once a year).
  /// Records that only had a birth date would otherwise show no age at all, so
  /// their current age is computed once and stored, and the legacy fields are
  /// cleared. Runs once — a flag in the settings box keeps later launches from
  /// walking the whole box again.
  static Future<void> convertBirthDatesToAges({
    required Box<Person> people,
    required Box<dynamic> settings,
  }) async {
    if (settings.get(birthDateMigrationKey) == true) {
      return;
    }

    final DateTime now = DateTime.now();
    // Iterate a copy so saving a record can never disturb the live iterator,
    // and guard each record so one bad row can't abort the whole migration
    // (which runs during startup and must never block the app from opening).
    for (final Person person in people.values.toList()) {
      try {
        final DateTime? birthDate = person.legacyBirthDate;
        final bool hasLegacyHebrewDate =
            person.legacyHebrewBirthYear != null ||
            person.legacyHebrewBirthMonth != null ||
            person.legacyHebrewBirthDay != null;
        if (birthDate == null && !hasLegacyHebrewDate) {
          continue;
        }

        // An age already entered by hand wins — it is the more deliberate
        // value, and it is the one the person's card has been showing.
        if (person.manualAge == null && birthDate != null) {
          person
            ..manualAge = AppDateUtils.calculateAge(birthDate)
            ..manualAgeUpdatedAt = now;
        }

        person
          ..legacyBirthDate = null
          ..legacyHebrewBirthYear = null
          ..legacyHebrewBirthMonth = null
          ..legacyHebrewBirthDay = null;

        await person.save();
      } catch (error, stackTrace) {
        debugPrint(
          'PersonMigrations: skipped ${person.id}: $error\n$stackTrace',
        );
      }
    }

    await settings.put(birthDateMigrationKey, true);
  }

  @visibleForTesting
  static const String photoFolderKey = 'migratedPhotoFolder';

  /// Points every stored photo back at the folder the photos live in now.
  ///
  /// A photo is stored as an absolute path, and iOS moves the app's sandbox
  /// to a new folder on an update — the files come along, the paths written
  /// into the records do not. Every picture then reads as missing: friends'
  /// faces, and the photos of a friend's personal card, which is how a card
  /// arrived with its text and without its pictures. A path whose file is
  /// gone but whose name is in [photosDirectory] is rewritten to it.
  ///
  /// Walks the box only when the folder is not the one it was last time, so
  /// an ordinary launch costs one settings read. Never deletes anything.
  static Future<int> repairPhotoPaths({
    required Box<Person> people,
    required Box<dynamic> settings,
    required String photosDirectory,
  }) async {
    if (settings.get(photoFolderKey) == photosDirectory) {
      return 0;
    }
    String? rebased(String path) {
      if (path.isEmpty || File(path).existsSync()) {
        return null;
      }
      final String name = path.split('/').last.split(r'\').last;
      final String candidate = '$photosDirectory${Platform.pathSeparator}$name';
      return File(candidate).existsSync() ? candidate : null;
    }

    int repaired = 0;
    for (final Person person in people.values.toList()) {
      try {
        bool changed = false;
        final List<String> paths = <String>[
          for (final String path in person.photosPaths) rebased(path) ?? path,
        ];
        for (int i = 0; i < paths.length; i++) {
          if (paths[i] != person.photosPaths[i]) {
            changed = true;
          }
        }
        if (changed) {
          person.photosPaths = paths;
          await person.save();
          repaired++;
        }
      } catch (error, stackTrace) {
        debugPrint(
          'repairPhotoPaths: skipped ${person.id}: $error\n$stackTrace',
        );
      }
    }

    // The matchmaker's own picture and their own card's photos.
    final Object? profilePhoto = settings.get('userPhotoPath');
    if (profilePhoto is String) {
      final String? moved = rebased(profilePhoto);
      if (moved != null) {
        await settings.put('userPhotoPath', moved);
        repaired++;
      }
    }
    final Object? card = settings.get('personalCard.person');
    if (card is String && card.isNotEmpty) {
      try {
        final Object? json = jsonDecode(card);
        if (json is Map<String, dynamic>) {
          bool changed = false;
          for (final String key in <String>['photos', 'photosPaths']) {
            final Object? list = json[key];
            if (list is List) {
              final List<Object?> next = <Object?>[];
              for (final Object? path in list) {
                final String? moved = path is String ? rebased(path) : null;
                changed = changed || moved != null;
                next.add(moved ?? path);
              }
              json[key] = next;
            }
          }
          if (changed) {
            await settings.put('personalCard.person', jsonEncode(json));
            repaired++;
          }
        }
      } on FormatException {
        // An unreadable card is left exactly as it is.
      }
    }
    await settings.put(photoFolderKey, photosDirectory);
    return repaired;
  }
}
