import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_achievements.dart';
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

/// A milestone, acknowledged and got out of the way.
///
/// A small dialog rather than a full-screen celebration, and a short cheer
/// rather than a paragraph. This fires at ten friends and at fifty and at a
/// hundred — anything grander would be exhausting by the third time, and the
/// thing being celebrated is somebody else's work, not the app's.
///
/// **There is no button to press.** Being congratulated and then made to
/// acknowledge the congratulation is a chore; this closes by itself after a
/// few seconds, or on a tap anywhere.
abstract final class AchievementDialog {
  static const Duration _visibleFor = Duration(seconds: 4);

  static Future<void> show(
    BuildContext context,
    Achievement achievement,
  ) async {
    CommunityProfileStore.markSeen(achievement.id);
    await _celebrate(context, achievement.title, achievement.body);
  }

  /// The shape both congratulations wear — this one and the note after a large
  /// import. Shared so the two can never be told apart by their chrome, only by
  /// their words, and so neither grows a button the other lacks.
  static Future<void> _celebrate(
    BuildContext context,
    String title,
    String body,
  ) async {
    Timer? autoClose;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final bool dark = theme.brightness == Brightness.dark;
        final Color tone = dark
            ? theme.colorScheme.primary
            : AppColors.primaryDark;

        void close() {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        }

        // Guarded against a rebuild of the route starting a second timer.
        autoClose ??= Timer(_visibleFor, close);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          child: AlertDialog(
            title: Row(
              children: <Widget>[
                Icon(Icons.celebration_rounded, size: 22, color: tone),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
              ],
            ),
            content: Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          ),
        );
      },
    );

    autoClose?.cancel();
  }
}

/// The note after a large import.
///
/// **It exists to stop two celebrations landing on the same second.** An import
/// of three hundred cards crosses the friend milestone, the action milestone
/// and very possibly the weekly record all at once, and a matchmaker who has
/// just done a good afternoon's work should be told that — once, in one
/// sentence about the thing they actually did — rather than handed a queue of
/// dialogs about round numbers. So this is checked *before* the achievements in
/// [CommunityPromptGate] and returns true when it spoke, and the milestones it
/// pre-empted stay unseen for a quieter day.
abstract final class BulkImportNoteDialog {
  /// Shows the pending note if there is one, and reports whether it did.
  static Future<bool> maybeShow(BuildContext context) async {
    final int added = CommunityProfileStore.pendingBulkImport;
    if (added < CommunityProfileStore.bulkImportNoticeFrom) {
      return false;
    }
    // Cleared before the await, not after: a second caller reaching this while
    // the dialog is on screen must find nothing rather than queue another one.
    CommunityProfileStore.clearPendingBulkImport();
    await AchievementDialog._celebrate(
      context,
      'המאגר שלך גדל!',
      CommunityAchievements.bulkImportMessage(added),
    );
    return true;
  }
}

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
