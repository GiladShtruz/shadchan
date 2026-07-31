import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The shared building blocks of the home screen.
///
/// The page is deliberately *not* one repeated card: every area has its own
/// shape. The board keeps the square [HomeMiniCard] (a pinned item carries a
/// note, a reminder and a menu), recent actions are low wide strips, open ideas
/// are short centred cards, and the people worth a thought are free circles on
/// a soft wave. What they share is the cream canvas, the same soft corners and
/// the same very light lines.

/// Grows a fixed box with the system font, so the cards keep fitting their text
/// instead of overflowing at a larger accessibility setting.
double homeScaled(BuildContext context, double base) {
  final double scale = MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, 1.6);
  return base * scale;
}

/// The board card's box.
double homeCardHeight(BuildContext context) {
  return homeScaled(context, HomeConfig.cardHeight);
}

/// A section title, optionally with a "הצג הכל" shortcut.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onSeeAll,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HomeConfig.carouselPadding + 2,
        20,
        HomeConfig.carouselPadding,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('הצג הכל'),
                ),
            ],
          ),
          if (sub != null && sub.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A horizontal row of cards. The side padding is smaller than a card, so the
/// next one always peeks in from the edge and the row reads as scrollable
/// without needing an arrow.
class HomeCarousel extends StatelessWidget {
  const HomeCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.height,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  /// The row's fixed height. Defaults to the board card's box.
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? homeCardHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: HomeConfig.carouselPadding,
        ),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: HomeConfig.cardGap),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// The frame the board's notes run inside: a thin line around the whole row,
/// on a wash a shade warmer than the page, so the notes read as pinned to one
/// board instead of floating on the cream canvas.
class HomeNoteBoard extends StatelessWidget {
  const HomeNoteBoard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HomeConfig.carouselPadding,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: HomeConfig.boardFramePadding,
        ),
        decoration: BoxDecoration(
          color: dark
              ? AppColors.secondaryDarkDm.withValues(alpha: 0.08)
              : AppColors.secondaryLight.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: (dark ? AppColors.secondaryDarkDm : AppColors.secondary)
                .withValues(alpha: 0.35),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// One item on the board, drawn as a paper note: a strip of tape at the top,
/// the avatars centred under it, the name below them, the pinned note and
/// reminder, and the actions button along the bottom edge — which is also the
/// menu, so the resting screen still shows nothing open.
class HomeBoardNote extends StatelessWidget {
  const HomeBoardNote({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    required this.actions,
    this.subtitle,
    this.footer,
    this.tintSeed = '',
  });

  /// The avatar (or pair of avatars) at the top of the note.
  final Widget leading;

  final String title;
  final VoidCallback onTap;

  /// The full-width button along the bottom. Given a [PopupMenuButton] it opens
  /// the same options the old corner menu had.
  final Widget actions;

  /// The pinned note in the matchmaker's words.
  final String? subtitle;

  /// The reminder line, when one is set.
  final Widget? footer;

  /// Keeps the same person or proposal on the same paper colour between
  /// builds, so the board looks hand-arranged rather than random.
  final String tintSeed;

  /// The papers the notes are torn from — all from the app's own pastels.
  static const List<Color> _papers = <Color>[
    AppColors.softYellow,
    AppColors.softRose,
    AppColors.softGreen,
    AppColors.softBlue,
    AppColors.softSand,
    AppColors.softPurple,
  ];

  Color _paperFor(ThemeData theme) {
    int hash = 0;
    for (final int unit in tintSeed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final Color paper = _papers[hash % _papers.length];
    return theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            paper.withValues(alpha: 0.16),
            theme.colorScheme.surface,
          )
        : paper.withValues(alpha: 0.55);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();
    final Color paper = _paperFor(theme);

    return SizedBox(
      width: HomeConfig.cardWidth,
      height: homeCardHeight(context),
      child: Material(
        color: paper,
        // A note is torn paper: square-ish corners, only barely rounded.
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: <Widget>[
                  _NoteTape(color: theme.colorScheme.surface),
                  const SizedBox(height: 6),
                  leading,
                  const SizedBox(height: 7),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (footer != null) ...<Widget>[
                    const SizedBox(height: 4),
                    footer!,
                  ],
                  const Spacer(),
                  actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The little strip of tape that holds a note to the board.
class _NoteTape extends StatelessWidget {
  const _NoteTape({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.05,
      child: Container(
        width: 46,
        height: 9,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The board note's bottom button: the same options the corner menu used to
/// hold, in a control that can actually be seen and hit.
class HomeNoteActionsButton extends StatelessWidget {
  const HomeNoteActionsButton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.tune_rounded,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// "הפעולות האחרונות שלך": a low, wide strip — avatars at the start, then the
/// name, what was done and when.
class HomeActivityCard extends StatelessWidget {
  const HomeActivityCard({
    super.key,
    required this.leading,
    required this.title,
    required this.action,
    required this.timeAgo,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String action;
  final String timeAgo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: HomeConfig.activityCardWidth,
      height: homeScaled(context, HomeConfig.activityCardHeight),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 14, 8),
            child: Row(
              children: <Widget>[
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        // A long name wraps onto a second line instead of being
                        // cut; the box itself stays the same size for every
                        // card, so the row still reads as one strip.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$action · $timeAgo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          height: 1.1,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// "רעיונות פתוחים": a short card whose whole content — the overlapping photos,
/// the two names and the status — sits centred in the box.
class HomeIdeaCard extends StatelessWidget {
  const HomeIdeaCard({
    super.key,
    required this.personA,
    required this.personB,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.onTap,
    this.marker,
  });

  final Person? personA;
  final Person? personB;
  final String title;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;

  /// A small corner mark — used for a reminder that came due.
  final Widget? marker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: HomeConfig.ideaCardWidth,
      height: homeScaled(context, HomeConfig.ideaCardHeight),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Stack(
              children: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        HomeCardCoupleAvatars(
                          personA: personA,
                          personB: personB,
                          radius: 17,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        HomeCardFooter(
                          label: status,
                          color: statusColor,
                          tinted: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (marker != null)
                  PositionedDirectional(top: 6, start: 6, child: marker!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark on a card whose reminder has come due: small, but the one thing on
/// the home screen that is allowed to shout a little.
class HomeAlertBadge extends StatelessWidget {
  const HomeAlertBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.notifications_active,
        size: 11,
        color: AppColors.onPrimary,
      ),
    );
  }
}

/// "חברים ששווה לחשוב עליהם": a free circle with a name and one line of
/// reasoning under it. No frame at all — the row's soft wave carries them.
class HomeSuggestionBubble extends StatelessWidget {
  const HomeSuggestionBubble({
    super.key,
    required this.person,
    required this.reason,
    required this.onTap,
  });

  final Person person;
  final String reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: HomeConfig.suggestionBubbleWidth,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark
                      ? theme.colorScheme.surface
                      : AppColors.surface.withValues(alpha: 0.9),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: PersonAvatar(person: person, radius: 29),
              ),
              const SizedBox(height: 7),
              Text(
                person.fullName.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                reason,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  height: 1.25,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The soft wave the suggestion circles stand on, instead of a row of boxes.
class HomeWaveBackground extends StatelessWidget {
  const HomeWaveBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return CustomPaint(
      painter: _WavePainter(
        color: theme.colorScheme.primary.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.10 : 0.13,
        ),
      ),
      child: child,
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double top = size.height * 0.34;
    final Path path = Path()
      ..moveTo(0, top + size.height * 0.10)
      ..cubicTo(
        size.width * 0.25,
        top - size.height * 0.10,
        size.width * 0.55,
        top + size.height * 0.20,
        size.width,
        top - size.height * 0.02,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.color != color;
}

/// The single avatar used on the person-shaped cards.
class HomeCardAvatar extends StatelessWidget {
  const HomeCardAvatar({super.key, required this.person, this.radius = 22});

  final Person? person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final Person? current = person;
    if (current == null) {
      final ThemeData theme = Theme.of(context);
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_off_outlined,
          size: radius,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return PersonAvatar(person: current, radius: radius);
  }
}

/// The two overlapping avatars used on the proposal-shaped cards. Sized from
/// the ringed diameter, so a [Stack] never shaves a sliver off a photo.
class HomeCardCoupleAvatars extends StatelessWidget {
  const HomeCardCoupleAvatars({
    super.key,
    required this.personA,
    required this.personB,
    this.radius = 22,
    this.ringColor,
  });

  final Person? personA;
  final Person? personB;
  final double radius;

  /// The colour of the thin ring between the two photos. Defaults to the
  /// surface, which is what makes them read as overlapping.
  final Color? ringColor;

  static const double _ring = 2;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double ringed = radius * 2 + _ring * 2;
    final double overlap = radius * 0.55;

    Widget avatar(Person? person) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ringColor ?? theme.colorScheme.surface,
            width: _ring,
          ),
        ),
        child: HomeCardAvatar(person: person, radius: radius),
      );
    }

    return SizedBox(
      height: ringed,
      width: ringed * 2 - overlap,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(start: 0, child: avatar(personA)),
          PositionedDirectional(
            start: ringed - overlap,
            child: avatar(personB),
          ),
        ],
      ),
    );
  }
}

/// The quiet bottom line of a card: a short label in the card's accent.
class HomeCardFooter extends StatelessWidget {
  const HomeCardFooter({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.tinted = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;

  /// Wraps the line in a soft pill — used for a proposal's status, where the
  /// colour carries real meaning.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = color ?? theme.colorScheme.onSurfaceVariant;

    final Widget line = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (!tinted) {
      return line;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: line,
    );
  }
}

/// The small round chevron that ends an action card, in the card's own tone.
class HomeArrowButton extends StatelessWidget {
  const HomeArrowButton({
    super.key,
    required this.background,
    required this.foreground,
    this.size = 30,
    this.icon = Icons.chevron_left,
  });

  final Color background;
  final Color foreground;
  final double size;

  /// The chevron itself, so a card can point the arrow the way its own layout
  /// reads.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.62, color: foreground),
    );
  }
}
