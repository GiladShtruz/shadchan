import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_promote.dart';
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
            'כאן נשמרים החברים שאת/ה חושב/ת עליהם, הרעיונות שנפתחו ומה קרה '
            'איתם. מתחילים בהוספת כמה חברים — כל אחד שנוסף פותח כיוון.',
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

/// The invitation into the continuous "think about someone" view. Warm rather
/// than urgent — it is an offer to sit and think, not a queue with a count.
class HomeThinkBanner extends StatelessWidget {
  const HomeThinkBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: dark
                  ? <Color>[
                      AppColors.secondaryDarkDm.withValues(alpha: 0.22),
                      theme.colorScheme.surface,
                    ]
                  : <Color>[AppColors.secondaryLight, AppColors.surface],
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.self_improvement_outlined,
                color: dark
                    ? AppColors.secondaryDarkDm
                    : AppColors.secondaryInk,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'עוצרים רגע לחשוב על שידוך?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: dark
                        ? theme.colorScheme.onSurface
                        : AppColors.secondaryInk,
                  ),
                ),
              ),
              HomeArrowButton(
                background:
                    (dark ? AppColors.secondaryDarkDm : AppColors.secondaryInk)
                        .withValues(alpha: 0.14),
                foreground: dark
                    ? AppColors.secondaryDarkDm
                    : AppColors.secondaryInk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single number line. Tapping it opens the numbers screen — the page it
/// leads to is where charts belong, not here.
class HomeStatBanner extends StatelessWidget {
  const HomeStatBanner({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark
        ? AppColors.femaleAccentDm
        : AppColors.femaleAccent;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.favorite, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              HomeArrowButton(
                background: accent.withValues(alpha: 0.14),
                foreground: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One card of "שווה לקדם": who or what, and one line saying why it is here.
class HomePromoteCard extends StatelessWidget {
  const HomePromoteCard({super.key, required this.item, required this.onTap});

  final HomePromoteItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? person = item.person;

    return SizedBox(
      width: homeActivityCardWidth(context),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (person != null)
                  HomeCardAvatar(person: person, radius: 21)
                else
                  HomeCardCoupleAvatars(
                    personA: item.personA,
                    personB: item.personB,
                    radius: 16,
                  ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                // The reason is the whole point of the card: without it this is
                // just a face, and the matchmaker has to work out for themselves
                // why the app put it there.
                Text(
                  item.reason,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
