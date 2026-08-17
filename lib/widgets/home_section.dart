import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The shared building blocks of the home screen.
///
/// The page is deliberately *not* one repeated card, but neither is it a
/// different card per area — the previous version had drifted into five
/// variations on a rounded white rectangle. What is left is three shapes that
/// each earn their difference: the corkboard, the wave the open ideas float on,
/// and the plain bordered surface everything else uses. One section header, one
/// inset, one gap, one "הצגת הכל".

bool homeIsNarrow(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  return width > 0 && width < 350;
}

double homeHorizontalInset(BuildContext context) =>
    homeIsNarrow(context) ? 10 : HomeConfig.carouselPadding;

double homeCardGap(BuildContext context) =>
    homeIsNarrow(context) ? 8 : HomeConfig.cardGap;

double homeBoardCardWidth(BuildContext context) =>
    homeIsNarrow(context) ? 144 : HomeConfig.cardWidth;

/// Every note on the board is exactly this tall.
///
/// It follows the *system font* and nothing else. Following the content would
/// bring back the board whose height depended on the longest note on it; not
/// following the font would clip a note for anyone reading at 1.5×, which is
/// the one reason a fixed box is ever allowed to grow.
double homeBoardCardHeight(BuildContext context) =>
    homeScaled(context, HomeConfig.cardHeight);

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
              fontSize: homeIsNarrow(context) ? 13 : null,
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
            color: theme.colorScheme.onSurfaceVariant,
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
              style: theme.textTheme.labelSmall?.copyWith(
                height: 1.25,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A real corkboard: a warm granular surface inside a thin wooden frame.
///
/// Fixed height by construction — the notes are one row and the row is one card
/// tall, so a board with twenty notes is exactly as tall as a board with one.
/// The vertical padding above the notes is what keeps every drawing pin whole.
class HomeNoteBoard extends StatelessWidget {
  const HomeNoteBoard({super.key, required this.child});

  final Widget child;

  /// The whole surface, notes and padding included. Independent of how many
  /// notes are pinned — that is the point of the row.
  static double height(BuildContext context) =>
      homeBoardCardHeight(context) +
      HomeConfig.boardPaddingTop +
      HomeConfig.boardPaddingBottom;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    // Cork is three browns, not one: a base, a darker grain and a lighter fleck.
    final Color base = dark ? const Color(0xFF6A5946) : const Color(0xFFD9B888);
    final Color grain = dark
        ? const Color(0xFF4A3D2F)
        : const Color(0xFFA97F4F);
    final Color fleck = dark
        ? const Color(0xFF8C7A62)
        : const Color(0xFFF0DCBB);
    final Color frame = dark
        ? const Color(0xFF3E3226)
        : const Color(0xFF9C7448);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: homeHorizontalInset(context)),
      child: Container(
        height: height(context),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          // The frame is a border rather than a second box, so the cork fills
          // the surface right up to the wood.
          border: Border.all(color: frame, width: 5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.30 : 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: CustomPaint(
            painter: _CorkPainter(base: base, grain: grain, fleck: fleck),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                HomeConfig.boardPaddingTop,
                0,
                HomeConfig.boardPaddingBottom,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cork, drawn rather than photographed.
///
/// Three passes over one deterministic pseudo-random sequence: coarse darker
/// granules, finer light flecks, then a soft vignette. A repeatable sequence
/// matters — a texture that reshuffles on every repaint shimmers while the page
/// is scrolled.
class _CorkPainter extends CustomPainter {
  const _CorkPainter({
    required this.base,
    required this.grain,
    required this.fleck,
  });

  final Color base;
  final Color grain;
  final Color fleck;

  /// A cheap deterministic hash — the same board draws the same grain forever.
  static double _noise(int seed) {
    int x = (seed * 1103515245 + 12345) & 0x7fffffff;
    x ^= x >> 13;
    return ((x * 1103515245) & 0x7fffffff) / 0x7fffffff;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final Rect area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = base);

    // Coarse granules.
    final Paint dark = Paint()..color = grain.withValues(alpha: 0.20);
    for (int i = 0; i < 520; i++) {
      final double x = _noise(i * 3 + 1) * size.width;
      final double y = _noise(i * 3 + 2) * size.height;
      final double r = 0.9 + _noise(i * 3 + 3) * 2.2;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: r * 2.1, height: r * 1.4),
        dark,
      );
    }

    // Light flecks, half as many and half as strong.
    final Paint light = Paint()..color = fleck.withValues(alpha: 0.22);
    for (int i = 0; i < 260; i++) {
      final double x = _noise(i * 5 + 7001) * size.width;
      final double y = _noise(i * 5 + 7002) * size.height;
      final double r = 0.6 + _noise(i * 5 + 7003) * 1.4;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 1.3),
        light,
      );
    }

    // A gentle darkening towards the frame, which is what makes it read as a
    // surface rather than as a flat swatch.
    canvas.drawRect(
      area,
      Paint()
        ..shader = RadialGradient(
          radius: 0.85,
          colors: <Color>[Colors.transparent, grain.withValues(alpha: 0.18)],
        ).createShader(area),
    );
  }

  @override
  bool shouldRepaint(_CorkPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.grain != grain ||
      oldDelegate.fleck != fleck;
}

/// One item on the board, drawn as a paper note: a small pin at the top,
/// the avatars and every line of text centred as one balanced group, and a
/// small arrow-only menu along the bottom edge.
class HomeBoardNote extends StatelessWidget {
  const HomeBoardNote({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    required this.actions,
    this.subtitle,
    this.tintSeed = '',
  });

  /// The avatar (or pair of avatars) at the top of the note.
  final Widget leading;

  final String title;
  final VoidCallback onTap;

  /// The small arrow menu along the bottom.
  final Widget actions;

  /// The pinned note in the matchmaker's words.
  final String? subtitle;

  /// Keeps the same person or proposal on the same paper colour between
  /// builds, so the board looks hand-arranged rather than random.
  final String tintSeed;

  /// Cream, pale blue and pale pink papers, matching the app palette.
  static const List<Color> _papers = <Color>[
    AppColors.softYellow,
    AppColors.softRose,
    AppColors.softBlue,
  ];

  int get _stableHash {
    int hash = 0;
    for (final int unit in tintSeed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  Color _paperFor(ThemeData theme) {
    final Color paper = _papers[_stableHash % _papers.length];
    return theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            paper.withValues(alpha: 0.16),
            theme.colorScheme.surface,
          )
        : paper.withValues(alpha: 0.55);
  }

  /// The full height the pin needs, reserved inside the note so no part of it
  /// can ever be cut by the paper's own clip.
  static const double _pinLane = 22;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();
    final Color paper = _paperFor(theme);

    // A hand-pinned note is never quite straight, but it is also never askew:
    // under a degree in either direction.
    final double angle = ((_stableHash % 7) - 3) * 0.005;

    return Transform.rotate(
      angle: angle,
      child: SizedBox(
        width: homeBoardCardWidth(context),
        height: homeBoardCardHeight(context),
        child: Material(
          color: paper,
          // A note is torn paper: square-ish corners, only barely rounded.
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
              child: Column(
                key: const ValueKey<String>('home-board-note-content'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(
                    height: _pinLane,
                    child: Center(child: _NotePin()),
                  ),
                  // The name, face and note ride the space that is left, so a
                  // one-line note and a two-line note produce the same box.
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        leading,
                        const SizedBox(height: 7),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if (sub != null && sub.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 3),
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
                      ],
                    ),
                  ),
                  Center(child: actions),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawing pin holding a note to the cork: a domed head with a highlight
/// and the shadow it casts on the paper. Always drawn whole — it lives inside
/// the note's own padding rather than hanging off its top edge.
class _NotePin extends StatelessWidget {
  const _NotePin();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 20, height: 20, child: _PinDot());
  }
}

class _PinDot extends StatelessWidget {
  const _PinDot();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const _PinPainter(), child: const SizedBox());
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter();

  /// One pin colour for the whole board. Three colours competing with three
  /// paper colours was the busiest thing on the surface.
  static const Color _body = Color(0xFFB0525C);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double r = size.shortestSide * 0.36;

    canvas
      ..drawOval(
        Rect.fromCenter(
          center: centre.translate(1.5, 3),
          width: r * 2.2,
          height: r * 1.2,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      )
      ..drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: <Color>[
              Color.lerp(_body, Colors.white, 0.45)!,
              _body,
              Color.lerp(_body, Colors.black, 0.30)!,
            ],
            stops: const <double>[0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: r)),
      )
      ..drawCircle(
        centre.translate(-r * 0.32, -r * 0.34),
        r * 0.22,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => false;
}

/// The board note's clean, arrow-only menu banner.
class HomeNoteActionsButton extends StatelessWidget {
  const HomeNoteActionsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: 48,
      height: 26,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
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
