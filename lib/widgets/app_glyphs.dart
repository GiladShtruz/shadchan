import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "התאמות" in the app's own sign: two cards leaning on each other with a
/// heart where they meet — the launcher icon, drawn as a line icon.
class MatchCardsIcon extends StatelessWidget {
  const MatchCardsIcon({super.key, this.size = 24, this.color});

  final double size;

  /// Defaults to the ambient icon colour, like an [Icon].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color ink = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MatchCardsPainter(ink)),
    );
  }
}

class _MatchCardsPainter extends CustomPainter {
  const _MatchCardsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = color;

    final Size card = Size(s * 0.46, s * 0.62);
    RRect cardAt(Offset centre) => RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: card.width, height: card.height),
      Radius.circular(s * 0.09),
    );

    // Its own layer, so the front card can clear the back card's lines
    // where it covers them — on any ground.
    canvas.saveLayer(Offset.zero & size, Paint());

    // The back card, leaning one way…
    canvas
      ..save()
      ..translate(s * 0.39, s * 0.47)
      ..rotate(-0.26);
    canvas.drawRRect(cardAt(Offset.zero), stroke);
    canvas.restore();

    // …and the front card leaning the other, over it, with the heart.
    canvas
      ..save()
      ..translate(s * 0.6, s * 0.53)
      ..rotate(0.16);
    canvas.drawRRect(cardAt(Offset.zero), Paint()..blendMode = BlendMode.clear);
    canvas.drawRRect(cardAt(Offset.zero), stroke);
    canvas.drawPath(_heartPath(Offset.zero, s * 0.26), fill);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MatchCardsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A light bulb — an idea — with a small heart inside it: "הרעיונות שלי".
///
/// [filled] is the selected state of the bottom bar: the glass filled and the
/// heart cut out of it.
class IdeaBulbIcon extends StatelessWidget {
  const IdeaBulbIcon({
    super.key,
    this.size = 24,
    this.color,
    this.heart = true,
    this.filled = false,
  });

  final double size;
  final Color? color;

  /// The small heart inside the glass. Off, it is a plain, quiet bulb.
  final bool heart;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color ink = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BulbPainter(ink, heart: heart, filled: filled),
      ),
    );
  }
}

class _BulbPainter extends CustomPainter {
  const _BulbPainter(this.color, {required this.heart, required this.filled});

  final Color color;
  final bool heart;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The glass: most of a circle, narrowing into the neck.
    final Offset centre = Offset(s * 0.5, s * 0.4);
    final double r = s * 0.29;
    const double open = 0.62; // half-angle of the gap at the bottom, radians
    final Path glass = Path()
      ..addArc(
        Rect.fromCircle(center: centre, radius: r),
        math.pi / 2 + open,
        2 * math.pi - 2 * open,
      );
    final Offset left =
        centre + Offset(-r * math.sin(open), r * math.cos(open));
    final Offset right =
        centre + Offset(r * math.sin(open), r * math.cos(open));
    final double neckTop = s * 0.72;
    glass
      ..moveTo(left.dx, left.dy)
      ..quadraticBezierTo(s * 0.38, s * 0.66, s * 0.39, neckTop)
      ..moveTo(right.dx, right.dy)
      ..quadraticBezierTo(s * 0.62, s * 0.66, s * 0.61, neckTop);

    if (filled) {
      // A layer of its own, so the heart cut out below clears only the glass.
      canvas.saveLayer(Offset.zero & size, Paint());
      final Path body = Path()
        ..addOval(Rect.fromCircle(center: centre, radius: r))
        ..addRect(Rect.fromLTRB(s * 0.39, centre.dy, s * 0.61, neckTop));
      canvas.drawPath(body, Paint()..color = color);
    }
    canvas.drawPath(glass, stroke);

    // The base: two short lines under the neck.
    canvas
      ..drawLine(Offset(s * 0.39, neckTop), Offset(s * 0.61, neckTop), stroke)
      ..drawLine(
        Offset(s * 0.42, s * 0.85),
        Offset(s * 0.58, s * 0.85),
        stroke,
      );

    if (heart) {
      final Path h = _heartPath(Offset(s * 0.5, s * 0.42), s * 0.26);
      if (filled) {
        // Cut out of the filled glass.
        canvas.drawPath(
          h,
          Paint()
            ..color = color
            ..blendMode = BlendMode.clear,
        );
        canvas.drawPath(
          h,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.04,
        );
      } else {
        canvas.drawPath(h, Paint()..color = color);
      }
    }
    if (filled) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BulbPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.heart != heart ||
      oldDelegate.filled != filled;
}

/// A heart [width] wide, centred on [centre].
Path _heartPath(Offset centre, double width) {
  final double w = width;
  final double cx = centre.dx;
  final double cy = centre.dy;
  return Path()
    ..moveTo(cx, cy + w * 0.42)
    ..cubicTo(
      cx - w * 0.62,
      cy + w * 0.02,
      cx - w * 0.42,
      cy - w * 0.62,
      cx,
      cy - w * 0.22,
    )
    ..cubicTo(
      cx + w * 0.42,
      cy - w * 0.62,
      cx + w * 0.62,
      cy + w * 0.02,
      cx,
      cy + w * 0.42,
    )
    ..close();
}
