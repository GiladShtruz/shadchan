import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The shared building blocks of the home screen.
///
/// Every row on the page is a [HomeCarousel] of [HomeMiniCard]s of exactly the
/// same size, so the whole screen reads as one system and as many cards as
/// possible fit next to each other. Sections carry no frame or background of
/// their own — only a right-aligned title — which is what keeps the page calm
/// as it grows.

/// The card box, grown for a larger system font so the fixed-height cards keep
/// fitting their text instead of overflowing. Every row computes it from the
/// same context, so all the cards on screen stay exactly the same size.
double homeCardHeight(BuildContext context) {
  final double scale = MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, 1.6);
  return HomeConfig.cardHeight * scale;
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
        HomeConfig.carouselPadding,
        18,
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

/// A horizontal row of equally sized cards. The side padding is smaller than a
/// card, so the next one always peeks in from the edge and the row reads as
/// scrollable without needing an arrow.
class HomeCarousel extends StatelessWidget {
  const HomeCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: homeCardHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
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

/// The one card shape the home screen uses everywhere: a fixed box with an
/// avatar block on top, a name, an optional two-line note and an optional
/// footer line pinned to the bottom.
class HomeMiniCard extends StatelessWidget {
  const HomeMiniCard({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.footer,
    this.menu,
    this.background,
    this.borderColor,
  });

  /// The avatar (or pair of avatars) at the top of the card.
  final Widget leading;

  final String title;
  final VoidCallback onTap;

  /// The quiet second line — a note, a reason, what the last action was.
  final String? subtitle;

  /// The bottom line: a status, a date, how long ago. Rendered in [accent].
  final Widget? footer;

  /// An optional corner button. Kept to a single icon so the resting screen
  /// still shows no open menus.
  final Widget? menu;

  /// Overrides for the one row that is meant to feel different — the couples
  /// who are dating, which is a moment of celebration rather than a task.
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();

    return SizedBox(
      width: HomeConfig.cardWidth,
      height: homeCardHeight(context),
      child: Material(
        color: background ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor ?? theme.colorScheme.outlineVariant,
              ),
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                  child: Column(
                    children: <Widget>[
                      leading,
                      const SizedBox(height: 8),
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
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                      ],
                      const Spacer(),
                      ?footer,
                    ],
                  ),
                ),
                if (menu != null)
                  PositionedDirectional(top: 0, start: 0, child: menu!),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
  });

  final Person? personA;
  final Person? personB;
  final double radius;

  static const double _ring = 2;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double ringed = radius * 2 + _ring * 2;

    Widget avatar(Person? person) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.surface, width: _ring),
        ),
        child: HomeCardAvatar(person: person, radius: radius),
      );
    }

    return SizedBox(
      height: ringed,
      width: ringed * 2 - _overlap,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(start: 0, child: avatar(personA)),
          PositionedDirectional(
            start: ringed - _overlap,
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
