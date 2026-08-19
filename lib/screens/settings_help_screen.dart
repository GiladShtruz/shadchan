import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "עזרה ומשוב" — the three ways to reach somebody, and nothing else.
///
/// "שליחת תקלה" and "רעיון לשיפור" are one row, because they were always one
/// form: `/support/report` asks which it is on the screen itself, and offering
/// the same destination twice under two names only made the settings longer.
class SettingsHelpScreen extends StatelessWidget {
  const SettingsHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('עזרה ומשוב'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SettingsGroup(
              title: 'איך אפשר לעזור',
              children: <Widget>[
                SettingsRow(
                  icon: Icons.forum_outlined,
                  title: 'שליחת תקלה או רעיון',
                  subtitle: 'טופס אחד לכל פנייה, עם אפשרות לצרף תמונה',
                  onTap: () => context.push('/support/report'),
                ),
                SettingsRow(
                  icon: Icons.help_outline_rounded,
                  title: 'עזרה והדרכה',
                  onTap: () => context.push('/support/help'),
                ),
                SettingsRow(
                  icon: Icons.mail_outline_rounded,
                  title: 'יצירת קשר',
                  subtitle: CommunityLinks.supportEmail,
                  onTap: CommunityLinks.openSupportEmail,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
