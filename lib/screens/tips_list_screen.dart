import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';

/// "טיפים לשדכנים" — everything other matchmakers have said, on one page.
///
/// **Rebuilt so it reads like a page of quotations rather than a backlog.** It
/// was a column of identical outlined cards, each opening with the same bulb
/// emoji: forty rows that all look the same is a list to get through, and
/// nobody gets through it. Four things changed and they all serve the same
/// end —
///
/// * **No bulbs anywhere.** The mark used to be an emoji appended to every
///   sentence, which on a device without a colour emoji font drew a blank box
///   and everywhere else read as a typo inside somebody's own words. What
///   opens a tip now is a large typographic quotation mark, drawn in the
///   card's own ink at low opacity — furniture, not punctuation somebody typed.
/// * **The cards take turns wearing three warm tints.** Nothing about a tip
///   decides its colour; the rotation exists so the eye has something to travel
///   down. A page of one tint is a wall.
/// * **Room to breathe.** Bigger type, a real line height, and a full gap
///   between cards, because these are sentences to read and not rows to scan.
/// * **A welcome at the top and an invitation at the foot.** The page opens by
///   saying whose words these are, and closes by asking for yours — which is
///   the moment somebody is most likely to think of one.
class TipsListScreen extends StatelessWidget {
  const TipsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Gender? gender = context.watch<UserProfileProvider>().gender;
    final List<CommunityTip> community = context.watch<TipsProvider>().approved;

    final List<({String text, String? author})> tips =
        <({String text, String? author})>[
          for (final String template in MatchmakerTips.tips)
            (text: template.forGender(gender), author: null),
          for (final CommunityTip tip in community)
            (
              text: tip.text,
              author: tip.authorName.isEmpty ? null : tip.authorName,
            ),
        ];

    return Scaffold(
      appBar: AppBar(title: const Text('טיפים לשדכנים'), centerTitle: true),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          // The header, the tips, and the invitation at the end.
          itemCount: tips.length + 2,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return const _TipsWelcome();
            }
            if (index == tips.length + 1) {
              return _AddTipInvite(onTap: () => context.push('/profile/tips'));
            }

            final ({String text, String? author}) tip = tips[index - 1];
            return _TipCard(
              text: tip.text,
              author: tip.author,
              tone: _TipTone.values[(index - 1) % _TipTone.values.length],
            );
          },
        ),
      ),
    );
  }
}

/// The three warm washes the cards take turns in. Nothing about a tip picks
/// its tone — the rotation is there to give a long page a rhythm.
enum _TipTone {
  sand,
  sky,
  olive;

  Color wash(bool dark) {
    if (dark) {
      return switch (this) {
        _TipTone.sand => const Color(0xFF2A2520),
        _TipTone.sky => const Color(0xFF1F272C),
        _TipTone.olive => const Color(0xFF222720),
      };
    }
    return switch (this) {
      _TipTone.sand => const Color(0xFFFBF2E6),
      _TipTone.sky => const Color(0xFFF0F5F7),
      _TipTone.olive => const Color(0xFFF2F4EA),
    };
  }

  Color ink(bool dark) {
    if (dark) {
      return switch (this) {
        _TipTone.sand => AppColors.secondaryDarkDm,
        _TipTone.sky => AppColors.primaryDarkDm,
        _TipTone.olive => const Color(0xFFA9BB8E),
      };
    }
    return switch (this) {
      _TipTone.sand => AppColors.secondaryInk,
      _TipTone.sky => AppColors.primaryInk,
      _TipTone.olive => const Color(0xFF5C6B45),
    };
  }
}

/// The opening: whose words these are, in one warm band.
class _TipsWelcome extends StatelessWidget {
  const _TipsWelcome();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondaryInk;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ink.withValues(alpha: dark ? 0.32 : 0.20)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[_TipTone.sand.wash(dark), theme.colorScheme.surface],
        ),
      ),
      child: Stack(
        children: <Widget>[
          // The warm corner: nothing is written on it, and it is what makes the
          // band read as a piece of paper rather than as an outlined box.
          PositionedDirectional(
            top: -34,
            start: -26,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ink.withValues(alpha: dark ? 0.10 : 0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'מה שדכנים למדו בדרך',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'אוסף קטן של דברים ששדכנים אחרים גילו — קצת ניסיון, קצת לב. '
                'אפשר לקרוא אחד ולחזור מחר לעוד.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One tip, as a quotation.
class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.text,
    required this.author,
    required this.tone,
  });

  final String text;
  final String? author;
  final _TipTone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = tone.ink(dark);
    final String? by = author?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: tone.wash(dark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ink.withValues(alpha: dark ? 0.26 : 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A quotation mark rather than an icon: these are somebody's words,
          // and the mark that says so is a letterform, not a symbol.
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '”',
              style: theme.textTheme.displaySmall?.copyWith(
                height: 0.9,
                fontWeight: FontWeight.w900,
                color: ink.withValues(alpha: 0.42),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (by != null && by.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ink.withValues(alpha: dark ? 0.28 : 0.16),
                        ),
                        child: Text(
                          by.characters.first,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          by,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The foot of the page: the one moment somebody is most likely to think of a
/// tip of their own is straight after reading everybody else's.
class _AddTipInvite extends StatelessWidget {
  const _AddTipInvite({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: <Widget>[
          Text(
            'יש לך טיפ משלך?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'כל טיפ שנשלח נקרא, ואם הוא מתאים הוא מצטרף לרשימה הזאת.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onTap,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('לשליחת טיפ משלי'),
          ),
        ],
      ),
    );
  }
}
