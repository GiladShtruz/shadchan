import 'package:flutter/material.dart';

/// The optional follow-up to picking a reminder date: "להוסיף הערה
/// לתזכורת?".
///
/// Skipping is a first-class answer — the note is there for the matchmaker who
/// wants to remember *why* they are coming back, and never a step to get past.
abstract final class ReminderNoteDialog {
  /// Returns the note, an empty string when the note was cleared, or null when
  /// the matchmaker skipped.
  static Future<String?> show(
    BuildContext context, {
    String title = 'להוסיף הערה לתזכורת?',
    String? initialNote,
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _ReminderNoteDialog(title: title, initialNote: initialNote),
    );
  }
}

class _ReminderNoteDialog extends StatefulWidget {
  const _ReminderNoteDialog({required this.title, this.initialNote});

  final String title;
  final String? initialNote;

  @override
  State<_ReminderNoteDialog> createState() => _ReminderNoteDialogState();
}

class _ReminderNoteDialogState extends State<_ReminderNoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNote ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'לא חובה — אפשר גם לדלג.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'למשל: לבדוק אם חזרה מההפסקה',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('דילוג'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}
