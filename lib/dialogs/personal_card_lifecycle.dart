import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Deleting and restoring the owner's card — reached from "ניהול ופרטיות"
/// (deleting) and from wherever the deleted card's place is drawn
/// (restoring). Never from the home page itself: removing the card is not
/// something to be one tap away from while looking at it.
abstract final class PersonalCardLifecycle {
  /// Deletes the card — the card only, never the account or the
  /// matchmaker's side of it. Every matchmaker stops seeing it at once; it
  /// stays restorable indefinitely. True when it was deleted.
  static Future<bool> delete(BuildContext context) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('למחוק את הכרטיס שלך?'),
        content: const Text(
          'השדכנים שקיבלו גישה יפסיקו לראות אותו מיד. החשבון שלך נשאר, '
          'ואפשר לשחזר את הכרטיס בכל עת.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('מחיקה'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) {
      return false;
    }
    final PersonalCardProvider cards = context.read<PersonalCardProvider>();
    final bool ok = await PersonalCardSync.deleteNow();
    if (!context.mounted) {
      return false;
    }
    if (ok) {
      await cards.markDeleted();
      return true;
    }
    AppNotice.show(context, 'לא הצלחנו למחוק כרגע. אפשר לנסות שוב.');
    return false;
  }

  /// Brings the card back as "פנוי", then asks about the old grants.
  static Future<void> restore(BuildContext context) async {
    final PersonalCardProvider cards = context.read<PersonalCardProvider>();
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final Person? restored = await cards.restore();
    final bool ok =
        restored != null && await PersonalCardSync.publishNow(restored);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      await cards.markDeleted();
      if (context.mounted) {
        AppNotice.show(context, 'לא הצלחנו לשחזר כרגע. אפשר לנסות שוב.');
      }
      return;
    }
    if (access.approved.isEmpty) {
      AppNotice.show(context, 'הכרטיס שוחזר');
      return;
    }
    final bool? keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('הכרטיס שוחזר'),
        content: Text(
          '{האם תרצה|האם תרצי} לשחזר גם את אישורי הגישה לשדכנים?'.forGender(
            dialogContext.userGender,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('לא'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('כן, לשחזר'),
          ),
        ],
      ),
    );
    final bool done = keep == true
        ? await access.reawakenApproved()
        : await access.revokeAllApproved();
    if (!done && context.mounted) {
      AppNotice.show(
        context,
        'לא הצלחנו לעדכן את אישורי הגישה. אפשר לנסות שוב.',
      );
    }
  }
}
