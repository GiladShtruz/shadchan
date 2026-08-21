import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/community_milestones.dart';

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

/// Milestones and the note after a large import used to live here, as two
/// dialogs sharing one `_celebrate` helper. **Both are gone.** They are said
/// now by `AchievementWatcher`, as a toast, at the moment they happen rather
/// than on the next launch — see `lib/widgets/app_toast.dart` for why a
/// congratulation is the one thing that must never take the screen.

/// "הקהילה הגיעה ל־1,000 רעיונות" — the community's own good news, once.
///
/// **A small festive screen, and very rarely.** The rungs are far apart, a
/// device says nothing about anything it was already past when it first looked,
/// and this rides the same one-prompt-per-launch gate as everything else the
/// app raises by itself — see [CommunityMilestones] for all three. Somebody who
/// uses the app every day should meet this a handful of times a year and be
/// pleased each time.
///
/// **Nobody is congratulated.** The community reached it; the reader is part of
/// the community. There is no "thanks to you", no figure of their own beside
/// it, and one button that says nothing more than "ממשיכים".
abstract final class CommunityMilestoneDialog {
  static Future<void> show(
    BuildContext context,
    CommunityMilestone milestone,
  ) async {
    CommunityProfileStore.markCommunityMilestoneSeen(milestone.id);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final bool dark = theme.brightness == Brightness.dark;
        final Color lead = dark
            ? theme.colorScheme.primary
            : AppColors.primaryDark;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  lead.withValues(alpha: dark ? 0.24 : 0.14),
                  theme.colorScheme.surface,
                ],
              ),
            ),
            child: Stack(
              children: <Widget>[
                // The warm corner the tip card and the community cards wear,
                // so the moment looks like it belongs to this app rather than
                // to a confetti library.
                PositionedDirectional(
                  top: -40,
                  start: -34,
                  child: Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondary.withValues(
                        alpha: dark ? 0.12 : 0.10,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        milestone.emoji,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 46),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        milestone.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        milestone.body,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const Text('ממשיכים'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
