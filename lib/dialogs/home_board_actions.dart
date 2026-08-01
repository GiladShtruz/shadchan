import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';

/// The actions behind "הלוח שלי", shared by the three-dots menus on a person
/// and a proposal and by the small menu on a board card itself.
///
/// Reminders here are the app's real reminders — a person's "לבדוק שוב" date
/// and a proposal's reminder date — so setting one from the board also sends
/// the push notification and shows up in the reminders panel, instead of
/// creating a second, silent kind of reminder.
abstract final class HomeBoardActions {
  /// The menu label for the current state of an item.
  static String menuLabel(HomeItemKind kind, String targetId) {
    return HomeBoardStore.instance.contains(kind, targetId)
        ? 'הסרה מהלוח שלי'
        : 'הוספה ללוח שלי';
  }

  /// Room a [PopupMenuItem] built from [menuItemChild] needs for its two lines.
  static const double menuItemHeight = 60;

  /// The board menu item's body. While an item is not on the board yet, the
  /// label is followed by one small line saying where it will turn up — "הלוח
  /// שלי" means nothing until you have seen it once.
  static Widget menuItemChild(
    BuildContext context,
    HomeItemKind kind,
    String targetId,
  ) {
    final String label = menuLabel(kind, targetId);
    if (HomeBoardStore.instance.contains(kind, targetId)) {
      return Text(label);
    }

    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        const SizedBox(height: 2),
        Text(
          'יופיע בלוח המעקב האישי בעמוד הבית.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Pins or unpins. Returns whether it is pinned afterwards.
  ///
  /// No confirmation bar: the board itself is the feedback, and the menu label
  /// flips the next time it is opened.
  static bool toggle(BuildContext context, HomeItemKind kind, String targetId) {
    return HomeBoardStore.instance.toggle(kind, targetId);
  }

  static void remove(BuildContext context, HomeItemKind kind, String targetId) {
    HomeBoardStore.instance.remove(kind, targetId);
  }

  /// Adds, edits or clears the short note shown on the board card.
  static Future<void> editNote(
    BuildContext context,
    HomeItemKind kind,
    String targetId,
  ) async {
    final HomeBoardEntry? entry = HomeBoardStore.instance.entryFor(
      kind,
      targetId,
    );
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _BoardNoteDialog(initialText: entry?.note ?? '');
      },
    );
    if (note == null) {
      return;
    }
    HomeBoardStore.instance.setNote(kind, targetId, note);
  }

  /// Sets or clears the reminder that the board card shows.
  static Future<void> editReminder(
    BuildContext context,
    HomeItemKind kind,
    String targetId,
  ) async {
    final PersonRepository personRepository = context.read<PersonRepository>();
    final MatchRepository matchRepository = context.read<MatchRepository>();

    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי להזכיר לך?',
      allowClear: true,
    );
    if (choice == null) {
      return;
    }

    switch (kind) {
      case HomeItemKind.person:
        if (choice.date == null) {
          await personRepository.clearPersonReminder(targetId);
        } else {
          await personRepository.setPersonReminder(targetId, choice.date!);
        }
      case HomeItemKind.idea:
        await matchRepository.setReminder(targetId, choice.date);
    }
  }
}

class _BoardNoteDialog extends StatefulWidget {
  const _BoardNoteDialog({required this.initialText});

  final String initialText;

  @override
  State<_BoardNoteDialog> createState() => _BoardNoteDialogState();
}

class _BoardNoteDialogState extends State<_BoardNoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הערה קצרה'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'למשל: לחזור אחרי החג'),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}
