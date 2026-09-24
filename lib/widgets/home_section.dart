import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The shared building blocks of the home screen.
///
/// The page is deliberately *not* one repeated card, but neither is it a
/// different card per area — the previous version had drifted into five
/// variations on a rounded white rectangle, and then into a corkboard with
/// paper notes pinned to it, which was a sixth. What is left is two shapes
/// that earn their difference: the wave the suggestions float on, and the
/// plain bordered surface everything else uses. One section header, one inset,
/// one gap, one "הצגת הכל" — and one accent bar, which lives in
/// `accent_stripe.dart` because it is not only this page's.

bool homeIsNarrow(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  return width > 0 && width < 350;
}

double homeHorizontalInset(BuildContext context) =>
    homeIsNarrow(context) ? 10 : HomeConfig.carouselPadding;

double homeCardGap(BuildContext context) =>
    homeIsNarrow(context) ? 8 : HomeConfig.cardGap;

/// A fixed dimension, grown with the system font and nothing else.
///
/// Capped at 1.6×: past that a "fixed" box has stopped being fixed and the
/// layout is better served by the text ellipsizing.
double homeScaled(BuildContext context, double base) {
  final double scale = MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, 1.6);
  return base * scale;
}

/// **The one card the app's blocks are drawn on.**
///
/// Every panel worth reading on בית, המאגר שלי and הרעיונות שלי is this: the
/// paper the page is made of, a soft shadow lifting it off the cream ground,
/// and one coloured rule along its foot saying what kind of thing it is. It is
/// the shape the two entry cards ("הוספת חברים", "הוספת רעיון") already wore,
/// pulled out of them so that every other block can be evidently the same
/// family rather than a tinted panel of its own invention.
///
/// No border and no coloured fill: a wash *and* an outline is two edges for one
/// shape, and a page of five tinted panels reads as wallpaper. The colour is
/// all in [stripe].
class HomePaperCard extends StatelessWidget {
  const HomePaperCard({
    super.key,
    required this.child,
    this.stripe,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.onTap,
    this.radius = 20,
    this.elevation = 2,
  });

  final Widget child;

  /// The rule along the foot, in one of the palette's colours. Null draws no
  /// rule — for a card that is only a container for other carded things.
  final Color? stripe;

  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color? rule = stripe;

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(padding: padding, child: child),
        if (rule != null) AccentUnderline(color: rule),
      ],
    );

    return Material(
      color: dark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      elevation: dark ? 0 : elevation,
      // A neutral shadow, never one tinted with the rule's colour: a tinted
      // shadow reads as a halo drawn round the card rather than as the card
      // sitting above the page.
      shadowColor: AppColors.onSurface.withValues(alpha: 0.20),
      // Material 3 would otherwise lighten a raised surface towards
      // `surfaceTint`, drifting the paper off the colour the page uses.
      surfaceTintColor: Colors.transparent,
      // The rule is flush to the bottom edge; this clip is what rounds it.
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// A section title, optionally with a "הצג הכל" shortcut.
///
/// The titles run bare. Each one used to carry a small glyph beside it, and
/// five of them down one page added up to a column of decoration nobody read —
/// the words already say which block this is.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.onSeeAll,
    this.expanded,
    this.onToggle,
  });

  final String title;

  /// Left null on the home page. Kept for a section elsewhere that has a real
  /// reason to be marked.
  final IconData? icon;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  /// Non-null on a section that can be folded away, which turns the whole
  /// header into the control: a chevron on the end, and the title itself as the
  /// tap target. Null leaves the header a plain label.
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();
    final bool? open = expanded;

    final Widget titleRow = Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
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
            child: const Text('הצגת הכל'),
          ),
        if (open != null)
          Icon(
            open
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: AppColors.muted(dark: theme.brightness == Brightness.dark),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        homeHorizontalInset(context),
        homeIsNarrow(context) ? 16 : 20,
        homeHorizontalInset(context),
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (open == null)
            titleRow
          else
            // The whole line is the control, not just the chevron: on a folded
            // section the title *is* the way in, and a 24pt arrow at the far
            // edge of a phone is the hardest part of it to hit.
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: titleRow,
              ),
            ),
          if (sub != null && sub.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(height: 1.25),
            ),
          ],
        ],
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

/// The soft wave the suggestion circles stand on, instead of a row of boxes.
///
/// The water is alive but never busy: the crest slides sideways as the page is
/// scrolled — so the movement is something the user does, not something the
/// screen does at them — over a very slow idle bob, and every few seconds a
/// couple of small droplets pop above the surface and fade.
class HomeWaveBackground extends StatefulWidget {
  const HomeWaveBackground({super.key, required this.child});

  final Widget child;

  @override
  State<HomeWaveBackground> createState() => _HomeWaveBackgroundState();
}

class _HomeWaveBackgroundState extends State<HomeWaveBackground>
    with SingleTickerProviderStateMixin {
  /// One full turn of the idle bob and of the splash cycle.
  static const Duration _period = Duration(seconds: 9);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  )..repeat();

  /// The page's scroll offset, republished for the painter alone so scrolling
  /// never rebuilds the row of circles above the wave.
  final ValueNotifier<double> _scroll = ValueNotifier<double>(0);

  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) {
      return;
    }
    _position?.removeListener(_handleScroll);
    _position = position;
    _position?.addListener(_handleScroll);
    _handleScroll();
  }

  void _handleScroll() {
    final ScrollPosition? position = _position;
    if (position == null || !position.hasPixels) {
      return;
    }
    _scroll.value = position.pixels;
  }

  @override
  void dispose() {
    _position?.removeListener(_handleScroll);
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color color = theme.colorScheme.primary.withValues(
      alpha: dark ? 0.10 : 0.13,
    );
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_controller, _scroll]),
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _WavePainter(
            color: color,
            // A quarter of the page's travel: the water drifts, it does not
            // race the content past it.
            drift: _scroll.value * 0.25,
            time: _controller.value,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.color,
    required this.drift,
    required this.time,
  });

  final Color color;

  /// Scroll travel used to advance the gentle flow cycle.
  final double drift;

  /// 0..1, one turn of the idle bob and of the splash cycle.
  final double time;

  /// Mirrored splash positions keep the whole waterline visually balanced.
  static const List<double> _splashAt = <double>[0.2, 0.5, 0.8];

  /// How much of one cycle a single splash lasts.
  static const double _splashSpan = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final double baseline = size.height * 0.34;
    final double amplitude = size.height * 0.055;
    final double flowPhase = time * 2 * math.pi + drift / 120;
    final double bob = math.sin(flowPhase);
    final double breathing = 0.96 + math.cos(flowPhase) * 0.04;

    double crestY(double x) {
      final double t = x / size.width;
      return baseline +
          amplitude * breathing * math.cos((t - 0.5) * 4 * math.pi) +
          bob * size.height * 0.01;
    }

    // A single mirrored frequency gives equal crests and troughs on both
    // sides. The baseline and amplitude breathe together, so it still flows
    // without the uneven interference pattern created by mixed frequencies.
    const int steps = 48;
    final Path water = Path()..moveTo(0, crestY(0));
    for (int i = 1; i <= steps; i++) {
      final double x = size.width * i / steps;
      water.lineTo(x, crestY(x));
    }
    water
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(water, Paint()..color = color);

    for (int i = 0; i < _splashAt.length; i++) {
      // The outer pair rises together; the centre follows half a cycle later.
      final double cycle = (time + (i == 1 ? 0.5 : 0)) % 1;
      if (cycle > _splashSpan) {
        continue;
      }
      _paintSplash(
        canvas,
        size,
        x: size.width * _splashAt[i],
        surfaceY: crestY(size.width * _splashAt[i]),
        progress: cycle / _splashSpan,
      );
    }
  }

  /// Two droplets and a small ring: they rise, slow down and fade, which is all
  /// a splash needs to read as one at this size.
  void _paintSplash(
    Canvas canvas,
    Size size, {
    required double x,
    required double surfaceY,
    required double progress,
  }) {
    final double fade = 1 - progress;
    final double lift = math.sin(progress * math.pi) * size.height * 0.075;
    final Paint paint = Paint()
      ..color = color.withValues(alpha: color.a * fade);

    canvas.drawCircle(
      Offset(x - 3.5, surfaceY - lift),
      1.8 * fade + 0.5,
      paint,
    );
    canvas.drawCircle(
      Offset(x + 3, surfaceY - lift * 0.72),
      1.4 * fade + 0.4,
      paint,
    );
    canvas.drawCircle(
      Offset(x, surfaceY),
      2 + progress * 7,
      Paint()
        ..color = color.withValues(alpha: color.a * fade * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.drift != drift ||
        oldDelegate.time != time;
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
    final Color tone =
        color ?? AppColors.muted(dark: theme.brightness == Brightness.dark);

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
    this.icon = Icons.chevron_right,
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

/// The heading of one of the two invitations at the top of the home page —
/// "עוצרים רגע לחשוב על חברים" and "רעיונות שהמאגר מציע לך".
///
/// **One widget because the two have to be the same size, and could not be.**
/// Both asked for `titleLarge` and both were wrapped in a `FittedBox`, so what
/// each of them was actually drawn at came out of the width left over on its
/// own card — a picture on one, a pair of portraits and a chevron on the other
/// — and the two blocks that sit one above the other were headed at two
/// different sizes. The size is fixed here instead, and what gives is the
/// number of lines: a heading that wraps on a narrow phone is still the same
/// heading as the one above it, and a heading that shrinks is not.
class HomeBannerTitle extends StatelessWidget {
  const HomeBannerTitle({
    super.key,
    required this.text,
    this.color,
    this.singleLine = false,
  });

  final String text;

  /// The block's own accent, where it has one. Defaults to the page's ink.
  final Color? color;

  /// Keeps the heading on one line, shrinking it to fit rather than wrapping.
  ///
  /// The exception to the rule above, and it is allowed exactly where the rule
  /// has nothing left to protect: a banner that no longer sits above a second
  /// banner has nothing to be the same size *as*. The two are on separate
  /// pages now — "עוצרים רגע לחשוב על החברים" heads המאגר שלי and "רעיונות
  /// שהמאגר מציע לך" heads הרעיונות שלי — and a heading that wraps to two
  /// lines makes its block taller than the one invitation inside it deserves.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget label = Text(
      text,
      // No line cap by default. What gives at a large system font on a narrow
      // phone is the number of lines, never the size: two blocks that sit one
      // above the other and are headed at two different sizes read as a banner
      // with a footnote, which is exactly what the `FittedBox` on each of them
      // used to produce.
      maxLines: singleLine ? 1 : null,
      softWrap: !singleLine,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        height: 1.15,
        color: color ?? theme.colorScheme.onSurface,
      ),
    );

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: singleLine
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: label,
            )
          : label,
    );
  }
}

/// One of the app's hand-drawn line illustrations, wearing the colour of
/// whatever block it is on.
///
/// The drawings arrive as black ink on a white ground with no alpha channel, so
/// dropping one onto a coloured card would paste a white rectangle over it and
/// dropping one into the dark theme would put a lightbox in the middle of the
/// page. Blend modes do the whole job without touching the files, and which
/// ones depends on which way round the card is:
///
///  * **Dark drawing on a light card** — `screen` leaves white alone and turns
///    black into [ink]; `multiply` then leaves that alone and turns the white
///    ground into [paper].
///  * **Light drawing on a dark card** — neither mode can lighten a stroke
///    while darkening the ground, so the image is *inverted* first. `multiply`
///    then turns the (now white) strokes into [ink] and leaves the black ground
///    alone, and `screen` lifts that ground to [paper].
///
/// Which of the two is in play is read off the colours themselves rather than
/// off the theme: a caller that wants pale strokes on a dark ground has already
/// said so by passing a [paper] darker than its [ink].
///
/// Either way the result is a drawing in [ink] on [paper], from one asset, in
/// either theme — and the source files stay exactly as they were drawn.
class HomeLineArt extends StatelessWidget {
  const HomeLineArt({
    super.key,
    required this.asset,
    required this.ink,
    required this.paper,
    this.fit = BoxFit.contain,
  });

  final String asset;

  /// What the black strokes become.
  final Color ink;

  /// What the white ground becomes.
  final Color paper;

  final BoxFit fit;

  /// Flips every channel. The one step that lets a light stroke sit on a dark
  /// ground, which no single blend of these two colours can produce.
  static const List<double> _invert = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    // **The white ground is painted, not assumed.** `ColorFilter.mode` is
    // applied to a whole layer, and for these blend modes an opaque source over
    // a transparent destination comes out opaque — so every pixel the drawing
    // does not cover, the letterbox `BoxFit.contain` leaves around it included,
    // came out the colour of a stroke and drew a hard frame round the picture.
    // Extending the drawing's own white ground across the box is what makes the
    // filters see one uniform white to recolour.
    final Widget image = ColoredBox(
      color: Colors.white,
      child: Image.asset(
        asset,
        fit: fit,
        // Whatever the drawing shows, the words beside it say it better.
        excludeFromSemantics: true,
      ),
    );

    // Darker ground than strokes means the drawing has to come out light, which
    // is the inverted path.
    final Widget filtered = paper.computeLuminance() < ink.computeLuminance()
        ? ColorFiltered(
            colorFilter: ColorFilter.mode(paper, BlendMode.screen),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(ink, BlendMode.multiply),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(_invert),
                child: image,
              ),
            ),
          )
        : ColorFiltered(
            colorFilter: ColorFilter.mode(paper, BlendMode.multiply),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(ink, BlendMode.screen),
              child: image,
            ),
          );

    // **And the whole thing is clipped to its own box.** A `ColorFiltered`
    // becomes a compositing layer, and a layer whose filter turns transparent
    // into opaque paints that opacity over everything up to the nearest clip —
    // which here was the entire card, label band included. The clip is what
    // keeps the recolouring inside the picture.
    return ClipRect(child: filtered);
  }
}
