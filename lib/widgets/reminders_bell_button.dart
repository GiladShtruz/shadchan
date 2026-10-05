import 'package:flutter/material.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/notification_center.dart';

/// The bell, drawn the same way in the same slot on every main screen.
///
/// Its number is exactly the rows on the notifications page that have not
/// been read — counted by [NotificationCenter], the same count the app icon's
/// badge carries — and a tap opens that page.
class RemindersBellButton extends StatelessWidget {
  const RemindersBellButton({super.key, this.boxed = false});

  /// Draws the bell as one of the home bar's rounded squares instead of a bare
  /// icon button.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReminderLog.instance,
      builder: (BuildContext context, _) {
        final int unread = NotificationCenter.unreadCount(context);
        void open() => AppNavigation.open(context, '/reminders');
        final Icon icon = Icon(
          unread > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_outlined,
        );
        if (boxed) {
          return HomeBarButton(
            tooltip: 'התראות',
            badgeCount: unread,
            onPressed: open,
            icon: icon,
          );
        }
        return IconButton(
          tooltip: 'התראות',
          icon: Badge.count(
            count: unread,
            isLabelVisible: unread > 0,
            child: icon,
          ),
          onPressed: open,
        );
      },
    );
  }
}
