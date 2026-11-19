import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// המאגר שלי and הרעיונות שלי: the page is the app's one light cream, and
/// the cards and tiles on it are white — the other way round from the rest
/// of the app, where the page is white and the cards cream. A list of many
/// cards reads calmer as white sheets on cream than as cream on white.
///
/// Light mode only; dark mode is unchanged. Wraps the screen at its route, so
/// everything under it — the bar, the pinned headers, every card — reads the
/// same two colours from the theme.
class CreamPage extends StatelessWidget {
  const CreamPage({super.key, required this.child});

  final Widget child;

  static ThemeData themeFor(ThemeData base) {
    if (base.brightness == Brightness.dark) return base;
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.cardCream,
      cardColor: AppColors.surface,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.surface,
        surfaceContainerLow: AppColors.surface,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.cardCream,
      ),
      cardTheme: base.cardTheme.copyWith(color: AppColors.surface),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData base = Theme.of(context);
    if (base.brightness == Brightness.dark) return child;
    return Theme(data: themeFor(base), child: child);
  }
}
