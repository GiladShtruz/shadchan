import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// Who is being asked for their number, which decides what the dialog says.
enum MyPhonePurpose {
  /// The card owner: friends who match find their card by it.
  cardOwner,

  /// A matchmaker asking a friend for access: the friend's app checks that
  /// they have each other saved, and links the card, by it.
  matchmakerRequest,
}

/// Asks for the user's own phone number — the one their friends have saved.
///
/// It is what connects accounts: friends who match find this person's card
/// by it, and this person's address book finds the matchmakers among their
/// friends by it. Returns the number as typed, or null when dismissed.
///
/// **Scrollable, on purpose.** A phone keyboard takes half the screen, and a
/// fixed dialog with a paragraph above the field overflowed under it — the
/// field and the save button were pushed out of reach, so the number could be
/// neither typed nor saved.
abstract final class MyPhoneDialog {
  static Future<String?> show(
    BuildContext context, {
    String? initial,

    /// During sign-up: the dialog cannot be tapped away, and skipping it is
    /// an explicit "אחר כך".
    bool required = false,
    MyPhonePurpose purpose = MyPhonePurpose.cardOwner,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: !required,
      builder: (BuildContext dialogContext) => _MyPhoneDialog(
        initial: initial,
        required: required,
        purpose: purpose,
      ),
    );
  }
}

class _MyPhoneDialog extends StatefulWidget {
  const _MyPhoneDialog({
    required this.initial,
    required this.required,
    required this.purpose,
  });

  final String? initial;
  final bool required;
  final MyPhonePurpose purpose;

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
    final ThemeData theme = Theme.of(context);
    final bool matchmaker = widget.purpose == MyPhonePurpose.matchmakerRequest;
    final String lead = matchmaker
        ? 'כדי לוודא שאתם שמורים אחד אצל השני ולסנכרן נכון את הכרטיס, '
              '${'{הזן|הזיני}'.forGender(context.userGender)} את מספר הטלפון שלך.'
        : 'המספר שהחברים שלך שמרו אצלם. לפיו חברים שמשדכים ימצאו את הכרטיס '
              'שלך.';
    final String note = matchmaker
        ? 'המספר ישמש לזיהוי וסנכרון מול החבר.'
        : 'הוא לא מופיע בכרטיס ולא נשלח בשיתוף.';
    return AlertDialog(
      scrollable: true,
      title: Text(matchmaker ? 'מספר הטלפון שלך' : 'המספר שלי'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(lead),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.telephoneNumber],
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
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedInk,
            ),
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
