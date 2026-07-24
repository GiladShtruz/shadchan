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
}
