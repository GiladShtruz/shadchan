import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/engagement_dialogs.dart';
import 'package:shadchan/dialogs/match_outcome_dialog.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/enums.dart';

/// Why a proposal is waiting.
///
/// One list, shared by the proposal screen and the status sheet, because a
/// reason written in one place is read in the other — two lists would drift and
/// the same pause would be worded two ways depending on where it was set.
///
/// They are all about one side being unavailable, which is what a pause
/// actually is. "מחכים לתשובה" was dropped: that is not a pause, it is the
/// ordinary state of an open proposal.
abstract final class MatchWaitingReasons {
  static const List<String> options = <String>[
    'הוא בהפסקה',
    'היא בהפסקה',
    'הוא תפוס',
    'היא תפוסה',
  ];

  /// Offered alongside the rest rather than above them: pausing a proposal
  /// never has to be justified.
  static const String noReason = 'בלי סיבה מיוחדת';
}

/// The "עדכון סטטוס" menu that opens over a proposal card. Everything happens
/// in place: picking "בהמתנה" asks why and when to look again, and picking
/// "נדחה" asks who ended it and why before closing the proposal.
abstract final class MatchStatusSheet {
  static Future<void> show(
    BuildContext context, {
    required MatchIdea match,
    Person? male,
    Person? female,
  }) async {
    final MatchStatus? picked = await showModalBottomSheet<MatchStatus>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'עדכון סטטוס',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ),
                for (final MatchStatus status in <MatchStatus>[
                  MatchStatus.idea,
                  MatchStatus.unavailable,
                  MatchStatus.rejected,
                  MatchStatus.dating,
                  MatchStatus.dated,
                  MatchStatus.married,
                ])
                  ListTile(
                    leading: Text(
                      status.icon,
                      style: const TextStyle(fontSize: 20),
                    ),
                    title: Text(status.displayName),
                    trailing: match.status == status
                        ? Icon(
                            Icons.check,
                            color: Theme.of(sheetContext).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(status),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !context.mounted) {
      return;
    }

    final MatchRepository repository = context.read<MatchRepository>();

    switch (picked) {
      case MatchStatus.unavailable:
        await _moveToWaiting(
          context,
          repository: repository,
          match: match,
          male: male,
          female: female,
        );
      case MatchStatus.rejected:
        // Goes through recordOutcome rather than a bare status change, so
        // closing a proposal from here writes both candidates' history — who
        // ended it and why — exactly like the proposal screen's own
        // "סגירת ההצעה" flow does.
        await _closeAsRejected(context, repository, match);
      case MatchStatus.married:
        // Split out from the plain moves below because this one is also the
        // app's only piece of *outgoing* good news. Recorded only on the
        // transition: re-picking a status the proposal already had is not a
        // second engagement.
        final bool alreadyMarried = match.status == MatchStatus.married;
        await repository.updateStatus(match.id, picked);
        if (alreadyMarried || !context.mounted) {
          return;
        }
        await EngagementFlow.celebrate(
          context,
          firstNameA: male?.firstName ?? '',
          firstNameB: female?.firstName ?? '',
          matchmakerName: context.read<UserProfileProvider>().name ?? '',
        );
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.dating:
      case MatchStatus.dated:
        await repository.updateStatus(match.id, picked);
    }
  }

  /// "בהמתנה" needs a reason — whose side is paused — and then when to look at
  /// the proposal again.
  static Future<void> _moveToWaiting(
    BuildContext context, {
    required MatchRepository repository,
    required MatchIdea match,
    required Person? male,
    required Person? female,
  }) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'למה ההצעה בהמתנה?',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ),
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
          ),
        );
      },
    );

    if (reason == null || !context.mounted) {
      return;
    }

    final ReminderChoice? when = await ReminderPickerSheet.show(
      context,
      title: 'מתי לבדוק שוב?',
    );

    await repository.setWaiting(
      match.id,
      reason: reason,
      checkAgainOn: when?.date,
    );
  }

  /// Closes the proposal as rejected, asking who ended it and why first. The
  /// answers go to [MatchRepository.recordOutcome], which moves the status and
  /// writes the proposal journal plus both candidates' history.
  static Future<void> _closeAsRejected(
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
