import 'package:flutter/material.dart';

/// Recolours one of the app's hand-drawn pictures into a palette colour
/// without flattening it.
///
/// The drawings are marker and pencil strokes: a body colour with lighter
/// streaks and darker edges running through it. A plain `srcIn` tint would
/// paint every opaque pixel the same colour and leave a sticker where there
/// was a drawing. This maps the picture's *luminance* instead: a pixel as
/// light as the drawing's body ([bodyLuminance], 0–255) becomes exactly
/// [target], lighter streaks run towards white and darker ones towards black,
/// so the texture survives and only the ink changes.
///
/// [bodyLuminance] is measured once per asset (the median Rec. 709 luminance
/// of its opaque pixels) and passed in by the caller — see [ArtTint].
ColorFilter artTint(Color target, double bodyLuminance) {
  final double l0 = bodyLuminance.clamp(1, 254).toDouble();
  List<double> row(double channel) {
    final double c = channel * 255;
    final double m = (255 - c) / (255 - l0);
    final double offset = c - m * l0;
    return <double>[0.2126 * m, 0.7152 * m, 0.0722 * m, 0, offset];
  }

  return ColorFilter.matrix(<double>[
    ...row(target.r),
    ...row(target.g),
    ...row(target.b),
    0, 0, 0, 1, 0, //
  ]);
}

/// The body luminance of each drawing that is recoloured at draw time.
abstract final class ArtTint {
  static const double addFriends = 73.9;
  static const double addIdea = 99.2;
  static const double actionArrow = 80.6;
  static const double actionHeart = 112.3;
  static const double actionX = 56.9;
}
