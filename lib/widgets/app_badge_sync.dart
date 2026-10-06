import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/widgets/notification_center.dart';

/// Keeps the number on the app's icon equal to the number on the bell.
///
/// Above the router, so it is counting whichever screen is open; it writes
/// the badge only when the count actually changes. A push that arrives while
/// the app is closed sets the icon from the server's own count; the next time
/// the app is open this puts it right again.
class AppBadgeSync extends StatefulWidget {
  const AppBadgeSync({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Off in widget tests, where there is no platform to badge.
  final bool enabled;

  @override
  State<AppBadgeSync> createState() => _AppBadgeSyncState();
}

class _AppBadgeSyncState extends State<AppBadgeSync> {
  int? _shown;

  void _update(int count) {
    if (!widget.enabled || count == _shown) {
      return;
    }
    _shown = count;
    AppBadgePlus.updateBadge(count).catchError((Object error) {
      debugPrint('AppBadgeSync: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReminderLog.instance,
      builder: (BuildContext context, Widget? child) {
        final int count = NotificationCenter.unreadCount(context);
        WidgetsBinding.instance.addPostFrameCallback((_) => _update(count));
        return child!;
      },
      child: widget.child,
    );
  }
}
