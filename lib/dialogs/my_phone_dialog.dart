import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// Asks for the user's own phone number — the one their friends have saved.
///
/// It is what connects accounts: friends who match find this person's card
/// by it, and this person's address book finds the matchmakers among their
/// friends by it. Returns the number as typed, or null when dismissed.
abstract final class MyPhoneDialog {
  static Future<String?> show(
    BuildContext context, {
    String? initial,

    /// During sign-up: the dialog cannot be tapped away, and skipping it is
    /// an explicit "אחר כך".
    bool required = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: !required,
      builder: (BuildContext dialogContext) =>
          _MyPhoneDialog(initial: initial, required: required),
    );
  }
}

class _MyPhoneDialog extends StatefulWidget {
  const _MyPhoneDialog({required this.initial, required this.required});

  final String? initial;
  final bool required;

  @override
  State<_MyPhoneDialog> createState() => _MyPhoneDialogState();
}

class _MyPhoneDialogState extends State<_MyPhoneDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    if (PhoneIdentity.canonical(text) == null) {
      setState(() => _error = 'צריך מספר טלפון מלא');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('המספר שלי'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'המספר שהחברים שלך שמרו אצלם. לפיו חברים שמשדכים ימצאו את הכרטיס '
            'שלך, ולפיו אפשר למצוא אותם. הוא לא מופיע בכרטיס ולא נשלח בשיתוף.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
            ],
            decoration: InputDecoration(
              labelText: 'מספר טלפון',
              hintText: '050-0000000',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.required ? 'אחר כך' : 'ביטול'),
        ),
        FilledButton(onPressed: _submit, child: const Text('שמירה')),
      ],
    );
  }
}
