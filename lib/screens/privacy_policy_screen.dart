import 'package:flutter/material.dart';
import 'package:shadchan/utils/privacy_policy_text.dart';

/// The privacy policy in full, reached from the settings and from the plain
/// language privacy page.
///
/// The text itself lives in [PrivacyPolicyText] rather than here, because the
/// overflow menu shows the same policy in a dialog and two copies of a legal
/// document is how they drift apart.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  bool _english = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _english
              ? PrivacyPolicyText.englishTitle
              : PrivacyPolicyText.hebrewTitle,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              // Above the text, not below it: somebody who cannot read the
              // language on screen must not have to scroll past all of it to
              // find the way out.
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
              const SizedBox(height: 8),
              Text(
                _english
                    ? PrivacyPolicyText.englishTitle
                    : PrivacyPolicyText.hebrewTitle,
                textDirection: _english
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              // The English text is laid out left-to-right inside an otherwise
              // right-to-left app.
              Directionality(
                textDirection: _english
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                child: Text(
                  _english
                      ? PrivacyPolicyText.english
                      : PrivacyPolicyText.hebrew,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
