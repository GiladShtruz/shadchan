import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_version.dart';
import 'package:shadchan/utils/privacy_policy_text.dart';

/// The privacy policy as an [AboutDialog], opened from the overflow menu.
///
/// The same text also has a full screen of its own at `/privacy-policy`, which
/// is where the settings link goes. This is the short way to it — the menu is
/// the one place in the app somebody looks when they want to know what it does
/// with their data and have no intention of hunting through settings first.
///
/// **One dialog, two languages.** The button sits above the text rather than
/// below it, because a reader who cannot read the Hebrew must not have to
/// scroll nineteen sections to find the way out of it. The label always names
/// the language it switches *to*, for the same reason.
class PrivacyPolicyDialog extends StatefulWidget {
  const PrivacyPolicyDialog({super.key, this.version = ''});

  /// The app version shown under the name. Empty hides the line — an unknown
  /// version is better left out than printed as "unknown".
  final String version;

  /// Reads the version first, then opens. Awaiting before the dialog rather
  /// than inside it keeps the header from rebuilding under the reader's eyes a
  /// frame after it appeared.
  static Future<void> show(BuildContext context) async {
    final String number = await AppVersion.read();
    // A platform channel that cannot answer is no reason to withhold the
    // policy. The line simply does not appear.
    final String version = number.isEmpty ? '' : 'גרסה $number';
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => PrivacyPolicyDialog(version: version),
    );
  }

  @override
  State<PrivacyPolicyDialog> createState() => _PrivacyPolicyDialogState();
}

class _PrivacyPolicyDialogState extends State<PrivacyPolicyDialog> {
  bool _english = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AboutDialog(
      applicationName: 'שדכן',
      applicationVersion: widget.version.isEmpty ? null : widget.version,
      applicationIcon: Image.asset(
        'assets/logo_mark.png',
        width: 42,
        height: 42,
        // The mark is drawn white so one file can serve both themes; without a
        // tint it is invisible on the dialog's light surface.
        color: theme.colorScheme.primary,
      ),
      children: <Widget>[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _english = !_english),
            icon: const Icon(Icons.translate_rounded, size: 18),
            label: Text(
              _english
                  ? PrivacyPolicyText.toHebrewLabel
                  : PrivacyPolicyText.toEnglishLabel,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _english
              ? PrivacyPolicyText.englishTitle
              : PrivacyPolicyText.hebrewTitle,
          textDirection: _english ? TextDirection.ltr : TextDirection.rtl,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        // The English text has to be laid out left-to-right even though the app
        // itself is an RTL app, or every paragraph ends up with its full stop
        // on the wrong side.
        Directionality(
          textDirection: _english ? TextDirection.ltr : TextDirection.rtl,
          child: SelectionArea(
            child: Text(
              _english ? PrivacyPolicyText.english : PrivacyPolicyText.hebrew,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
