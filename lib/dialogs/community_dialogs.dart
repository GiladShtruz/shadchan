import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';

/// The three things the app occasionally asks for or announces, and the rules
/// about when it is allowed to.
///
/// They live together because they share one constraint: each interrupts
/// somebody in the middle of their own work, so at most one may appear per
/// launch, and none of them may appear twice for the same reason. The pacing
/// itself is in [CommunityPromptsStore]; what is here is the wording and the
/// shape.

/// "הצטרפות לקבוצת העדכונים" — a quiet group where only the administrators
/// post.
///
/// **Opening the link is not joining.** The invite hands the decision to
/// WhatsApp, and this app never learns what happened there — so only the
/// explicit "אני כבר בקבוצה" stops the reminders. Anything else means the
/// invitation comes back in another hundred actions.
/// "כבר בנית מאגר משמעותי" — the one reminder a matchmaker who skipped signing
/// in ever gets, and the pacing that keeps it one.
///
/// **It is about their database, not about the account.** Somebody who declined
/// once has heard the pitch; repeating it is nagging. What has changed since
/// then is that they now have something worth losing, and that — not the
/// feature list — is the only new thing worth saying.
///
/// Paced in friends rather than in days by [SignInPromptStore], and it rides
/// the same one-prompt-per-launch gate as everything else the app says on its
/// own, at the bottom of the order.
abstract final class SignInReminderDialog {
  static const String title = 'כבר בנית מאגר משמעותי';

  static const String message =
      'כדאי להתחבר כדי לגבות אותו ולשמור עליו גם אם תחליף מכשיר.';

  static Future<void> show(BuildContext context, {required int friends}) async {
    SignInPromptStore.markReminded(friends);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text(title),
          content: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('לא עכשיו'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                dialogContext.push('/sign-in');
              },
              child: const Text('התחברות'),
            ),
          ],
        );
      },
    );
  }
}

abstract final class UpdatesGroupDialog {
  /// [actions] is the running action count when the app raised this by itself,
  /// and null when the matchmaker opened it from the settings or the menu —
  /// there is nothing to pace in that case, because they asked.
  static Future<void> show(BuildContext context, {int? actions}) async {
    if (!CommunityLinks.hasUpdatesGroup) {
      return;
    }
    if (actions != null) {
      CommunityPromptsStore.markUpdatesGroupOffered(actions);
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('קבוצת העדכונים'),
          content: Text(
            'יש קבוצת WhatsApp שקטה שבה אנחנו מפרסמים עדכונים על האפליקציה. '
            'רק המנהלים כותבים בה, אז היא לא מציפה.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          actionsOverflowButtonSpacing: 4,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('לא עכשיו'),
            ),
            TextButton(
              onPressed: () {
                CommunityPromptsStore.markInUpdatesGroup();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('אני כבר בקבוצה'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                CommunityLinks.openLink(CommunityLinks.updatesGroupUrl);
              },
              child: const Text('הצטרפות'),
            ),
          ],
        );
      },
    );
  }
}

/// The rating request: short, positive, and asked only after something good has
/// already happened.
abstract final class RateAppDialog {
  static Future<void> show(BuildContext context, {required int actions}) async {
    if (!CommunityLinks.hasStoreListing) {
      return;
    }
    CommunityPromptsStore.markRatingAsked(actions);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('נעים לנו לשמוע'),
          content: Text(
            'אם האפליקציה עוזרת לך, דירוג קצר בחנות עוזר לשדכנים נוספים למצוא '
            'אותה. זה לוקח פחות מדקה.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('לא עכשיו'),
            ),
            FilledButton(
              onPressed: () {
                // Marked done rather than asked: the app cannot tell whether a
                // review was actually left, and asking somebody who already went
                // to the store is the one thing this must never do.
                CommunityPromptsStore.markRatingDone();
                Navigator.of(dialogContext).pop();
                CommunityLinks.openLink(CommunityLinks.downloadUrl);
              },
              child: const Text('לדירוג'),
            ),
          ],
        );
      },
    );
  }
}

/// The one-time question: may your name appear on the leaderboard?
///
/// **It is asked before anything is published, not after.** The community layer
/// arrived in an update, and everybody already using the app entered their name
/// for a private diary — publishing it to every other user on the strength of
/// that consent, and offering an opt-out afterwards, is not the same thing as
/// asking. Until this is answered the member document carries no name at all,
/// only counters against a uid.
///
/// Both answers are real answers and neither is styled as the right one. It is
/// dismissible, and dismissing it means "not yet": the question comes back next
/// launch, and until then nothing is published.
abstract final class LeaderboardConsentDialog {
  static Future<void> show(BuildContext context) async {
    final CommunityProvider community = context.read<CommunityProvider>();

    final bool? show = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('הצטרפות לקהילת השדכנים'),
          content: SingleChildScrollView(
            child: Text(
              'הוספנו אזור קהילה: כמה פעולות עשו כל השדכנים יחד, כמה מהם היו '
              'פעילים השבוע, ודירוג של עשרת הפעילים ביותר.\n\n'
              'הפעילות שלך נספרת בסך הכולל בכל מקרה, בלי שם. השאלה היחידה היא '
              'אם השם שרשמת בפרופיל יופיע בדירוג לשדכנים אחרים.\n\n'
              'שום פרט על החברים שלך לא נשלח לשום מקום — לא שם, לא גיל, לא '
              'טלפון ולא הערה. אפשר לשנות את הבחירה בכל רגע בהגדרות.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
          actionsOverflowButtonSpacing: 4,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('בלי השם שלי'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('אפשר להציג את שמי'),
            ),
          ],
        );
      },
    );

    if (show == null) {
      // Dismissed rather than answered. Nothing is recorded, nothing is
      // published, and the question is asked again next launch.
      return;
    }
    await community.answerLeaderboardConsent(hidden: !show);
  }
}

/// Milestones and the note after a large import used to live here, as two
/// dialogs sharing one `_celebrate` helper. **Both are gone.** They are said
/// now by `AchievementWatcher`, as a toast, at the moment they happen rather
/// than on the next launch — see `lib/widgets/app_toast.dart` for why a
/// congratulation is the one thing that must never take the screen.

/// "מה חדש?" — one published note, shown once per device and never again.
abstract final class WhatsNewDialog {
  static Future<void> show(BuildContext context, Announcement note) async {
    CommunityPromptsStore.markAnnouncementSeen(note.id);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final bool dark = theme.brightness == Brightness.dark;

        return AlertDialog(
          title: Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: dark ? theme.colorScheme.primary : AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(note.title)),
            ],
          ),
          content: note.body.isEmpty
              ? null
              : Text(
                  note.body,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        );
      },
    );
  }
}
