import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// Who is being asked for their number, which decides what the dialog says.
enum MyPhonePurpose {
  /// The card owner: friends who match find their card by it.
  cardOwner,

  /// A matchmaker asking a friend for access: the friend's app checks that
  /// they have each other saved, and links the card, by it.
  matchmakerRequest,

  /// A matchmaker's own number, asked once: friends who keep a personal card
  /// find them by it under "החברים שלי שמשדכים בשדכן".
  matchmaker,
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
    /// an explicit "דילוג".
    bool required = false,
    MyPhonePurpose purpose = MyPhonePurpose.cardOwner,
  }) async {
    final MyPhoneOutcome outcome = await showForSignUp(
      context,
      initial: initial,
      required: required,
      purpose: purpose,
    );
    return outcome.phone;
  }

  /// The sign-up step: the same dialog, which can also notice that the number
  /// already belongs to another account and ask what to do about it.
  ///
  /// [belongsToAnotherAccount] answers whether the number is already in the
  /// system under a different account. Left out, nothing is checked.
  static Future<MyPhoneOutcome> showForSignUp(
    BuildContext context, {
    String? initial,
    bool required = true,
    MyPhonePurpose purpose = MyPhonePurpose.cardOwner,
    Future<bool> Function(String phone)? belongsToAnotherAccount,
  }) async {
    final MyPhoneOutcome? outcome = await showDialog<MyPhoneOutcome>(
      context: context,
      barrierDismissible: !required,
      builder: (BuildContext dialogContext) => _MyPhoneDialog(
        initial: initial,
        required: required,
        purpose: purpose,
        belongsToAnotherAccount: belongsToAnotherAccount,
      ),
    );
    return outcome ?? const MyPhoneOutcome.skipped();
  }
}

/// How the phone step ended.
class MyPhoneOutcome {
  const MyPhoneOutcome.saved(String this.phone) : useExistingAccount = false;

  const MyPhoneOutcome.skipped() : phone = null, useExistingAccount = false;

  /// The number is already in the system and the user chose to sign in to
  /// that account instead of going on with this one.
  const MyPhoneOutcome.useExistingAccount()
    : phone = null,
      useExistingAccount = true;

  /// The number to save, or null when skipped.
  final String? phone;

  final bool useExistingAccount;
}

class _MyPhoneDialog extends StatefulWidget {
  const _MyPhoneDialog({
    required this.initial,
    required this.required,
    required this.purpose,
    this.belongsToAnotherAccount,
  });

  final String? initial;
  final bool required;
  final MyPhonePurpose purpose;
  final Future<bool> Function(String phone)? belongsToAnotherAccount;

  @override
  State<_MyPhoneDialog> createState() => _MyPhoneDialogState();
}

class _MyPhoneDialogState extends State<_MyPhoneDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );
  String? _error;
  bool _checking = false;

  /// The user's gender, as last drawn — `userGender` watches, so it can only
  /// be read in `build`, and the follow-up question needs it outside.
  Gender? _gender;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) {
      return;
    }
    final String text = _controller.text.trim();
    if (PhoneIdentity.canonical(text) == null) {
      setState(() => _error = 'צריך מספר טלפון מלא');
      return;
    }
    final Future<bool> Function(String phone)? check =
        widget.belongsToAnotherAccount;
    if (check != null) {
      setState(() => _checking = true);
      bool taken = false;
      try {
        taken = await check(text);
      } on Object {
        // No answer is not a reason to stop somebody signing up: the number
        // is saved and the account goes on as usual.
        taken = false;
      }
      if (!mounted) {
        return;
      }
      setState(() => _checking = false);
      if (taken) {
        final bool? useExisting = await _askAboutExisting();
        if (!mounted || useExisting == null) {
          return;
        }
        Navigator.of(context).pop(
          useExisting
              ? const MyPhoneOutcome.useExistingAccount()
              : MyPhoneOutcome.saved(text),
        );
        return;
      }
    }
    Navigator.of(context).pop(MyPhoneOutcome.saved(text));
  }

  /// True to sign in to the account that already has this number, false to
  /// go on creating another one with it, null when the question is closed.
  Future<bool?> _askAboutExisting() {
    final Gender? gender = _gender;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('המספר כבר קיים'),
        content: Text(
          'מספר הטלפון הזה כבר קיים במערכת. מה {תרצה|תרצי} לעשות?'.forGender(
            gender,
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 4,
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('התחברות לחשבון הקיים'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('יצירת חשבון נוסף עם מספר זה'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = context.userGender;
    _gender = gender;
    final (String title, String lead, String note) = switch (widget.purpose) {
      MyPhonePurpose.matchmakerRequest => (
        'מספר הטלפון שלך',
        'כדי לוודא שאתם שמורים אחד אצל השני ולסנכרן נכון את הכרטיס, '
            '${'{הזן|הזיני}'.forGender(gender)} את מספר הטלפון שלך.',
        'המספר ישמש לזיהוי וסנכרון מול החבר.',
      ),
      MyPhonePurpose.matchmaker => (
        'המספר שלי',
        'אנשי קשר שלך שמנהלים כרטיס אישי ב״שדכן״ יראו אותך ברשימת החברים '
            'שמשדכים, ויוכלו לתת לך גישה לכרטיס שלהם.',
        'המספר משמש רק לזיהוי בין חברים ולא מוצג לאף אחד.',
      ),
      MyPhonePurpose.cardOwner => (
        'המספר שלי',
        'המספר שהחברים שלך שמרו אצלם. לפיו חברים שמשדכים ימצאו את הכרטיס '
            'שלך.',
        'הוא לא מופיע בכרטיס ולא נשלח בשיתוף.',
      ),
    };
    return AlertDialog(
      scrollable: true,
      title: Text(title),
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
      // "שמירה" at the start edge — the right, in RTL — and filled, because
      // it is the answer the step is asking for; skipping is the quiet one on
      // the other side.
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('שמירה'),
        ),
        TextButton(
          onPressed: _checking
              ? null
              : () => Navigator.of(context).pop(const MyPhoneOutcome.skipped()),
          style: TextButton.styleFrom(foregroundColor: AppColors.mutedInk),
          child: Text(widget.required ? 'דילוג' : 'ביטול'),
        ),
      ],
    );
  }
}
