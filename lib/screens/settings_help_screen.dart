import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "דיווח תקלות ויצירת קשר" — the two ways to reach a person, and nothing else.
///
/// "שליחת תקלה" and "רעיון לשיפור" are one row, because they were always one
/// form: `/support/report` asks which it is on the screen itself, and offering
/// the same destination twice under two names only made the settings longer.
///
/// **The help centre is not here any more.** It has its own row in the profile's
/// settings group, next to this one; carrying it here as well meant "עזרה"
/// appeared twice under two headings, one of them a level deeper than the
/// other, and the deeper one was the one people found first.
class SettingsHelpScreen extends StatelessWidget {
  const SettingsHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('דיווח תקלות ויצירת קשר'),
        centerTitle: true,
      ),
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
                  icon: Icons.mail_outline_rounded,
                  title: 'יצירת קשר',
                  subtitle: CommunityLinks.supportEmail,
                  onTap: CommunityLinks.openSupportEmail,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'כל פנייה נקראת. אם צירפתם תמונת מסך, קל יותר להבין מה קרה.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
