import 'package:flutter/material.dart';
import 'package:shadchan/providers/add_contacts_session.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/widgets/empty_state.dart';

/// Everything the add-contacts screen says *instead of* a list, in one place,
/// so the list and the swipe deck can never disagree about it.
///
/// Five situations, each with its own sentence and its own way out — the
/// failure the user hit before was that all of them looked like the same
/// empty screen:
/// 1. Access not asked yet: why it is needed, then the system question.
/// 2. Access refused: ask again.
/// 3. Access blocked for good: the way to the device settings, picked up on
///    return without closing anything.
/// 4. Access granted, the read failed: try again.
/// 5. Access granted, the phone has no contacts / none with a mobile number.
///
/// Returns null when there is a list to show.
abstract final class ContactsAccessState {
  static Widget? viewFor(AddContactsSession session) {
    if (session.awaitingPermissionRequest) {
      return _Framed(
        child: EmptyState(
          icon: Icons.contacts_outlined,
          title: 'גישה לאנשי הקשר',
          subtitle:
              'כדי {שתוכל|שתוכלי} למצוא ולהוסיף בקלות חברים {שאתה|שאת} כבר {מכיר|מכירה}, שדכן צריכה גישה לאנשי הקשר שלך. רק מי {שתבחר|שתבחרי} להוסיף נכנס למאגר.',
          buttonText: 'לאפשר גישה לאנשי קשר',
          onButtonPressed: session.requestAccess,
        ),
      );
    }

    final ContactsPermissionState? permission = session.permissionState;
    if (permission == ContactsPermissionState.permanentlyDenied) {
      return _Framed(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EmptyState(
              icon: Icons.contact_phone_outlined,
              title: 'הגישה לאנשי הקשר חסומה',
              subtitle:
                  'בהגדרות המכשיר: הרשאות ← אנשי קשר ← לאפשר. אחרי החזרה לכאן הרשימה תיטען מעצמה.',
              buttonText: 'פתיחת הגדרות המכשיר',
              onButtonPressed: session.openSettingsAndRecheck,
            ),
            TextButton(
              onPressed: session.load,
              child: const Text('בדיקה מחדש'),
            ),
          ],
        ),
      );
    }
    if (permission == ContactsPermissionState.denied) {
      return _Framed(
        child: EmptyState(
          icon: Icons.contact_phone_outlined,
          title: 'אין גישה לאנשי הקשר',
          subtitle:
              'בלי גישה אי אפשר להציג את אנשי הקשר מהטלפון. אפשר תמיד להוסיף חברים גם ידנית.',
          buttonText: 'לאפשר גישה לאנשי קשר',
          onButtonPressed: session.requestAccess,
        ),
      );
    }

    if (!session.hasAnyCandidate) {
      if (session.loadFailed) {
        return _Framed(
          child: EmptyState(
            icon: Icons.sync_problem_outlined,
            title: 'לא הצלחנו לטעון את אנשי הקשר',
            subtitle: 'משהו השתבש בקריאת אנשי הקשר מהמכשיר.',
            buttonText: 'לנסות שוב',
            onButtonPressed: session.refresh,
          ),
        );
      }
      if (session.deviceHasNoContacts) {
        return _Framed(
          child: EmptyState(
            icon: Icons.contact_phone_outlined,
            title: 'לא נמצאו אנשי קשר במכשיר',
            subtitle:
                'ספר הטלפונים במכשיר ריק, או שאנשי הקשר עדיין לא סונכרנו מהחשבון.',
            buttonText: 'רענון',
            onButtonPressed: session.refresh,
          ),
        );
      }
      return _Framed(
        child: EmptyState(
          icon: Icons.contact_phone_outlined,
          title: 'לא נמצאו אנשי קשר מתאימים',
          subtitle: 'מוצגים רק אנשי קשר עם שם ומספר נייד',
          buttonText: 'רענון',
          onButtonPressed: session.refresh,
        ),
      );
    }
    return null;
  }
}

/// A slim line over a list that is on screen but could not be refreshed: the
/// list is kept (it is the last good read), and the failure is still said.
class ContactsRefreshFailedBanner extends StatelessWidget {
  const ContactsRefreshFailedBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.sync_problem_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'לא הצלחנו לרענן את אנשי הקשר. מוצגת הרשימה האחרונה.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('לנסות שוב')),
        ],
      ),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: child,
      ),
    );
  }
}
