import 'package:flutter/material.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// What "הוספת אנשי קשר" says the first time it is opened.
///
/// A dialog rather than the inline [FirstVisitTip] the screen used to carry:
/// the point being made is not a hint about this screen's controls, it is the
/// reason to use the screen at all — a database is only as good as the number
/// of single friends in it — and that has to be read before the address book
/// is, not noticed above it.
///
/// Shown once and never again; the screen decides that through
/// `FirstVisitTips.takeFirstVisit` and only calls this when the answer is yes.
abstract final class AddContactsIntroDialog {
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        // Read here rather than at the call site: the screen opens this from a
        // post-frame callback, and `context.userGender` watches — which is
        // only legal while something is building.
        final Gender? gender = dialogContext.userGender;
        final ThemeData theme = Theme.of(dialogContext);
        final bool dark = theme.brightness == Brightness.dark;
        final Color lead = dark
            ? theme.colorScheme.primary
            : AppColors.primaryDark;

        return AlertDialog(
          icon: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lead.withValues(alpha: dark ? 0.24 : 0.12),
            ),
            child: Icon(Icons.group_add_outlined, color: lead, size: 24),
          ),
          title: const Text('הוספת אנשי קשר למאגר'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String paragraph in _paragraphs) ...<Widget>[
                Text(
                  paragraph.forGender(gender),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.style, size: 18, color: lead),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'טיפ: בתצוגת ההחלקה אפשר לעבור על אנשי הקשר במהירות.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        );
      },
    );
  }

  /// The explanation itself, in the app's `{זכר|נקבה}` form.
  static const List<String> _paragraphs = <String>[
    '{בחר|בחרי} איש קשר כדי להוסיף אותו למאגר שלך.',
    'ככל {שתוסיף|שתוסיפי} יותר אנשי קשר, המאגר שלך יהיה רלוונטי ומדויק יותר.',
    'מומלץ להוסיף את כל אנשי הקשר הרווקים שלך כדי להרחיב את המאגר האישי, '
        'גם אם {אתה לא בקשר|את לא בקשר} שוטף איתם.',
  ];
}
