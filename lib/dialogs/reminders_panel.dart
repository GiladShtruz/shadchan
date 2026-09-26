import 'package:flutter/material.dart';
import 'package:shadchan/widgets/reminders_list.dart';
import 'package:shadchan/widgets/card_inbox_list.dart';
import 'package:shadchan/widgets/support_inbox_list.dart';

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
              // The page's own cream paper with a soft neutral shadow — the
              // same sheet the home screen is printed on, so the panel reads
              // as the top of the app folding down rather than a white box.
              child: Material(
                color: theme.scaffoldBackgroundColor,
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: screen.height * 0.7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 8, 2),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'תזכורות',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'מה שהגיע זמנו — לחיצה לפתיחה, ⋯ לפעולות',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
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
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          children: <Widget>[
                            // Reports and answers sit above the reminders:
                            // both are "something happened that you have not
                            // seen", which is the whole job of this panel.
                            CardInboxList(
                              onOpen: () => Navigator.of(dialogContext).pop(),
                            ),
                            SupportInboxList(
                              onOpen: () => Navigator.of(dialogContext).pop(),
                            ),
                            RemindersList(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              onOpenMatch: () =>
                                  Navigator.of(dialogContext).pop(),
                            ),
                          ],
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
