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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: dark
              ? <Color>[
                  theme.colorScheme.primary.withValues(alpha: 0.20),
                  theme.colorScheme.surface,
                ]
              : <Color>[
                  AppColors.primaryLight.withValues(alpha: 0.8),
                  AppColors.surface,
                ],
        ),
      ),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
      ),
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
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
    final Color lead = _lead(theme);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
      ),
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onOpenIdea,
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

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: lead.withValues(alpha: 0.35)),
          ),
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
        ),
      ),
    );
  }
}

/// "עוצרים רגע לחשוב על החברים" — the invitation into the continuous
/// think-about-someone view, and the warmest thing on the home screen.
///
/// **A card with a picture in it, not a banner with an icon on it.** It was one
/// tinted strip with a small glyph and the word "מתחילים" — legible, and
/// completely interchangeable with the six other tinted strips the page has had
/// at one time or another. This is the one block on the home screen that is an
/// invitation rather than a control, so it is allowed to look like one: painted
/// paper, and a real button.
///
/// **Its illustration is people, not paper.** It used to borrow the notepad
/// from "הוספת רעיון", which put the same picture in two places a thumb apart
/// and made the two blocks read as one repeated thing. This card is about
/// thinking of *people*, so it draws people: two little profile cards leaning
/// against each other with a heart between them, in the same warm vintage
/// palette the notepad is painted in.
///
/// It drops the picture entirely below 300px of card or above 1.3x text, where
/// keeping it would leave the sentence three words wide.
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
        // Held down deliberately: the block is two lines and a pill tall now,
        // and every pixel the picture takes is a pixel the card grows by.
        final double pictureWidth = (constraints.maxWidth * 0.24).clamp(
          72.0,
          92.0,
        );

        return Material(
          color: dark ? theme.colorScheme.surface : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withValues(alpha: 0.20)),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topEnd,
                  end: AlignmentDirectional.bottomStart,
                  colors: <Color>[
                    accent.withValues(alpha: dark ? 0.15 : 0.08),
                    dark ? theme.colorScheme.surface : AppColors.surface,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            // A statement, not a question. The block is an
                            // open door, and a question mark on the home
                            // screen asks for an answer the matchmaker did
                            // not come here to give.
                            'עוצרים רגע לחשוב על החברים',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              color: dark
                                  ? theme.colorScheme.onSurface
                                  : accent,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FilledButton.icon(
                              onPressed: onTap,
                              icon: const Icon(
                                Icons.people_alt_outlined,
                                size: 17,
                              ),
                              // Scaled down rather than wrapped. The
                              // label is a question, and a question
                              // broken across two lines inside a pill
                              // reads as two half-sentences; at 1.5x
                              // system text on a 320px phone there is no
                              // room for it at full size and no room to
                              // wrap it either.
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'על מי חושבים עכשיו?',
                                  maxLines: 1,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: dark
                                    ? AppColors.secondaryDarkDm
                                    : AppColors.secondary,
                                foregroundColor: dark
                                    ? AppColors.onSecondary
                                    : AppColors.surface,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: theme.textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showPicture) ...<Widget>[
                      const SizedBox(width: 10),
                      _ThinkPeopleArt(size: pictureWidth, accent: accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The card's illustration: two profile cards leaning towards each other with
/// a heart where they meet.
///
/// Drawn here rather than shipped as an image so it takes the warm vintage
/// palette from the theme in both light and dark, and so it can never be
/// confused with the notepad photograph "הוספת רעיון" uses.
class _ThinkPeopleArt extends StatelessWidget {
  const _ThinkPeopleArt({required this.size, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color paper = dark
        ? Color.alphaBlend(accent.withValues(alpha: 0.16), theme.colorScheme.surface)
        : AppColors.surface;

    return SizedBox(
      width: size,
      height: size,
      child: Semantics(
        excludeSemantics: true,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // The two cards, tilted a few degrees apart, the front one warmer
            // and slightly larger so the pair reads as two people rather than
            // as one card with a shadow.
            Transform.translate(
              offset: Offset(-size * 0.13, -size * 0.04),
              child: Transform.rotate(
                angle: -0.16,
                child: _ProfileCardArt(
                  width: size * 0.50,
                  height: size * 0.66,
                  paper: paper,
                  accent: accent,
                  alpha: 0.55,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(size * 0.14, size * 0.05),
              child: Transform.rotate(
                angle: 0.14,
                child: _ProfileCardArt(
                  width: size * 0.52,
                  height: size * 0.70,
                  paper: paper,
                  accent: accent,
                  alpha: 0.85,
                ),
              ),
            ),
            // The heart sits where the two cards overlap: the whole point of
            // the picture in one small mark.
            PositionedDirectional(
              top: size * 0.04,
              start: size * 0.34,
              child: Icon(
                Icons.favorite_rounded,
                size: size * 0.24,
                color: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One little profile card in the illustration: a head, and two ruled lines
/// where a name would be.
class _ProfileCardArt extends StatelessWidget {
  const _ProfileCardArt({
    required this.width,
    required this.height,
    required this.paper,
    required this.accent,
    required this.alpha,
  });

  final double width;
  final double height;
  final Color paper;
  final Color accent;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final Color ink = accent.withValues(alpha: alpha);

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: width * 0.14),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(width * 0.20),
        border: Border.all(color: ink.withValues(alpha: alpha * 0.55)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: width * 0.34,
            height: width * 0.34,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
          ),
          SizedBox(height: height * 0.09),
          _ArtRule(width: width * 0.62, color: ink),
          SizedBox(height: height * 0.06),
          _ArtRule(width: width * 0.42, color: ink.withValues(alpha: alpha * 0.6)),
        ],
      ),
    );
  }
}

class _ArtRule extends StatelessWidget {
  const _ArtRule({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
