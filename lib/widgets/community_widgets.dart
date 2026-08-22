import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
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
        const SizedBox(height: 3),
        // The label carries as much weight as the number does. On the home
        // screen these two labels — "הפעילות שלך" and "פעילות הקהילה" — are the
        // only thing that says *what* the block is about, and in footnote grey
        // they were quieter than the "איך הפעילות נמדדת?" link underneath them.
        Text(
          label,
          maxLines: 2,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
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

/// "להופיע בקהילה בשם שלי" — the anonymity switch, back on the privacy page.
///
/// **A matchmaker is in the community under their own name by default.** There
/// used to be a launch dialog asking permission, and until it was answered the
/// name was withheld; the question arrived before anybody had seen what the
/// community even was, and the board it fed stayed half empty. So the default
/// is the ordinary one — you appear — and this is the switch that takes you
/// back out.
///
/// **It hides the name, not the work.** Off, the counters still travel and
/// still add to what the community did together; only the name and picture
/// stop being attached to them. Somebody who wants the counters to stop too is
/// asking for the switch below this one, [PrivateModeTile], and the copy on
/// both says which is which.
class LeaderboardNameTile extends StatelessWidget {
  const LeaderboardNameTile({super.key});

  static const String title = 'להופיע בקהילה בשם שלי';

  static const String explanation =
      'השם והתמונה שרשמת בפרופיל יופיעו לשדכנים אחרים בדירוג הקהילה. '
      'אם תכבה, הפעילות שלך עדיין תיספר בסך הכולל של הקהילה — אבל בלי שם, '
      'ולא תופיע בדירוג.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    // Nothing at all is published in private mode, so the name question is
    // already answered and the switch says so rather than pretending to be
    // live.
    final bool locked = community.isPrivate;
    final bool visible = !community.isHidden;

    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: visible,
      onChanged: locked ? null : (bool value) => _set(context, value),
      secondary: Icon(
        visible ? Icons.badge_outlined : Icons.visibility_off_outlined,
        size: 22,
        color: communityLead(theme),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        locked
            ? 'כרגע "שמור על הפרטיות שלי" פעיל, ולכן שום דבר לא נשלח לקהילה.'
            : explanation,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      isThreeLine: true,
    );
  }

  Future<void> _set(BuildContext context, bool visible) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await context.read<CommunityProvider>().setHidden(!visible);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            visible
                ? 'השם שלך יופיע בדירוג הקהילה.'
                : 'מעכשיו הפעילות שלך נספרת בלי שם.',
          ),
        ),
      );
  }
}

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

/// "מחיקת הגיבוי בענן" — erases the copy of the database on the server.
///
/// **Sits beside [DeleteCommunityDataTile] because the two are not the same
/// erasure, and the difference is the whole reason this exists.** That one
/// removes a row of counters and a name the matchmaker chose to publish about
/// themselves. This one removes the friends: their names, their telephone
/// numbers, the notes written about their shidduchim, and their faces — people
/// who are not users of this app, never agreed to anything, and have no way of
/// knowing a copy is held anywhere.
///
/// Until now the screen said that a cloud backup could be deleted *by asking*,
/// which meant an email to the developer and a manual pass through the Firebase
/// console. The least sensitive data in the system had a button and the most
/// sensitive one did not.
///
/// Shown only to an account that could have a backup at all: a matchmaker who
/// never connected an account has nothing on the server, and offering to delete
/// it would imply there was something up there.
class DeleteCloudBackupTile extends StatelessWidget {
  const DeleteCloudBackupTile({super.key});

  static const String explanation =
      'מוחק מהשרת את כל מה שגובה בענן — החברים, ההערות, ההצעות והתמונות. '
      'המאגר בטלפון שלך נשאר בדיוק כמו שהוא ואפשר להמשיך לעבוד רגיל. '
      'אם תישאר מחובר, הגיבוי הבא יעלה את המאגר לענן מחדש.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Nothing to delete without a durable account — see `CloudSyncService`,
    // which refuses to write a backup under an anonymous uid in the first
    // place.
    if (!context.watch<AccountProvider>().isSignedIn) {
      return const SizedBox.shrink();
    }
    final bool busy = context.watch<SyncProvider>().isDeleting;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !busy,
      leading: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Icon(Icons.cloud_off_outlined, color: theme.colorScheme.error),
      title: Text(
        'מחיקת הגיבוי בענן',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.error,
        ),
      ),
      subtitle: Text(explanation),
      isThreeLine: true,
      onTap: busy ? null : () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final SyncProvider sync = context.read<SyncProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את הגיבוי בענן?',
      message: explanation,
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }

    final bool deleted = await sync.deleteBackup();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                // Said plainly, and only when it is true. A deletion reported
                // wrongly is worse than one that did not happen.
                ? 'הגיבוי בענן נמחק. המאגר בטלפון שלך לא השתנה.'
                : 'לא הצלחנו למחוק את הגיבוי כרגע. כדאי לנסות שוב כשיש '
                      'חיבור טוב לאינטרנט.',
          ),
        ),
      );
  }
}
