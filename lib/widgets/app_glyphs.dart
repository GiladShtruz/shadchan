import 'dart:math' as math;
import 'package:shadchan/utils/app_tokens.dart';

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
    // The palette colour as this theme draws it (its night twin at night).
    final Color? color = this.color == null
        ? null
        : context.tokens.adapt(this.color!);
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
    // The palette colour as this theme draws it (its night twin at night).
    final Color? color = this.color == null
        ? null
        : context.tokens.adapt(this.color!);
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

    // The glass: most of a circle, narrowing into the neck. Drawn a little
    // higher and smaller than it once was, to leave room for the screw base's
    // three bands — with only two, the shape read as a generic badge rather
    // than as a bulb.
    final Offset centre = Offset(s * 0.5, s * 0.36);
    final double r = s * 0.27;
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
    final double neckTop = s * 0.65;
    glass
      ..moveTo(left.dx, left.dy)
      ..quadraticBezierTo(s * 0.38, s * 0.6, s * 0.39, neckTop)
      ..moveTo(right.dx, right.dy)
      ..quadraticBezierTo(s * 0.62, s * 0.6, s * 0.61, neckTop);

    if (filled) {
      // A layer of its own, so the heart cut out below clears only the glass.
      canvas.saveLayer(Offset.zero & size, Paint());
      final Path body = Path()
        ..addOval(Rect.fromCircle(center: centre, radius: r))
        ..addRect(Rect.fromLTRB(s * 0.39, centre.dy, s * 0.61, neckTop));
      canvas.drawPath(body, Paint()..color = color);
    }
    canvas.drawPath(glass, stroke);

    // The base: three bands under the neck, each a little shorter than the
    // one above it, in a slightly finer line so they stay apart at icon size.
    final Paint band = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(s * 0.39, neckTop), Offset(s * 0.61, neckTop), stroke)
      ..drawLine(Offset(s * 0.41, s * 0.765), Offset(s * 0.59, s * 0.765), band)
      ..drawLine(
        Offset(s * 0.445, s * 0.88),
        Offset(s * 0.555, s * 0.88),
        band,
      );

    if (heart) {
      final Path h = _heartPath(Offset(s * 0.5, s * 0.38), s * 0.24);
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

/// The app's own small marks — **one family, drawn the same way**: a 24-unit
/// grid, one stroke weight ([AppGlyphIcon.stroke]), round caps and joins,
/// rounded corners, and a single palette colour. They stand where emoji
/// used to (a heart between two names, a rank, a celebration, the type of a
/// chat message), because an emoji is drawn by the phone, in the phone's
/// colours, and every phone draws it differently.
///
/// A new mark is added here — never an emoji in its place.
enum AppGlyph {
  heart,
  heartFilled,
  medal,
  trophy,
  flag,
  spark,
  chat,
  mic,
  photo,
  card,
  couple,
  person,
  people,
  ring,
  check,
  sprout,
  bell,
  key,
  share,
}

/// One [AppGlyph], sized and coloured like an [Icon].
class AppGlyphIcon extends StatelessWidget {
  const AppGlyphIcon(
    this.glyph, {
    super.key,
    this.size = 20,
    this.color,
    this.label,
    this.semanticLabel,
  });

  /// The stroke weight of the whole family, in grid units (of 24).
  static const double stroke = 1.9;

  final AppGlyph glyph;
  final double size;
  final Color? color;

  /// A short figure drawn inside the medal (its rung on the ladder).
  final String? label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color? color = this.color == null
        ? null
        : context.tokens.adapt(this.color!);
    final Color ink = color ?? IconTheme.of(context).color ?? Colors.black;
    final Widget mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(glyph, ink, label)),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: mark)
        : Semantics(
            label: semanticLabel,
            child: ExcludeSemantics(child: mark),
          );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color, this.label);

  final AppGlyph glyph;
  final Color color;
  final String? label;

  @override
  void paint(Canvas canvas, Size size) {
    final double k = size.width / 24;
    canvas.save();
    canvas.scale(k);
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppGlyphIcon.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = color;
    RRect rr(double l, double t, double r, double b, double radius) =>
        RRect.fromLTRBR(l, t, r, b, Radius.circular(radius));

    switch (glyph) {
      case AppGlyph.heart:
        canvas.drawPath(_heartPath(const Offset(12, 13), 17), line);
      case AppGlyph.heartFilled:
        canvas.drawPath(_heartPath(const Offset(12, 13), 17), fill);
      case AppGlyph.medal:
        // Two ribbon tails, then the disc hanging from them.
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 2.5)
            ..lineTo(10.5, 8.5)
            ..moveTo(16.5, 2.5)
            ..lineTo(13.5, 8.5),
          line,
        );
        canvas.drawCircle(const Offset(12, 14.5), 6.5, line);
        final String? text = label;
        if (text != null && text.isNotEmpty) {
          final TextPainter tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: color,
                fontSize: 7.6,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(12 - tp.width / 2, 14.6 - tp.height / 2));
        } else {
          canvas.drawCircle(const Offset(12, 14.5), 2.2, fill);
        }
      case AppGlyph.trophy:
        canvas.drawPath(
          Path()
            ..moveTo(7, 3.5)
            ..lineTo(17, 3.5)
            ..lineTo(17, 8.5)
            ..cubicTo(17, 12, 14.5, 14, 12, 14)
            ..cubicTo(9.5, 14, 7, 12, 7, 8.5)
            ..close()
            ..moveTo(7, 5.5)
            ..cubicTo(3.5, 5.5, 3.5, 10.5, 7.6, 10.8)
            ..moveTo(17, 5.5)
            ..cubicTo(20.5, 5.5, 20.5, 10.5, 16.4, 10.8)
            ..moveTo(12, 14)
            ..lineTo(12, 17.5)
            ..moveTo(8, 20.5)
            ..lineTo(16, 20.5)
            ..moveTo(9, 20.5)
            ..lineTo(9.5, 17.5)
            ..lineTo(14.5, 17.5)
            ..lineTo(15, 20.5),
          line,
        );
      case AppGlyph.flag:
        canvas.drawPath(
          Path()
            ..moveTo(5.5, 21)
            ..lineTo(5.5, 3.5)
            ..moveTo(5.5, 4.5)
            ..cubicTo(9, 2.5, 12, 6.5, 18.5, 4.5)
            ..lineTo(18.5, 13)
            ..cubicTo(12, 15, 9, 11, 5.5, 13),
          line,
        );
      case AppGlyph.spark:
        final Path star = Path()
          ..moveTo(11, 3)
          ..quadraticBezierTo(11.8, 9.2, 18, 10.5)
          ..quadraticBezierTo(11.8, 11.8, 11, 18)
          ..quadraticBezierTo(10.2, 11.8, 4, 10.5)
          ..quadraticBezierTo(10.2, 9.2, 11, 3)
          ..close();
        canvas.drawPath(star, line);
        canvas.drawCircle(const Offset(18.5, 18.5), 1.5, fill);
        canvas.drawCircle(const Offset(19.5, 4.5), 1.1, fill);
      case AppGlyph.chat:
        canvas.drawPath(
          Path()
            ..addRRect(rr(3.5, 4.5, 20.5, 16.5, 5))
            ..moveTo(8, 16.5)
            ..lineTo(6.5, 20.5)
            ..lineTo(12, 16.5),
          line,
        );
      case AppGlyph.mic:
        canvas.drawRRect(rr(9, 3, 15, 14, 3), line);
        canvas.drawPath(
          Path()
            ..moveTo(5.8, 11)
            ..cubicTo(5.8, 19.2, 18.2, 19.2, 18.2, 11)
            ..moveTo(12, 17.2)
            ..lineTo(12, 21),
          line,
        );
      case AppGlyph.photo:
        canvas.drawRRect(rr(3.5, 5, 20.5, 19, 3.5), line);
        canvas.drawPath(
          Path()
            ..moveTo(6.5, 16)
            ..lineTo(10.5, 11.5)
            ..lineTo(13.5, 14.5)
            ..lineTo(15.5, 12.5)
            ..lineTo(18, 16),
          line,
        );
        canvas.drawCircle(const Offset(15.5, 8.8), 1.4, fill);
      case AppGlyph.card:
        canvas.drawRRect(rr(3, 5, 21, 19, 3.5), line);
        canvas.drawCircle(const Offset(8.8, 10.8), 2, line);
        canvas.drawPath(
          Path()
            ..moveTo(5.8, 16)
            ..quadraticBezierTo(8.8, 13.4, 11.8, 16)
            ..moveTo(14, 10)
            ..lineTo(18, 10)
            ..moveTo(14, 13.5)
            ..lineTo(17, 13.5),
          line,
        );
      case AppGlyph.couple:
        canvas.drawCircle(const Offset(8, 8), 2.8, line);
        canvas.drawCircle(const Offset(16, 8), 2.8, line);
        canvas.drawPath(
          Path()
            ..moveTo(3, 19.5)
            ..quadraticBezierTo(3.5, 13.5, 8, 13.5)
            ..quadraticBezierTo(10.5, 13.5, 12, 15.2)
            ..quadraticBezierTo(13.5, 13.5, 16, 13.5)
            ..quadraticBezierTo(20.5, 13.5, 21, 19.5),
          line,
        );
      case AppGlyph.person:
        canvas.drawCircle(const Offset(12, 8), 3.6, line);
        canvas.drawPath(
          Path()
            ..moveTo(5, 20.5)
            ..quadraticBezierTo(5.5, 14, 12, 14)
            ..quadraticBezierTo(18.5, 14, 19, 20.5),
          line,
        );
      case AppGlyph.people:
        canvas.drawCircle(const Offset(10, 8.5), 3.2, line);
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 20)
            ..quadraticBezierTo(4, 14, 10, 14)
            ..quadraticBezierTo(16, 14, 16.5, 20)
            ..moveTo(15.5, 5.6)
            ..quadraticBezierTo(18.6, 6.4, 18, 10)
            ..quadraticBezierTo(17.6, 11.6, 16.2, 12)
            ..moveTo(18.2, 14.4)
            ..quadraticBezierTo(20.6, 15.6, 21, 19.5),
          line,
        );
      case AppGlyph.ring:
        canvas.drawCircle(const Offset(12, 14.5), 6, line);
        canvas.drawPath(
          Path()
            ..moveTo(9.5, 5.5)
            ..lineTo(12, 3)
            ..lineTo(14.5, 5.5)
            ..lineTo(12, 8.3)
            ..close(),
          line,
        );
      case AppGlyph.check:
        canvas.drawPath(
          Path()
            ..moveTo(5, 12.5)
            ..lineTo(10, 17.5)
            ..lineTo(19, 7),
          line,
        );
      case AppGlyph.sprout:
        canvas.drawPath(
          Path()
            ..moveTo(12, 21)
            ..lineTo(12, 11)
            ..moveTo(12, 13)
            ..cubicTo(12, 8, 8, 6, 4.5, 6.5)
            ..cubicTo(4.5, 10.5, 7.5, 13, 12, 13)
            ..moveTo(12, 11)
            ..cubicTo(12, 6, 15.5, 3.5, 19.5, 4)
            ..cubicTo(19.5, 8, 16.5, 11, 12, 11),
          line,
        );
      case AppGlyph.bell:
        canvas.drawPath(
          Path()
            ..moveTo(6, 17)
            ..lineTo(6, 11)
            ..cubicTo(6, 7.3, 8.6, 4.8, 12, 4.8)
            ..cubicTo(15.4, 4.8, 18, 7.3, 18, 11)
            ..lineTo(18, 17)
            ..moveTo(4.5, 17)
            ..lineTo(19.5, 17)
            ..moveTo(10, 20.3)
            ..lineTo(14, 20.3),
          line,
        );
      case AppGlyph.key:
        canvas.drawCircle(const Offset(8, 12), 4, line);
        canvas.drawPath(
          Path()
            ..moveTo(12, 12)
            ..lineTo(20.5, 12)
            ..moveTo(17.5, 12)
            ..lineTo(17.5, 15.5)
            ..moveTo(20.5, 12)
            ..lineTo(20.5, 14.5),
          line,
        );
      case AppGlyph.share:
        canvas.drawCircle(const Offset(17.5, 5.5), 2.5, line);
        canvas.drawCircle(const Offset(6.5, 12), 2.5, line);
        canvas.drawCircle(const Offset(17.5, 18.5), 2.5, line);
        canvas.drawPath(
          Path()
            ..moveTo(8.7, 10.7)
            ..lineTo(15.3, 6.8)
            ..moveTo(8.7, 13.3)
            ..lineTo(15.3, 17.2),
          line,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.label != label;
}

/// The matchmaker's rung on the ladder: the medal with its number in it —
/// one mark for every rank, in the rank's own place.
class RankMark extends StatelessWidget {
  const RankMark({super.key, required this.level, this.size = 20, this.color});

  /// 1-based rung.
  final int level;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      AppGlyphIcon(AppGlyph.medal, size: size, color: color, label: '$level');
}

/// A line of text where [AppGlyphText.heart] stands for the app's own small
/// heart — "אבי ♥ הודיה" is stored and compared as text, and drawn with the
/// heart glyph between the names instead of the phone's emoji.
class AppGlyphText extends StatelessWidget {
  const AppGlyphText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textAlign,
    this.heartColor,
  });

  /// The mark a string carries where a heart is drawn.
  static const String heart = '\u2665';

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextAlign? textAlign;
  final Color? heartColor;

  @override
  Widget build(BuildContext context) {
    if (!text.contains(heart)) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign,
      );
    }
    final TextStyle base = DefaultTextStyle.of(context).style.merge(style);
    final double size = (base.fontSize ?? 14) * 0.82;
    final List<String> parts = text.split(heart);
    return Semantics(
      label: parts.map((String p) => p.trim()).join(' ו'),
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              for (int i = 0; i < parts.length; i++) ...<InlineSpan>[
                TextSpan(text: parts[i]),
                if (i < parts.length - 1)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: AppGlyphIcon(
                      AppGlyph.heartFilled,
                      size: size,
                      color: heartColor ?? context.tokens.femaleAccent,
                    ),
                  ),
              ],
            ],
          ),
          style: style,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
          textAlign: textAlign,
        ),
      ),
    );
  }
}

/// A profile photo, large: black ground, pinch to zoom, back or the ✕ to
/// close. Opened by a tap on a matchmaker's face on their profile.
abstract final class ProfilePhotoViewer {
  static Future<void> open(BuildContext context, String url, {String? name}) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (BuildContext context, _, _) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: name == null ? null : Text(name),
            leading: IconButton(
              tooltip: 'סגירה',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder:
                    (BuildContext context, Widget child, ImageChunkEvent? p) =>
                        p == null
                        ? child
                        : const CircularProgressIndicator(color: Colors.white),
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }
}
