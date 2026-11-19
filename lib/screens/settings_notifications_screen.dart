import 'package:flutter/material.dart';
import 'package:shadchan/services/notification_preferences.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "התראות" — which kinds of notification to receive, one switch each.
///
/// Every kind is on until it is switched off. The choice is saved to the
/// account (every phone of it follows), the server stops pushing a kind that
/// is off, and the notifications page and the bell stop showing it. Nothing
/// already received is deleted — switching a kind back on shows it again.
class SettingsNotificationsScreen extends StatelessWidget {
  const SettingsNotificationsScreen({super.key});

  static IconData _iconOf(NotificationCategory category) => switch (category) {
    NotificationCategory.ideas => Icons.lightbulb_outline_rounded,
    NotificationCategory.cardFriends => Icons.badge_outlined,
    NotificationCategory.newMatchmakers => Icons.person_add_alt_outlined,
    NotificationCategory.access => Icons.key_outlined,
    NotificationCategory.celebrations => Icons.celebration_outlined,
    NotificationCategory.network => Icons.diversity_3_outlined,
    NotificationCategory.chats => Icons.chat_bubble_outline_rounded,
    NotificationCategory.system => Icons.campaign_outlined,
    NotificationCategory.support => Icons.forum_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('התראות')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: NotificationPreferences.instance,
          builder: (BuildContext context, _) {
            final NotificationPreferences prefs =
                NotificationPreferences.instance;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'אפשר לבחור אילו סוגי התראות לקבל. הבחירה נשמרת בחשבון '
                    'ותחול על כל המכשירים שלך.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SettingsGroup(
                  title: 'סוגי התראות',
                  children: <Widget>[
                    for (final NotificationCategory category
                        in NotificationCategory.values)
                      SwitchListTile(
                        key: ValueKey<String>('notif:${category.name}'),
                        secondary: Icon(
                          _iconOf(category),
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(category.label),
                        subtitle: Text(category.description),
                        value: prefs.wants(category),
                        onChanged: (bool on) =>
                            prefs.set(category, enabled: on),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
