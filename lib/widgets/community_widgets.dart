import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';

/// The building blocks of the community surfaces.
///
/// One rule runs through all of them: **a number is not a trophy.** The figures
/// are set in the page's own type at the page's own weight, and exactly one
/// place in the whole feature draws a gold anything — first place on the
/// leaderboard. The feeling being aimed at is "there is a community here doing
/// a great deal for its friends", not "you are winning".

Color communityLead(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.primary
    : AppColors.primaryDark;

/// The one card shape the community surfaces use — the same bordered, softly
/// tinted surface the rest of the home page wears.
class CommunityCard extends StatelessWidget {
  const CommunityCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
  });

  final Widget child;
  final String? title;

  /// A quiet link on the heading row — "לפי חודשים ›" and the like. Never a
  /// second heading and never a button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = communityLead(theme);
    final String? heading = title;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            lead.withValues(alpha: dark ? 0.14 : 0.07),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (heading != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    heading,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// The day / week / month / all-time switch.
class CommunityPeriodTabs extends StatelessWidget {
  const CommunityPeriodTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.periods,
  });

  /// The three windows every personal and community figure offers. "היום" is
  /// left out on purpose: a day is a real unit for a leaderboard, which resets,
  /// and a noisy one for a total that is trying to say how things are going.
  static const List<CommunityPeriod> weekMonthAllTime = <CommunityPeriod>[
    CommunityPeriod.week,
    CommunityPeriod.month,
    CommunityPeriod.allTime,
  ];

  final CommunityPeriod selected;
  final ValueChanged<CommunityPeriod> onChanged;
  final List<CommunityPeriod> periods;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          for (final CommunityPeriod period in periods)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(period),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: period == selected ? lead : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      period.label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: period == selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The headline number of a card.
class CommunityFigure extends StatelessWidget {
  const CommunityFigure({super.key, required this.value, required this.label});

  final int value;
  final String label;

  /// Four-figure counts are normal on the community side, so they are grouped —
  /// "1,842" is read at a glance and "1842" is counted.
  static String format(int value) {
    final String digits = value.abs().toString();
    final StringBuffer out = StringBuffer(value < 0 ? '-' : '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              format(value),
              maxLines: 1,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1,
                color: communityLead(theme),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Flexible, not a plain Text: this row is put in a narrowed column
        // beside the pace chip on the activity screen, and it is read at 1.5x
        // system text on the home block. A label that cannot give way turns
        // either of those into an overflow stripe across the card.
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the small figures under the headline.
class CommunitySmallFigure extends StatelessWidget {
  const CommunitySmallFigure({
    super.key,
    required this.value,
    required this.label,
  });

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            CommunityFigure.format(value),
            maxLines: 1,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

/// One line of "what happened", as a label with its number at the end.
///
/// **A row, not a tile.** Six of these as cards would be six boxes competing
/// with each other and with the headline above them; as a short list they read
/// as one paragraph of figures, which is what they are.
class CommunityStatLine extends StatelessWidget {
  const CommunityStatLine({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final int value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            CommunityFigure.format(value),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// "איך הפעילות נספרת?" — the scoring method, said once and in full.
///
/// A sheet rather than a permanent block of small print. The rule matters the
/// first time somebody wonders about it and never again, and a table of weights
/// sitting under every figure turns a workspace into a rulebook.
class ActivityScoringSheet extends StatelessWidget {
  const ActivityScoringSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => const ActivityScoringSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              ActivityPoints.howItIsCountedTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'שיטת הניקוד:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final String line in ActivityPoints.scoringLines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: communityLead(theme),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            for (final String note in ActivityPoints.scoringNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The one-line way into [ActivityScoringSheet].
class ActivityScoringLink extends StatelessWidget {
  const ActivityScoringLink({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => ActivityScoringSheet.show(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.help_outline_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            // Flexible rather than intrinsic: at 1.5x system text the line is
            // wider than a 320px phone's card, and a link that overflows is
            // the one thing on this block nobody would report.
            Flexible(
              child: Text(
                ActivityPoints.howItIsCountedTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The invitation a matchmaker who has not connected an account sees where the
/// community's figures would be.
///
/// **It says what is missing, not that something is locked.** Their own numbers
/// are right beside it and keep working; the community is simply a thing they
/// are not part of yet, and one sentence and one button is the whole of what
/// the app has to say about it. There is no second nudge, no badge and no
/// counter of what they are missing out on.
class CommunitySignInCard extends StatelessWidget {
  const CommunitySignInCard({
    super.key,
    required this.title,
    required this.body,
    this.compact = false,
  });

  /// The form for the home block, where this sits inside a card that is
  /// already carrying the matchmaker's own figures.
  const CommunitySignInCard.joinTheCommunity({Key? key})
    : this(
        key: key,
        title: 'הצטרפו לקהילת השדכנים',
        body:
            'התחברו כדי לראות את פעילות הקהילה, להשתתף בדירוג ולסנכרן את המאגר '
            'בין מכשירים.',
        compact: true,
      );

  /// The form for the activity screen, standing in for the two community
  /// sections a signed-out reader cannot see.
  const CommunitySignInCard.communityIsForMembers({Key? key})
    : this(
        key: key,
        title: 'הקהילה זמינה למשתמשים מחוברים',
        body:
            'התחברו כדי לראות את פעילות קהילת השדכנים, להשתתף בדירוג ולשמור את '
            'הפעילות שלכם בין מכשירים.',
      );

  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style:
              (compact
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.titleSmall)
                  ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: () => context.push('/sign-in'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            ),
            child: const Text('התחברות'),
          ),
        ),
      ],
    );
  }
}

/// One line of the leaderboard.
class CommunityRankRow extends StatelessWidget {
  const CommunityRankRow({
    super.key,
    required this.place,
    required this.entry,
    this.highlighted = false,
  });

  final int place;
  final CommunityRankEntry entry;

  /// The reader's own line, shown separately below the ten.
  final bool highlighted;

  /// Gold for first, and nothing louder than a tinted disc for second and
  /// third. Three medals in a row turns a community into a podium.
  static const Color _gold = Color(0xFFD4A34B);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);

    Widget mark() {
      if (place == 1) {
        return const Icon(Icons.emoji_events_rounded, size: 22, color: _gold);
      }
      final bool podium = place == 2 || place == 3;
      return Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: podium
              ? lead.withValues(alpha: 0.16)
              : theme.colorScheme.surface,
          border: podium
              ? null
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          '$place',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: podium ? lead : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          mark(),
          const SizedBox(width: 10),
          _RankAvatar(url: entry.photoUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            CommunityFigure.format(entry.points),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: lead,
            ),
          ),
        ],
      ),
    );
  }
}

/// One matchmaker's face on the leaderboard.
///
/// **A picture is what makes a board of names a room of people**, which is the
/// whole reason the community area exists — the numbers were never the point.
///
/// The fallback is the app's own "somebody with no photo": the same neutral
/// circle a friend without a picture and without a stated gender gets. The two
/// gendered default illustrations are not used here on purpose — the app would
/// have to publish each matchmaker's gender to pick between them, and adding a
/// field to a collection every installed copy can read, in order to choose a
/// drawing, is not a trade worth making.
class _RankAvatar extends StatelessWidget {
  const _RankAvatar({required this.url});

  static const double _radius = 15;

  final String url;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget fallback = CircleAvatar(
      radius: _radius,
      backgroundColor: theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceContainerHighest
          : AppColors.primaryLight,
      child: Icon(
        Icons.person_outline,
        size: _radius * 1.15,
        color: AppColors.primary,
      ),
    );

    if (url.isEmpty) {
      return fallback;
    }
    return ClipOval(
      child: Image.network(
        url,
        width: _radius * 2,
        height: _radius * 2,
        fit: BoxFit.cover,
        // A face that will not load must not leave a broken box in a list of
        // people. It falls back to exactly what somebody with no photo gets.
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// **"להסתיר אותי מהדירוג" was removed from the app, and this note is what is
/// left of it.**
///
/// The mechanism underneath is intact and still matters: `CommunityProfileStore
/// .isHidden` is true until `LeaderboardConsentDialog` has been answered, so a
/// name is never published before somebody agrees to it, and
/// `CommunityService.publish` still writes an empty name for a hidden member.
/// What is gone is the *toggle* — the way to change that answer afterwards.
///
/// The consequence is worth writing down, because it is a real one and it was
/// a product decision rather than an oversight: somebody who said yes can no
/// longer say no. The only remaining way off the board is
/// [DeleteCommunityDataTile] on "פרטיות והמאגר שלי", which deletes the whole
/// member document. Restoring the toggle means putting this widget back in the
/// activity screen and the privacy page; nothing in the service layer has to
/// change.

/// "שמור על הפרטיות שלי" — the one switch that stops anything being shared.
///
/// **It is a switch and not a screen of choices.** A matchmaker who does not
/// want their work counted alongside everybody else's is not asking to
/// configure which halves of it are counted; they are asking for one thing, and
/// splitting it into "hide my name" and "hide my numbers" and "hide me from the
/// board" would be three ways to get it half right. On means nothing about them
/// leaves the device.
///
/// **Everything personal keeps working, and the copy says so.** The figures,
/// the chart, the milestones and the weekly best are all computed here from the
/// records on this phone; so is the ability to read what the community did.
/// What is given up is being *in* the totals and on the board. Said plainly,
/// because a privacy switch whose consequences are vague gets left alone by the
/// people who most wanted it.
class PrivateModeTile extends StatelessWidget {
  const PrivateModeTile({super.key});

  static const String title = 'שמור על הפרטיות שלי';

  static const String explanation =
      'הפעילות שלך לא תישלח לקהילה: לא ייספרו הנתונים שלך בסך הפעילות של '
      'הקהילה והשם שלך לא יופיע בדירוג. כל המספרים, הגרפים ואבני הדרך שלך '
      'ימשיכו לעבוד כרגיל במכשיר, ותוכל להמשיך לראות את פעילות הקהילה.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();

    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: community.isPrivate,
      onChanged: (bool value) => _set(context, value),
      secondary: Icon(
        community.isPrivate
            ? Icons.shield_moon_outlined
            : Icons.shield_outlined,
        size: 22,
        color: communityLead(theme),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        explanation,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      isThreeLine: true,
    );
  }

  Future<void> _set(BuildContext context, bool private) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Turning it on also deletes whatever is already on the server; see
    // `CommunityProvider.setPrivate`.
    await context.read<CommunityProvider>().setPrivate(private);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            private
                ? 'מעכשיו הפעילות שלך נשארת אצלך בלבד.'
                : 'הפעילות שלך נספרת שוב בנתוני הקהילה.',
          ),
        ),
      );
  }
}

/// "מחיקת הנתונים שלי מהקהילה" — the erasure path.
///
/// Uninstalling the app does not remove the member document; nothing on the
/// device can reach the server once it is gone. So the deletion has to be a
/// button *inside* the app, and it has to be somewhere a person looking for it
/// would look — which is the privacy page, not buried under the leaderboard.
///
/// It hides the matchmaker as well as deleting the row, because the next
/// publish recreates the row and must not recreate it with a name in it.
class DeleteCommunityDataTile extends StatelessWidget {
  const DeleteCommunityDataTile({super.key});

  static const String explanation =
      'מוחק מהשרת את המונים ואת השם שלך. הפעילות שלך באפליקציה נשמרת במכשיר '
      'כרגיל ולא נמחקת. אחרי המחיקה לא תופיע בדירוג ולא תיספר בנתוני הקהילה.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      title: Text(
        'מחיקת הנתונים שלי מהקהילה',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.error,
        ),
      ),
      subtitle: Text(explanation),
      isThreeLine: true,
      onTap: () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final CommunityProvider community = context.read<CommunityProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את נתוני הקהילה?',
      message: explanation,
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }

    final bool deleted = await community.deleteMyCommunityData();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? 'נתוני הקהילה שלך נמחקו.'
                : 'לא הצלחנו למחוק כרגע. כדאי לנסות שוב כשיש חיבור לאינטרנט.',
          ),
        ),
      );
  }
}
