import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The warm, paper-like surface the candidate's own pages are drawn on.
///
/// Kept in one place because the profile, the extended editor and the matches
/// view all have to agree: the app-wide theme paints app bars in cream, so a
/// screen that overrides its background to this canvas also has to state its
/// own title colour, or the title comes out cream on cream.
abstract final class ProfilePalette {
  static Color canvas(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.scaffoldBackgroundColor
        : AppColors.background;
  }

  static Color surface(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : AppColors.surface;
  }

  static Color warmSurface(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : AppColors.secondaryLight;
  }

  static Color text(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : AppColors.onSurface;
  }

  static Color muted(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurfaceVariant
        : AppColors.onSurfaceVariant;
  }

  static Color accent(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.primary
        : AppColors.primaryDark;
  }

  /// The title style for an app bar sitting on [canvas].
  static TextStyle? appBarTitleStyle(ThemeData theme) {
    final TextStyle? style =
        theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
    return style?.copyWith(color: text(theme));
  }
}
