import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/mazel_tov_sheet.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_engagements_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/mazel_tov_service.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "מזל טוב! זוג חדש התחתן" — on the home screen, for one launch, and then
/// gone.
///
/// **It was a dialog.** Somebody else's good news arrived by taking over the
/// screen of a matchmaker who had opened the app to do their own work, and it
/// had to be dismissed before they could. The news is worth carrying; the
/// interruption never was. As a card it is read when the eye reaches it and
/// scrolled past when it does not.
///
/// It marks itself seen as soon as it is drawn, which is what makes it
/// temporary: the same couple is never announced twice, and there is no archive
/// of past engagements anywhere in the app.
///
/// **"שלחו מזל טוב" is the one thing on it that acts.** One tap opens four
/// ready-made brachot and a field; the bracha lands in the *other* matchmaker's
/// journal for that couple, beside every other line about them. That is the
/// whole feature — no thread, no reply, no inbox screen — and it is why this
/// card is the only place in the app where one matchmaker can say something to
/// another at all.
///
/// Signed-out matchmakers do not see it, for the same reason they do not see
/// the community's figures — they are not part of it yet.
class HomeEngagementCard extends StatefulWidget {
  const HomeEngagementCard({super.key});

  @override
  State<HomeEngagementCard> createState() => _HomeEngagementCardState();
}

class _HomeEngagementCardState extends State<HomeEngagementCard> {
  CommunityEngagement? _engagement;
  bool _asked = false;
  bool _sending = false;
  bool _sent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked || !context.watch<AccountProvider>().isSignedIn) {
      return;
    }
    _asked = true;
    _load();
  }

  Future<void> _load() async {
    final CommunityEngagement? engagement =
        await CommunityEngagementsService.latestUnseen(
          seenId: CommunityPromptsStore.seenEngagementId,
        );
    if (engagement == null || !mounted) {
      return;
    }
    // Marked as it is drawn, not when it is dismissed. There is nothing to
    // dismiss, and a card that reappears every launch until somebody acts on it
    // is the interruption this replaced, in a different shape.
    CommunityPromptsStore.markEngagementSeen(engagement.id);
    setState(() {
      _engagement = engagement;
      _sent = CommunityPromptsStore.hasCongratulated(engagement.id);
    });
  }

  Future<void> _congratulate(CommunityEngagement engagement) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String myName = context.read<UserProfileProvider>().name ?? '';
    final String? text = await MazelTovSheet.show(context);
    if (text == null || !mounted) {
      return;
    }

    setState(() => _sending = true);
    final bool ok = await MazelTovService.send(
      toUid: engagement.authorUid,
      matchId: engagement.matchId,
      text: text,
      // The same rule the leaderboard follows: a matchmaker who has not agreed
      // to publish their name sends the bracha without one, and the recipient
      // reads it as coming from "שדכן מהקהילה".
      fromName: CommunityProfileStore.isHidden ? '' : myName,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      CommunityPromptsStore.markCongratulated(engagement.id);
    }
    setState(() {
      _sending = false;
      _sent = ok;
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'הברכה נשלחה. תודה!'
                : 'לא הצלחנו לשלוח כרגע. כדאי לנסות שוב כשיש חיבור לאינטרנט.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final CommunityEngagement? engagement = _engagement;
    if (engagement == null) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color tone = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    // Who it happened to. The matchmaker's name is on the record only when they
    // publish it at all; without one the line still says everything that
    // matters, and the button under it still works — a bracha is addressed by
    // account, not by name.
    final String headline = engagement.matchmakerName.isEmpty
        ? 'מזל טוב! לאחד השדכנים בקהילה התחתן זוג 🎉'
        : 'מזל טוב! לשדכן ${engagement.matchmakerName} התחתן זוג 🎉';

    // The anonymous line is the default and by far the common one. It names
    // nobody on purpose: the good news travels, the couple does not.
    final String body = engagement.isNamed
        ? '${engagement.firstNames} התחתנו!'
        : 'עוד בית נבנה בעם ישראל. שנשמע רק בשורות טובות!';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            tone.withValues(alpha: dark ? 0.14 : 0.07),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            headline,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          if (engagement.photoUrl.isNotEmpty) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                engagement.photoUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                // A photo that will not load must not leave a broken box in the
                // middle of somebody's good news.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          if (engagement.isNamed &&
              engagement.matchmakerName.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'שודך על ידי ${engagement.matchmakerName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (engagement.canBeCongratulated) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _sent
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.check_circle_outline, size: 16, color: tone),
                        const SizedBox(width: 6),
                        Text(
                          'שלחת מזל טוב 💛',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tone,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: _sending
                          ? null
                          : () => _congratulate(engagement),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.favorite_rounded, size: 18),
                      label: const Text('שלחו מזל טוב'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
