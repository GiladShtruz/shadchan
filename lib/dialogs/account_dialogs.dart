import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/account_switch.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Leaving, deleting and restoring an account — the same dialogs wherever they
/// are reached from (the profile's foot, "החשבון שלי", the recovery screen).
abstract final class AccountDialogs {
  /// "להתנתק מהחשבון?" and two buttons, nothing more.
  ///
  /// Nothing has to be explained: the database is the account's, signing in
  /// again on any phone brings all of it back, and there is no backup that
  /// could fail and no reason to refuse.
  static Future<void> confirmSignOut(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('להתנתק מהחשבון?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('התנתקות'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await signOut(context);
  }

  /// Signs out and clears the device, without asking.
  static Future<void> signOut(BuildContext context) async {
    final GoRouter router = GoRouter.of(context);
    await AccountSwitch.signOutAndClear(
      account: context.read<AccountProvider>(),
      sync: context.read<SyncProvider>(),
      people: context.read<PersonRepository>(),
      matches: context.read<MatchRepository>(),
      profile: context.read<UserProfileProvider>(),
      personalCard: context.read<PersonalCardProvider>(),
      cardAccess: context.read<CardAccessProvider>(),
      inbox: context.read<InboxProvider>(),
      community: context.read<CommunityProvider>(),
    );
    router.go('/sign-in');
  }

  /// Deletes the account — into 30 days of grace, not at once.
  static Future<void> confirmDeleteAccount(BuildContext context) async {
    final AccountProvider account = context.read<AccountProvider>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('למחוק את החשבון?'),
          content: const Text(
            'החשבון וכל המאגר שבו — החברים, הרעיונות, ההערות, ההקלטות '
            'והתמונות — יימחקו בעוד 30 יום, וכבר עכשיו יוסרו מהקהילה.\n\n'
            'עד אז אפשר להתחבר שוב ולשחזר הכול. אחרי 30 יום המחיקה סופית.',
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('מחיקת החשבון'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    String? password;
    if (account.deletionRequiresPassword) {
      password = await askPassword(context, confirmLabel: 'אימות ומחיקה');
      if (password == null || !context.mounted) {
        return;
      }
    }

    final GoRouter router = GoRouter.of(context);
    final OverlayState? notices = AppNotice.capture(context);
    final AccountDeletionResult result =
        await AccountSwitch.requestDeletionAndLeave(
          account: account,
          sync: context.read<SyncProvider>(),
          people: context.read<PersonRepository>(),
          matches: context.read<MatchRepository>(),
          profile: context.read<UserProfileProvider>(),
          personalCard: context.read<PersonalCardProvider>(),
          cardAccess: context.read<CardAccessProvider>(),
          inbox: context.read<InboxProvider>(),
          community: context.read<CommunityProvider>(),
          password: password,
        );
    if (result.outcome == AccountDeletionOutcome.canceled) {
      return;
    }
    if (result.outcome != AccountDeletionOutcome.success) {
      AppNotice.showOn(
        notices,
        result.message ?? 'לא הצלחנו למחוק את החשבון. כדאי לנסות שוב.',
      );
      return;
    }
    router.go('/sign-in');
    AppNotice.showOn(
      notices,
      'החשבון יימחק בעוד 30 יום. עד אז אפשר להתחבר ולשחזר אותו.',
    );
  }

  /// Erases the account now, from the recovery screen — no grace left.
  static Future<void> confirmDeleteNow(BuildContext context) async {
    final AccountProvider account = context.read<AccountProvider>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('למחוק לצמיתות עכשיו?'),
          content: const Text(
            'החשבון וכל המאגר יימחקו מיד. אי אפשר לבטל את הפעולה או לשחזר את '
            'המידע אחריה. פניות תמיכה שכבר נשלחו נשמרות לפי מדיניות הפרטיות.',
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('מחיקה לצמיתות'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    String? password;
    if (account.deletionRequiresPassword) {
      password = await askPassword(context, confirmLabel: 'אימות ומחיקה');
      if (password == null || !context.mounted) {
        return;
      }
    }
    final GoRouter router = GoRouter.of(context);
    final OverlayState? notices = AppNotice.capture(context);
    final AccountDeletionResult result =
        await AccountSwitch.deleteAccountAndClear(
          account: account,
          sync: context.read<SyncProvider>(),
          people: context.read<PersonRepository>(),
          matches: context.read<MatchRepository>(),
          profile: context.read<UserProfileProvider>(),
          personalCard: context.read<PersonalCardProvider>(),
          community: context.read<CommunityProvider>(),
          password: password,
        );
    if (result.outcome == AccountDeletionOutcome.canceled) {
      return;
    }
    if (result.outcome != AccountDeletionOutcome.success) {
      AppNotice.showOn(
        notices,
        result.message ?? 'לא הצלחנו למחוק את החשבון. כדאי לנסות שוב.',
      );
      return;
    }
    router.go('/sign-in');
  }

  /// The recovery date, said the way a person says a date.
  static String dueLabel(DateTime due) => AppDateUtils.formatDate(due);

  /// One password field in a dialog. Null when dismissed.
  static Future<String?> askPassword(
    BuildContext context, {
    String title = 'אימות',
    String label = 'הסיסמה שלך',
    required String confirmLabel,
  }) async {
    final TextEditingController controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              onSubmitted: (String value) {
                if (value.isNotEmpty) {
                  Navigator.of(dialogContext).pop(value);
                }
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    Navigator.of(dialogContext).pop(controller.text);
                  }
                },
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}
