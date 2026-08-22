import 'package:flutter/material.dart';
import 'package:shadchan/services/community_engagements_service.dart';

/// What the community hears when a proposal becomes a wedding, and the one
/// decision the matchmaker gets to make about it.
///
/// **Nothing about the couple is ever published.** There used to be a sheet
/// here offering to add their first names and a photograph, gated behind a box
/// the matchmaker ticked to say the couple had agreed. It was removed on
/// purpose: two people who are not users of this app, who never agreed to
/// anything and would have no way of knowing, do not become public because a
/// third person ticked a box about them. The good news travels; the couple does
/// not.
///
/// What is left is one announcement that names nobody, and one question, about
/// the matchmaker themselves.
abstract final class EngagementFlow {
  /// Records the engagement and then offers to put names to it.
  ///
  /// Silent on every failure. A matchmaker who has just marked a wedding is
  /// having the best moment this app has to offer, and a network error is not
  /// worth interrupting it — the couple is already recorded locally, and the
  /// community note is the part that can afford to be lost.
  static Future<void> celebrate(
    BuildContext context, {
    required String matchId,
    required String matchmakerName,
    required bool shareName,
    required bool private,
  }) async {
    // "שמור על הפרטיות שלי" covers this too. A wedding is something this
    // matchmaker did, and somebody who asked for none of what they do to be
    // shared has not made an exception for the best of it.
    if (private) {
      return;
    }
    final String? engagementId = await CommunityEngagementsService.record(
      // Carried so other matchmakers can send a bracha back into this
      // proposal's own journal. A uuid from this phone, meaningless anywhere
      // else — see `CommunityEngagement.matchId`.
      matchId: matchId,
    );
    if (engagementId == null || !context.mounted) {
      return;
    }
    // Most matchmakers never connect an account, and for them the anonymous
    // note is the whole feature — neither question is offered rather than
    // offered and then refused by the rules.
    if (!await CommunityEngagementsService.canBeNamed() || !context.mounted) {
      return;
    }
    if (!shareName || matchmakerName.trim().isEmpty) {
      // Somebody who keeps their name off the leaderboard is not asked to put
      // it on an announcement. The note has gone out and it says all it will
      // ever say.
      return;
    }

    // The one question this flow asks, and it is about the matchmaker, never
    // about the couple.
    final bool named = await MatchmakerNameDialog.ask(
      context,
      matchmakerName: matchmakerName,
    );
    if (!named || !context.mounted) {
      return;
    }
    final bool ok = await CommunityEngagementsService.attachMatchmakerName(
      engagementId: engagementId,
      matchmakerName: matchmakerName,
    );
    if (!ok || !context.mounted) {
      return;
    }

    // The way back. A name given in the first happy minute after a wedding is
    // exactly the kind that gets regretted in the second, and there is no
    // screen listing past announcements to take it off later.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('השם שלך צורף להודעה לקהילה.'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () async {
              final bool removed =
                  await CommunityEngagementsService.detachMatchmakerName(
                    engagementId,
                  );
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      removed
                          ? 'השם הוסר. ההודעה נשארה בלי שם.'
                          : 'לא הצלחנו להסיר כרגע. כדאי לנסות שוב כשיש '
                                'חיבור לאינטרנט.',
                    ),
                  ),
                );
            },
          ),
        ),
      );
  }
}

/// "אפשר לציין שהשידוך הזה שלך?" — asked once, per couple, of the matchmaker
/// about themselves.
///
/// **The announcement goes out nameless and stays nameless unless this is
/// answered yes.** It used to carry the matchmaker's name whenever they were
/// visible on the leaderboard, which quietly turned a standing preference about
/// a list of names into a per-event publication nobody had agreed to. Appearing
/// on a leaderboard and having it announced that you closed a particular match
/// on a particular day are different things, and only the second one is asked
/// about here.
///
/// Dismissing the dialog is a "no": the default has to be the quieter answer,
/// or the question is decoration.
abstract final class MatchmakerNameDialog {
  static Future<bool> ask(
    BuildContext context, {
    required String matchmakerName,
  }) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('מזל טוב!'),
          content: Text(
            'ההודעה לקהילה יוצאת עכשיו בלי שום פרט — רק שזוג התארס.\n\n'
            'אפשר לציין בה שהשידוך הזה שלך? יופיע השם '
            '"${matchmakerName.trim()}", ושום דבר על בני הזוג.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('להשאיר בלי שם'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('כן, לציין'),
            ),
          ],
        );
      },
    );
    return answer ?? false;
  }
}

/// The congratulation, shown once per couple and then never again.
///
/// Small, warm and gone in a few seconds — the same shape as the achievement
/// note, because it is the same kind of moment. There is no button and there is
/// nowhere to tap through to: this is news, not a screen.
/// `MazelTovDialog` used to live here: somebody else's engagement, announced by
/// taking over the screen on the next launch. It is `HomeEngagementCard` now —
/// a card on the home page for one launch, read when the eye reaches it. The
/// news was always worth carrying; the interruption never was.
