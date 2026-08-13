import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The shared building blocks of the home screen.
///
/// The page is deliberately *not* one repeated card: every area has its own
/// shape. The board keeps paper notes on a cream cork surface, recent actions
/// are low wide strips, open ideas are short centred cards, and the people
/// worth a thought are free circles on a soft wave. Heights follow their text;
/// the shared rhythm comes from widths, margins and typography.

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

double homeActivityCardWidth(BuildContext context) =>
    homeIsNarrow(context) ? 174 : HomeConfig.activityCardWidth;

double homeIdeaCardWidth(BuildContext context) {
  final double viewport = MediaQuery.sizeOf(context).width;
  final double inset = homeHorizontalInset(context);
  final double available = viewport - inset * 2 - homeCardGap(context) - 18;
  return (available / 2).clamp(128, HomeConfig.ideaCardWidth);
}

double homeSuggestionWidth(BuildContext context) =>
    homeIsNarrow(context) ? 116 : HomeConfig.suggestionBubbleWidth;

double homeScaled(BuildContext context, double base) {
  final double scale = MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, 1.6);
  return base * scale;
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
      padding: EdgeInsets.fromLTRB(
        homeHorizontalInset(context),
        homeIsNarrow(context) ? 16 : 20,
        homeHorizontalInset(context),
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
            ],
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

/// A horizontal row of cards. The side padding is smaller than a card, so the
/// next one always peeks in from the edge and the row reads as scrollable
/// without needing an arrow.
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(horizontal: homeHorizontalInset(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int index = 0; index < itemCount; index++) ...<Widget>[
            if (index > 0) SizedBox(width: homeCardGap(context)),
            itemBuilder(context, index) ?? const SizedBox.shrink(),
          ],
        ],
      ),
    );
  }
}

/// A quiet cream corkboard. Notes sit directly on its texture; there is no
/// inner frame competing with the paper edges.
class HomeNoteBoard extends StatelessWidget {
  const HomeNoteBoard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: homeHorizontalInset(context)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF55483A)
              : const Color(0xFFE8D4AE),
          borderRadius: BorderRadius.circular(22),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: CustomPaint(
            painter: _CorkPainter(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFFB59B78)
                  : const Color(0xFFC8A978),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _CorkPainter extends CustomPainter {
  const _CorkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dot = Paint()..color = color.withValues(alpha: 0.22);
    for (double y = 7; y < size.height; y += 13) {
      for (double x = 6 + ((y ~/ 13).isOdd ? 5 : 0); x < size.width; x += 17) {
        canvas.drawCircle(Offset(x, y), 0.8, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_CorkPainter oldDelegate) => oldDelegate.color != color;
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();
    final Color paper = _paperFor(theme);

    final double angle = ((_stableHash % 7) - 3) * 0.006;

    return Transform.rotate(
      angle: angle,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: HomeConfig.cardHeight,
          minWidth: homeBoardCardWidth(context),
          maxWidth: homeBoardCardWidth(context),
        ),
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
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned(
                      top: -2,
                      left: 0,
                      right: 0,
                      child: Center(child: _NotePin(seed: _stableHash)),
                    ),
                    Padding(
                      // Keeps the central group clear of the pin and the menu,
                      // without changing where its text is centred.
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        key: const ValueKey<String>('home-board-note-content'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Center(child: leading),
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
                            const SizedBox(height: 4),
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
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Center(child: actions),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small coloured drawing pin holding a note to the cork.
class _NotePin extends StatelessWidget {
  const _NotePin({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    const List<Color> pins = <Color>[
      Color(0xFFB96F78),
      Color(0xFF638EAA),
      Color(0xFFB78A52),
    ];
    final Color pin = pins[seed % pins.length];
    return SizedBox(
      width: 20,
      height: 17,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Positioned(
            top: 8,
            child: Container(
              width: 2,
              height: 8,
              color: pin.withValues(alpha: 0.7),
            ),
          ),
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: pin,
              shape: BoxShape.circle,
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: homeActivityCardWidth(context),
        maxWidth: homeActivityCardWidth(context),
        minHeight: 74,
      ),
      child: Material(
        color: theme.colorScheme.surface,
        // Soft, but no longer a full pill: at two wrapped lines the stadium
        // ends would eat the room the text needs.
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
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
                        // Wraps like the name above it rather than being cut.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          height: 1.15,
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

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: homeIdeaCardWidth(context),
        maxWidth: homeIdeaCardWidth(context),
        minHeight: 106,
      ),
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
              alignment: Alignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        HomeCardCoupleAvatars(
                          personA: personA,
                          personB: personB,
                          radius: 17,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          title,
                          maxLines: 2,
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
      width: homeSuggestionWidth(context),
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
                maxLines: 2,
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
                maxLines: 2,
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
