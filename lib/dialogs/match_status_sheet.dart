import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// The "עדכון סטטוס" menu that opens over a proposal card. Everything happens
/// in place: picking "בהמתנה" asks why and when to look again, and picking
/// "נדחה" offers to record the reason.
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
        await repository.updateStatus(match.id, picked);
        if (context.mounted) {
          await _askForRejectionNote(context, repository, match);
        }
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.dating:
      case MatchStatus.dated:
      case MatchStatus.married:
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
                      'למה ההצעה ממתינה?',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ),
                for (final String option in <String>[
                  'הוא בהפסקה',
                  'היא בהפסקה',
                  'הוא תפוס',
                  'היא תפוסה',
                ])
                  ListTile(
                    title: Text(option),
                    onTap: () => Navigator.of(sheetContext).pop(option),
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

  static Future<void> _askForRejectionNote(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final TextEditingController controller = TextEditingController();
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('למה ההצעה נדחתה?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'סיבת השלילה (לא חובה)',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('דלג'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('שמירה'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (note != null && note.isNotEmpty) {
      await repository.addNote(match.id, note);
    }
  }
}
