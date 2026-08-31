import 'package:flutter/material.dart';
import 'package:shadchan/services/call_log_disclosure_service.dart';

/// The one-time explanation shown *before* Android's own permission dialog,
/// the first time the add-contacts flow is about to read the call log.
///
/// This is Google Play's "prominent disclosure" requirement for the
/// `READ_CALL_LOG` permission: the system dialog it triggers explains nothing
/// about *why*, and satisfying the policy means the app says so itself first,
/// with its own accept/decline, before Android ever asks. See
/// [CallLogSortService.loadRecentCallOrderRequestingPermission].
abstract final class CallLogDisclosureDialog {
  /// Shows the disclosure if it has not been acknowledged yet, and returns
  /// whether it is fine to proceed with reading the call log — `true` if it
  /// was already acknowledged in a previous session, or the matchmaker just
  /// agreed; `false` if they declined, in which case the call log stays
  /// untouched and contacts fall back to name order.
  static Future<bool> ensureAcknowledged(BuildContext context) async {
    if (await CallLogDisclosureService.wasAcknowledged()) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }

    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('גישה ליומן השיחות'),
          content: const Text(
            'כדי לסדר את אנשי הקשר להוספה לפי מי שדיברתם איתו לאחרונה, '
            'האפליקציה תבקש גישה ליומן השיחות במכשיר. המידע הזה משמש רק '
            'למיון בתוך המכשיר שלך, ולא נשלח או משותף עם אף אחד.\n\n'
            'אפשר להמשיך בלי זה — אנשי הקשר יופיעו לפי שם בלבד.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('לא תודה'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('הבנתי, אפשר להמשיך'),
            ),
          ],
        );
      },
    );

    if (agreed == true) {
      await CallLogDisclosureService.markAcknowledged();
      return true;
    }
    return false;
  }
}
