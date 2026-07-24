import 'package:flutter/material.dart';
import 'package:shadchan/widgets/reminders_list.dart';

/// The reminders list shown as a panel that drops down from the top banner, so
/// tapping the bell on the home screen never navigates away from it and the
/// panel reads as an extension of the app bar rather than a centered modal.
abstract final class RemindersPanel {
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'תזכורות',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (BuildContext dialogContext, _, _) {
        final ThemeData theme = Theme.of(dialogContext);
        final Size screen = MediaQuery.of(dialogContext).size;

        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              // Sits right under the top banner rather than floating mid-screen.
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: screen.height * 0.7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.notifications_active_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'תזכורות',
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'סגירה',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: RemindersList(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          shrinkWrap: true,
                          onOpenMatch: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final CurvedAnimation curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
    );
  }
}
