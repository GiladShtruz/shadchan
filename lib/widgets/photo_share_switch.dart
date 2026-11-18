import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';

/// "התמונה שלי לא ניתנת לשיתוף" — the single's choice that the matchmakers
/// they gave access see the card's photos inside שדכן and never share them
/// out of the app.
///
/// **Explained at the moment of choosing.** Turning it on asks once, in
/// plain words, what it does and what it does not do — a matchmaker still
/// sees the photo, they cannot send it on — and only then saves.
class PhotoShareSwitch extends StatelessWidget {
  const PhotoShareSwitch({super.key});

  static const String title = 'התמונה שלי לא ניתנת לשיתוף';

  static const String subtitle =
      'השדכנים שנתת להם גישה יראו את התמונות בתוך שדכן, אבל לא יוכלו לשתף '
      'אותן החוצה.';

  static String explanationFor(BuildContext context) =>
      'השדכנים שנתת להם גישה ימשיכו לראות את התמונות שלך בתוך שדכן, כדי '
              'לחשוב {עליך|עלייך}. כשהם ישתפו את הכרטיס שלך ב־WhatsApp או '
              'בכל דרך אחרת, התמונות לא יצורפו — רק הטקסט.'
          .forGender(context.userGender);

  /// Asks before turning it on. True to go ahead.
  static Future<bool> confirm(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(title),
        content: Text(explanationFor(dialogContext)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('אישור'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    return SwitchListTile(
      key: const ValueKey<String>('photo-share-switch'),
      value: !cards.photosShareable,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 0),
      secondary: Icon(
        Icons.lock_outline_rounded,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
      onChanged: (bool private) async {
        if (private && !await confirm(context)) {
          return;
        }
        await cards.setPhotosShareable(!private);
      },
    );
  }
}
