import 'package:flutter/widgets.dart';

/// Icons the app draws differently from Material's own.
abstract final class AppIcons {
  /// Material's `help_outline_rounded` without its `matchTextDirection`.
  ///
  /// Material marks the question mark as a directional glyph, so in this RTL
  /// app it was drawn mirrored — a backwards "?". A question mark reads the
  /// same way in Hebrew, so this is the same glyph, never flipped.
  static const IconData help = IconData(0xf7e4, fontFamily: 'MaterialIcons');
}
