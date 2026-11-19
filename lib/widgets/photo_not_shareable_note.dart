import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "התמונות לצפייה בשדכן בלבד" — a friend's personal-card photos the owner
/// asked not to be shared out of the app. One small grey line with a lock,
/// under the photos; every share of the card already leaves them out (see
/// `CardPhotoPrivacy`).
class PhotoNotShareableNote extends StatelessWidget {
  const PhotoNotShareableNote({super.key});

  static const String text = 'התמונות לצפייה בשדכן בלבד · לא יצורפו לשיתוף';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = AppColors.muted(
      dark: theme.brightness == Brightness.dark,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 13, color: muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
