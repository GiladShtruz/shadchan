import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// One-time data migrations for proposals, run at startup before the UI builds.
abstract final class MatchMigrations {
  @visibleForTesting
  static const String availabilityMigrationKey = 'migratedMatchAvailability';

  /// Brings existing data in line with the rules that now run automatically:
  /// a proposal waits while either side is busy or on a break and reopens once
  /// both are free, and a couple that is dating is marked "תפוס" on both cards.
  ///
  /// Without this, records saved by earlier versions would keep their old
  /// status until someone happened to change something. Runs once — a flag in
  /// the settings box keeps later launches from walking the boxes again. No
  /// journal notes are written: this is a silent backfill, not something the
  /// matchmaker did.
  static Future<void> reconcileStatusesWithAvailability({
    required Box<MatchIdea> matches,
    required Box<Person> people,
    required Box<dynamic> settings,
  }) async {
    if (settings.get(availabilityMigrationKey) == true) {
      return;
    }

    final DateTime now = DateTime.now();
    // Iterate copies so saving a record cannot disturb the live iterator, and
    // guard each record so one bad row can't abort startup.
    for (final MatchIdea match in matches.values.toList()) {
      try {
        final Person? personA = people.get(match.personAId);
        final Person? personB = people.get(match.personBId);

        if (match.status == MatchStatus.dating) {
          for (final Person? person in <Person?>[personA, personB]) {
            if (person != null &&
                person.profileStatus != ProfileStatus.busy &&
                !person.profileStatus.isArchived) {
              person
                ..profileStatus = ProfileStatus.busy
                ..updatedAt = now;
              await person.save();
            }
          }
          continue;
        }

        final bool eitherPaused =
            (personA?.profileStatus.pausesMatches ?? false) ||
            (personB?.profileStatus.pausesMatches ?? false);

        final MatchStatus? target = switch (match.status) {
          MatchStatus.idea ||
          MatchStatus.checking => eitherPaused ? MatchStatus.unavailable : null,
          MatchStatus.unavailable => eitherPaused ? null : MatchStatus.idea,
          _ => null,
        };

        if (target == null) {
          continue;
        }

        match
          ..status = target
          ..updatedAt = now;
        await match.save();
      } catch (error, stackTrace) {
        debugPrint('MatchMigrations: skipped ${match.id}: $error\n$stackTrace');
      }
    }

    await settings.put(availabilityMigrationKey, true);
  }
}
