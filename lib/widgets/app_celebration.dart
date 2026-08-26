import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The app's way of saying "that was worth doing" — big, in the middle, and
/// gone by itself.
///
/// **This is deliberately not [AppToast], and the two are not interchangeable.**
/// A toast is the right shape for a fact: something saved, something sent,
/// something that failed. A line at the bottom of the screen is exactly as much
/// room as a fact deserves. But a matchmaker who has just put forty friends into
/// an empty database has not been told a fact — they have finished the hardest
/// thing the app ever asks of them, and answering that with a grey strip above
/// the tab bar reads as indifference.
///
/// So this one takes the middle of the screen: a card, a mark, the number in
/// full size, and a ring of confetti thrown out from behind it.
///
/// **It still never has to be dismissed.** That was the one thing right about
/// the dialog this replaced being deleted: being congratulated and then made to
/// press "אישור" turns a moment into a chore. It fades out on its own after
/// [visibleFor], and a tap anywhere takes it away early for somebody who has
/// already read it.
abstract final class AppCelebration {
  /// Longer than a toast's three and a half seconds, because there is more to
  /// look at and because the whole point is to let the moment land.
  static const Duration visibleFor = Duration(seconds: 4);

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Shows [headline] over [message], replacing whatever is on screen.
  ///
  /// [emoji] is the mark at the top of the card. One, large — a card with three
  /// of them is a party invitation.
  static void show(
    BuildContext context, {
    required String headline,
    required String message,
    String emoji = '🎉',
  }) {
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    dismiss();

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => _Celebration(
        headline: headline,
        message: message,
        emoji: emoji,
        onTap: dismiss,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(visibleFor, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _Celebration extends StatefulWidget {
  const _Celebration({
    required this.headline,
    required this.message,
    required this.emoji,
    required this.onTap,
  });

  final String headline;
  final String message;
  final String emoji;
  final VoidCallback onTap;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  /// The card's own arrival: a small overshoot, so it lands rather than
  /// appears.
  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
  );

  /// The confetti, thrown outward behind the card and slightly slower than it,
  /// so the burst reads as caused by the card landing.
  late final Animation<double> _burst = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: FadeTransition(
          opacity: _fade,
          child: ColoredBox(
            // A wash rather than a black barrier: the page underneath should
            // still be recognisable, because what is being celebrated happened
            // on it.
            color: theme.colorScheme.scrim.withValues(alpha: dark ? 0.5 : 0.28),
            child: Center(
              child: ScaleTransition(
                scale: _scale,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _burst,
                          builder: (BuildContext context, _) => CustomPaint(
                            painter: _ConfettiPainter(_burst.value),
                          ),
                        ),
                      ),
                    ),
                    _Card(
                      headline: widget.headline,
                      message: widget.message,
                      emoji: widget.emoji,
                      lead: lead,
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

class _Card extends StatelessWidget {
  const _Card({
    required this.headline,
    required this.message,
    required this.emoji,
    required this.lead,
  });

  final String headline;
  final String message;
  final String emoji;
  final Color lead;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 14),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.15,
              color: dark ? theme.colorScheme.onSurface : lead,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small coloured shapes thrown outward from behind the card.
///
/// Fixed angles and fixed colours rather than random ones: this is drawn on
/// every import, and a burst that is different every time is noise, while the
/// same burst every time becomes the app's own gesture. They fade as they
/// travel, so the card is alone on screen by the time anybody has finished
/// reading it.
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.progress);

  final double progress;

  static const List<Color> _colors = <Color>[
    AppColors.secondary,
    AppColors.primaryDark,
    Color(0xFFD4A34B),
    Color(0xFF8FB6C9),
  ];

  static const int _count = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      return;
    }
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double reach = math.max(size.width, size.height) * 0.62;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _count; i++) {
      final double angle = (i / _count) * 2 * math.pi;
      // Alternating distances, so the ring does not read as a dial.
      final double distance =
          reach * progress * (i.isEven ? 1 : 0.78) + size.width * 0.34;
      final Offset at =
          centre + Offset(math.cos(angle), math.sin(angle)) * distance;
      paint.color = _colors[i % _colors.length].withValues(
        alpha: (1 - progress).clamp(0, 1) * 0.9,
      );
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle + progress * 3);
      final double side = i.isEven ? 7 : 5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: side, height: side * 1.6),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
