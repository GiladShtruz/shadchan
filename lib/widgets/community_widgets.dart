import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';

/// The building blocks of the community surfaces.
///
/// One rule runs through all of them: **a number is not a trophy.** The figures
/// are set in the page's own type at the page's own weight, the meter is the
/// brand blue rather than a colour that means "score", and exactly one place in
/// the whole feature draws a gold anything — first place on the leaderboard.
/// The feeling being aimed at is "there is a community here doing a great deal
/// for its friends", not "you are winning".

Color communityLead(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.primary
    : AppColors.primaryDark;

/// The one card shape the community surfaces use — the same bordered, softly
/// tinted surface the rest of the home page wears.
class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

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
            Text(
              heading,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// The week / month / all-time switch.
class CommunityPeriodTabs extends StatelessWidget {
  const CommunityPeriodTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.periods,
  });

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
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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

/// The goal meter. Past the target it keeps its full bar and changes tone
/// rather than stopping — the week does not end at 100%.
class CommunityMeter extends StatelessWidget {
  const CommunityMeter({super.key, required this.progress, this.over = false});

  final double progress;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = over ? AppColors.statusDating : communityLead(theme);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 9,
        backgroundColor: theme.colorScheme.outlineVariant,
        valueColor: AlwaysStoppedAnimation<Color>(tone),
      ),
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
          const SizedBox(width: 12),
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
            CommunityFigure.format(entry.actions),
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

/// "להסתיר אותי מהדירוג", with the sentence that explains what it means.
///
/// It is drawn in three places — the home block, this screen and the settings —
/// on purpose. A privacy control that only exists in a settings screen is a
/// privacy control most people never find, and this one has to be found *at the
/// moment somebody notices their name on a public list*, which is not while
/// they are looking at the settings.
///
/// **It is always shown, at every community size.** An earlier plan was to
/// reveal it only past two hundred active matchmakers, on the theory that
/// hiding in a small group is conspicuous. That plan belonged to a design where
/// appearing was the default and this toggle was the only way out. It is not
/// the design that shipped: `LeaderboardConsentDialog` asks once, before a name
/// has ever been published, and until it is answered nothing identifying is
/// written to the server at all. So this tile is not an escape hatch — it is
/// where an answered question is changed later, and there is no community size
/// at which somebody should be unable to change their answer.
class HideFromLeaderboardTile extends StatelessWidget {
  const HideFromLeaderboardTile({super.key, this.dense = false});

  /// The compact form used inside a card that is already busy.
  final bool dense;

  static const String explanation =
      'כשמסתירים, השם שלך לא מופיע לאף אחד בדירוג — וגם המיקום האישי שלך לא '
      'יוצג לך. הפעילות שלך ממשיכה להיספר בנתוני הקהילה, בלי שם.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: dense,
          value: community.isHidden,
          onChanged: (bool value) => community.setHidden(value),
          title: Text(
            'להסתיר אותי מהדירוג',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: dense ? null : Text(explanation),
        ),
        if (dense)
          Text(
            explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
      ],
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
