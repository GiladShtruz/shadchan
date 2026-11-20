import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// Cream page, white cards. Since the 2026-11-20 palette this is how the
/// whole app is drawn; the wrapper is kept so the two list screens state it
/// explicitly and stay correct if the app-wide theme ever changes.
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
      scaffoldBackgroundColor: AppColors.page,
      cardColor: AppColors.card,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.card,
        surfaceContainerLow: AppColors.card,
      ),
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: AppColors.page),
      cardTheme: base.cardTheme.copyWith(color: AppColors.card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData base = Theme.of(context);
    if (base.brightness == Brightness.dark) return child;
    return Theme(data: themeFor(base), child: child);
  }
}
