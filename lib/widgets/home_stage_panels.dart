import 'package:flutter/material.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/widgets/home_section.dart';

Color _lead(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.primary
    : AppColors.primaryDark;

/// The opening card a brand-new matchmaker lands on.
///
/// Shown *inside* the real home screen rather than as a wizard in front of it:
/// nothing here blocks the rest of the app, and adding friends is an invitation
/// rather than a toll gate. It disappears on its own once the database starts.
class HomeWelcomeCard extends StatelessWidget {
  const HomeWelcomeCard({super.key, required this.onAddPeople});

  final VoidCallback onAddPeople;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // The page's one card: plain paper, a soft shadow, the brand blue along
    // the foot. It was a blue-washed panel — the first thing a new matchmaker
    // saw, and the one block on the page drawn unlike the rest of it.
    return HomePaperCard(
      stripe: dark ? AppColors.primaryDarkDm : AppColors.primary,
      radius: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'זה היומן האישי שלך לשידוכים',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'כאן נשמרים החברים {שאתה חושב|שאת חושבת} עליהם, הרעיונות שנפתחו '
                    'ומה קרה איתם. מתחילים בהוספת כמה חברים — כל אחד שנוסף '
                    'פותח כיוון.'
                .forGender(context.userGender),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAddPeople,
              style: FilledButton.styleFrom(
                backgroundColor: _lead(theme),
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.person_add_alt, size: 19),
              label: const Text('הוספת החברים הראשונים'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The staged target: ten, then twenty-five, then fifty, then a hundred.
class HomeMilestoneCard extends StatelessWidget {
  const HomeMilestoneCard({super.key, required this.milestone});

  final HomeMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = _lead(theme);

    return HomePaperCard(
      stripe: lead,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.flag_outlined, size: 18, color: lead),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  milestone.target == null
                      ? 'המאגר שלך'
                      : '${milestone.friends} מתוך ${milestone.target} חברים',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: milestone.progress,
              minHeight: 7,
              backgroundColor: theme.colorScheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation<Color>(lead),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            milestone.message,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The nudge towards a first proposal.
///
/// Only ever shown to someone who has friends but has never opened an idea —
/// which is the one moment the app can say something genuinely useful about it.
/// It disappears the moment the first proposal exists and never returns, so it
/// cannot become another permanent box asking to be dealt with.
class HomeFirstIdeaCard extends StatelessWidget {
  const HomeFirstIdeaCard({
    super.key,
    required this.friends,
    required this.onOpenIdea,
  });

  final int friends;
  final VoidCallback onOpenIdea;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = _lead(theme);

    return HomePaperCard(
      stripe: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.favorite_border, size: 18, color: lead),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'עוד לא פתחת רעיון',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'יש כבר $friends חברים במאגר. אולי שניים מהם מתאימים זה לזה — '
            'רעיון ראשון הוא רק מחשבה שנשמרת.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenIdea,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('פתיחת רעיון ראשון'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bulk-import offer. Prominent but plainly secondary to adding from the
/// address book, and gone from this screen once the database is large enough
/// that it is no longer the fastest way to grow.
class HomeImportInvite extends StatelessWidget {
  const HomeImportInvite({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = _lead(theme);

    return HomePaperCard(
      stripe: lead,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: lead.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.auto_awesome, color: lead, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'יש לך מאגר אישי בקבוצת ווטסאפ או באקסל? ייבא אותו באמצעות '
              'כלי ה-AI',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 6),
          HomeArrowButton(
            background: lead.withValues(alpha: 0.12),
            foreground: lead,
          ),
        ],
      ),
    );
  }
}

/// "עוצרים רגע לחשוב על החברים" — the invitation into the continuous
/// think-about-someone view, at the head of המאגר שלי.
///
/// **Two lines on the reading edge, and one quiet mark at the other.** The
/// heading and the button under it both start at the right, so the block reads
/// as one sentence with its answer beneath it; a centred pill under a
/// right-aligned heading read as two things that happened to share a card.
///
/// **The mark is a line drawing of a cup of coffee**, recoloured the way the
/// home cards are — see [HomeLineArt]. It replaced a painted figure-with-a-cup
/// that was too detailed to read at this size.
///
/// It drops the mark below 300px of card or above 1.3x text, where keeping it
/// would leave the title three words wide.
class HomeThinkBanner extends StatelessWidget {
  const HomeThinkBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark
        ? AppColors.secondaryDarkDm
        : AppColors.secondaryInk;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool showPicture =
            constraints.maxWidth >= 300 && textScale <= 1.3;
        // The page's own card: plain paper, a soft shadow, and the copper rule
        // along the foot. It used to be a tinted, outlined panel — the same
        // wash the block below it wore, which made the head of המאגר שלי two
        // coloured boxes in a row.
        return HomePaperCard(
          stripe: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
          radius: 22,
          onTap: onTap,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // One line, shrunk rather than wrapped — see
                    // [HomeBannerTitle.singleLine].
                    HomeBannerTitle(
                      text: 'עוצרים רגע לחשוב על החברים',
                      color: dark ? theme.colorScheme.onSurface : accent,
                      singleLine: true,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: onTap,
                      // Scaled down rather than wrapped: a question
                      // broken across two lines inside a pill reads as
                      // two half-sentences.
                      style: FilledButton.styleFrom(
                        backgroundColor: dark
                            ? AppColors.secondaryDarkDm
                            : AppColors.secondary,
                        foregroundColor: dark
                            ? AppColors.onSecondary
                            : AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                        textStyle: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('על מי חושבים עכשיו?', maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ),
              if (showPicture) ...<Widget>[
                const SizedBox(width: 12),
                _CoffeeMark(accent: accent, dark: dark),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The cup of coffee beside "עוצרים רגע לחשוב על החברים", in a disc of the
/// block's own tint so the drawing's white ground never shows.
class _CoffeeMark extends StatelessWidget {
  const _CoffeeMark({required this.accent, required this.dark});

  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color disc = Color.alphaBlend(
      accent.withValues(alpha: dark ? 0.22 : 0.10),
      dark ? theme.colorScheme.surfaceContainerHighest : AppColors.surface,
    );

    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
      child: HomeLineArt(
        asset: 'assets/coffee_icon.png',
        ink: dark ? AppColors.secondaryDarkDm : accent,
        paper: disc,
      ),
    );
  }
}
