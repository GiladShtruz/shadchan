import 'package:flutter/material.dart';

/// Edits the reusable WhatsApp request-details message.
///
/// The dialog owns its controller so it is disposed only after the dialog
/// route has fully left the Navigator overlay.
class DetailsMessageDialog extends StatefulWidget {
  const DetailsMessageDialog({
    super.key,
    required this.initialMessage,
    required this.showReset,
  });

  final String initialMessage;
  final bool showReset;

  @override
  State<DetailsMessageDialog> createState() => _DetailsMessageDialogState();
}

class _DetailsMessageDialogState extends State<DetailsMessageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialMessage,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('עריכת נוסח ההודעה'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 5,
        maxLines: 12,
      ),
      actions: <Widget>[
        if (widget.showReset)
          TextButton(
            onPressed: () => Navigator.of(context).pop('__reset__'),
            child: const Text('ברירת מחדל'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}
