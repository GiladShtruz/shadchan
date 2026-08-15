import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_outcome_dialog.dart';
import 'package:shadchan/dialogs/match_status_sheet.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// The three ways a proposal moves on, offered straight from its card.
enum MatchQuickAction {
  waiting('העברה להמתנה', Icons.pause_rounded),
  dating('מתחילים לצאת', Icons.celebration_outlined),
  close('סגירת הצעה', Icons.close_rounded);

  const MatchQuickAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Running a proposal from the list, without opening it.
///
/// The proposal screen has richer versions of all of these — a reminder note,
/// a confirmation on a wedding, the full journal. This is deliberately the
/// short road: a matchmaker running down רעיונות after a round of phone calls
/// is updating five proposals, and five round trips into a detail screen and
/// back is what makes people stop updating statuses at all.
///
/// Everything still goes through the same repository calls the detail screen
/// uses, so a status set from here is indistinguishable from one set there —
/// same journal entries, same history on both candidates.
abstract final class MatchQuickActions {
  static Future<void> run(
    BuildContext context,
    MatchQuickAction action,
    MatchIdea match,
  ) async {
    final MatchRepository repository = context.read<MatchRepository>();
    switch (action) {
      case MatchQuickAction.waiting:
        await _moveToWaiting(context, repository, match);
      case MatchQuickAction.dating:
        await repository.updateStatus(match.id, MatchStatus.dating);
      case MatchQuickAction.close:
        await _close(context, repository, match);
    }
  }

  /// The availability values a matchmaker sets by hand, per side, from the
  /// chip under each name. `mazelTov` is left out — the app sets that itself
  /// when a proposal ends in a wedding.
  static Future<void> setPersonStatus(
    BuildContext context,
    Person person,
    ProfileStatus status,
  ) async {
    if (person.profileStatus == status) {
      return;
    }
    final PersonRepository repository = context.read<PersonRepository>();
    await repository.updateProfileStatus(person.id, status);
    if (!status.pausesMatches || !context.mounted) {
      return;
    }
    // Marking someone busy or on a break already moved their proposals to
    // "בהמתנה". The only open question left is when to look at them again.
    final ReminderChoice? when = await ReminderPickerSheet.show(
      context,
      title: 'מתי להזכיר לך לבדוק שוב?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    final DateTime? date = when?.date;
    if (date != null) {
      await repository.setPersonReminder(person.id, date);
    }
  }

  static Future<void> _moveToWaiting(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('למה ההצעה בהמתנה?')),
              for (final String option in <String>[
                ...MatchWaitingReasons.options,
                MatchWaitingReasons.noReason,
              ])
                ListTile(
                  title: Text(option),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(option == MatchWaitingReasons.noReason ? '' : option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (reason == null || !context.mounted) {
      return;
    }

    final ReminderChoice? when = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור לבדוק?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    await repository.setWaiting(
      match.id,
      reason: reason,
      checkAgainOn: when?.date,
    );
  }

  /// Closes a proposal that never reached "מתחילים לצאת" — which is every
  /// proposal this control is offered on, since a couple who are out are shown
  /// their own actions instead. So there is no "did they date?" question: it is
  /// asked straight why the idea did not progress.
  static Future<void> _close(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final ({MatchOutcomeParty party, String note})? outcome =
        await MatchOutcomeDialog.show(context, MatchStatus.rejected);
    if (outcome == null) {
      return;
    }
    await repository.recordOutcome(
      match.id,
      newStatus: MatchStatus.rejected,
      party: outcome.party,
      note: outcome.note.isEmpty ? null : outcome.note,
    );
  }
}
