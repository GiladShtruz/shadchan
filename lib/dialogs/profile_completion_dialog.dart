import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// Shown once, after an update, to a matchmaker whose profile is missing a
/// photo or their details — see `CommunityPromptGate`.
///
/// The reason is the whole message: friends who keep a personal card, and
/// other matchmakers, decide whom to let into their card or database by
/// recognising a face and a name.
abstract final class ProfileCompletionDialog {
  /// True when the matchmaker chose to complete the profile now.
  static Future<bool?> show(BuildContext context, {Gender? userGender}) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final bool dark = theme.brightness == Brightness.dark;
        final Color blue = dark ? AppColors.primaryDarkDm : AppColors.primary;
        return AlertDialog(
          icon: CircleAvatar(
            radius: 28,
            backgroundColor: blue.withValues(alpha: dark ? 0.2 : 0.12),
            child: Icon(Icons.add_a_photo_outlined, color: blue, size: 26),
          ),
          title: const Text(
            'כדאי להשלים את הפרופיל',
            textAlign: TextAlign.center,
          ),
          content: Text(
            '{הוסף|הוסיפי} תמונה ופרטים שלך כ{שדכן|שדכנית}. כך חברים '
                    'ושדכנים אחרים יזהו אותך בקלות — ויוכלו לתת לך גישה '
                    'לכרטיסים ולמאגרים שלהם.'
                .forGender(userGender),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('אחר כך'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('להשלמת הפרופיל'),
            ),
          ],
        );
      },
    );
  }
}
