import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
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

  @visibleForTesting
  static const String unearnedRemindersKey = 'migratedUnearnedMonthlyReminders';

  /// **The monthly reminder belongs to activity, not to an update.**
  ///
  /// Older versions gave every live idea without a reminder the app's monthly
  /// one at each launch — so an update (or a new phone) armed a reminder on
  /// every old idea at the same moment, and a month later they all came due
  /// together. That backfill is gone: an idea gets its monthly reminder when it
  /// is opened, and it moves with every act on it
  /// (`MatchRepository._restartDefaultReminder`).
  ///
  /// This clears, once per device, the default reminders that backfill wrote:
  /// an app-default reminder (never one the matchmaker set by hand) dated more
  /// than a month after anything happened on the idea. A reminder that is a
  /// month after the idea's last act — the ones activity earns — is kept.
  static Future<void> retireUnearnedMonthlyReminders({
    required Box<MatchIdea> matches,
    required Iterable<MatchNote> notes,
    required Box<dynamic> settings,
  }) async {
    if (settings.get(unearnedRemindersKey) == true) {
      return;
    }
    final Map<String, DateTime> lastNote = <String, DateTime>{};
    for (final MatchNote note in notes) {
      final DateTime? seen = lastNote[note.matchId];
      if (seen == null || note.createdAt.isAfter(seen)) {
        lastNote[note.matchId] = note.createdAt;
      }
    }
    for (final MatchIdea match in matches.values.toList()) {
      final DateTime? reminder = match.reminderDate;
      if (reminder == null ||
          match.reminderNote != MatchRepository.defaultReminderNote) {
        continue;
      }
      DateTime last = match.createdAt;
      for (final DateTime? at in <DateTime?>[
        match.updatedAt,
        lastNote[match.id],
      ]) {
        if (at != null && at.isAfter(last)) last = at;
      }
      // A day of slack over the month the repository adds.
      final DateTime earned = MatchRepository.defaultReminderFrom(
        last,
      ).add(const Duration(days: 1));
      if (!reminder.isAfter(earned)) {
        continue;
      }
      try {
        match
          ..reminderDate = null
          ..reminderNote = null;
        await match.save();
      } catch (error) {
        debugPrint('MatchMigrations: reminder kept on ${match.id}: $error');
      }
    }
    await settings.put(unearnedRemindersKey, true);
  }
}
