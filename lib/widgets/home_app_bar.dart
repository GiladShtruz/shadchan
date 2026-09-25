import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The app's own mark, on nothing.
///
/// One white asset tinted at draw time with a `srcIn` filter, so the light and
/// the dark theme share a file and the mark can never fall out of step with the
/// palette. It sits directly on the page — no tile, no disc, no card behind it
/// — because the launcher icon's blue-grey square is chrome that belongs to the
/// home screen of the *phone*, and repeating it inside the app makes the bar
/// look like it is showing an app icon rather than wearing a logo.
class ShadchanLogo extends StatelessWidget {
  const ShadchanLogo({super.key, this.size = 24, this.color});

  final double size;

  /// Defaults to the palette's light blue, lightened again in the dark theme.
  ///
  /// The mark wears `primary` and the word beside it `primaryInk`: the two are
  /// the palette's light blue and its deep blue, one pair rather than two
  /// neighbouring blue-greys that only look like the same decision.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color ink =
        color ??
        (theme.brightness == Brightness.dark
            ? AppColors.primaryDarkDm
            : AppColors.primary);

    return ColorFiltered(
      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
      child: Image.asset(
        'assets/logo_mark.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// The logo and the app's name, side by side, for the middle of the home bar.
///
/// The word is deliberately small and quiet. A masthead the size of a heading
/// would be the largest thing on a screen whose whole job is to put the
/// matchmaker's own work in front of them; this is a signature, not a title.
class ShadchanWordmark extends StatelessWidget {
  const ShadchanWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Scaled down rather than clipped or wrapped. The title slot of an
    // `AppBar` is whatever the leading and the actions leave behind, so on a
    // 320px phone at a large system font it can be narrower than the logo and
    // the word laid side by side — and a masthead that overflows is the one
    // thing on this bar nobody would report as a bug, they would just see a
    // yellow-and-black stripe.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // First child sits at the start edge, which in RTL is the right — the
          // mark leads and the word follows it, the way it is read.
          const ShadchanLogo(size: 24),
          const SizedBox(width: 6),
          Text(
            'שדכן',
            // The page's heading ink: the app's own name is the first
            // heading on the screen, and a second blue for it would be one
            // more "nearly the same" tone — see [AppColors.headingInk].
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: AppColors.heading(
                dark: theme.brightness == Brightness.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One control in the home bar: an icon inside a soft rounded square.
///
/// **A square rather than a bare icon**, because the bar now carries three of
/// them in a row at one end and a photograph at the other. Bare icons in a row
/// read as a strip of decoration; boxed ones read as three separate buttons,
/// which is what they are — and the box is what makes the group balance the
/// round photograph across the bar instead of trailing off into the corner.
class HomeBarButton extends StatelessWidget {
  const HomeBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showDot = false,
    this.badgeCount = 0,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// A small mark saying there is something behind this button. A dot and not a
  /// number: the count lives inside the panel the button opens, and a badge on
  /// a small square is read as "there is something" long before it is read as
  /// "there are four".
  final bool showDot;

  /// A number on the corner of the square — how many open notifications wait
  /// behind the bell. Drawn whenever it is above zero, in place of the dot,
  /// and it moves the moment one arrives, is read, handled or deleted,
  /// because the bell watches everything it counts.
  final int badgeCount;

  /// Sized to leave the bar's middle slot room for the wordmark on a 320px
  /// phone: three of these, their gaps and the photograph opposite them are all
  /// subtracted from it before the title gets a pixel.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: dark
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Ink(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.9,
                    ),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: <Widget>[
                    IconTheme.merge(
                      data: IconThemeData(
                        size: 20,
                        color: AppColors.heading(dark: dark),
                      ),
                      child: icon,
                    ),
                    if (showDot && badgeCount <= 0)
                      PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.error,
                            border: Border.all(
                              color: dark
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : theme.colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (badgeCount > 0)
            PositionedDirectional(
              top: -6,
              end: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "בוקר טוב, יצחק" — the first thing on the page, and not a card.
///
/// **It moved out of the app bar and onto the page itself.** In the bar it was
/// one line of bar-sized type competing with three icons and a photograph for a
/// 56px strip; here it has the width of the screen, it is the size a greeting
/// should be, and the bar above it is free to carry the app's own name.
///
/// **No frame, no tint, no card.** It is spoken, not displayed: a box around it
/// would make it a component, and the page already opens with two real cards
/// under it.
///
/// **And one short line under it**, in the page's ordinary voice, saying what
/// the day is for. It is the only sentence on the home screen that asks for
/// nothing: everything else either shows work or offers a way to do some.
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({
    super.key,
    required this.greeting,
    required this.name,
    this.line,
    this.trailing,
  });

  /// "בוקר טוב" / "צהריים טובים" / "ערב טוב" / "לילה טוב".
  final String greeting;

  /// The first name alone. A greeting is how somebody is spoken to, not how
  /// they are filed.
  final String name;

  /// The warm line under the greeting — "בוא ניצור היום חיבורים חדשים".
  final String? line;

  /// Something small at the other end of the greeting's first line — the far
  /// top corner, left in RTL. Holds "ניהול הכרטיס שלי" for a matchmaker who
  /// keeps a card of their own, so it costs the page no row of its own.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String? warm = line?.trim();

    final Widget greetingBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '$greeting, '),
              // The name in the warm accent: the one word on the line that is
              // about this particular person. The palette's brown, not a
              // near-miss of it — see [AppColors.secondary].
              TextSpan(
                text: name,
                style: TextStyle(
                  color: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
                ),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // No colour of its own: the greeting is the page's largest heading
          // and takes the page's heading ink with every other one. It used to
          // name `onSurface`, which is a warm near-black — the one brown on
          // the page that was not the palette's.
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        if (warm != null && warm.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            warm,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
          ),
        ],
      ],
    );

    final Widget? corner = trailing;
    if (corner == null) {
      return greetingBlock;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: greetingBlock),
        const SizedBox(width: 6),
        corner,
      ],
    );
  }
}
