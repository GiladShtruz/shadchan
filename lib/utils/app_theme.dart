import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

abstract final class AppTheme {
  static ThemeData lightTheme() {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.outline,
    );

    return _buildTheme(
      colorScheme: colorScheme.copyWith(
        surfaceContainerHighest: AppColors.primaryLight,
        surfaceContainerLow: AppColors.secondaryLight,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outlineVariant: AppColors.divider,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarBackgroundColor: AppColors.primary,
      appBarForegroundColor: AppColors.onPrimary,
      cardColor: AppColors.surface,
      chipBackgroundColor: AppColors.primaryLight,
      chipLabelColor: AppColors.primary,
      inputFillColor: AppColors.background,
      dividerColor: AppColors.divider,
      bottomNavigationBackgroundColor: AppColors.surface,
      bottomNavigationSelectedColor: AppColors.primary,
      bottomNavigationUnselectedColor: AppColors.onSurfaceVariant,
      textColor: AppColors.onSurface,
      secondaryTextColor: AppColors.onSurfaceVariant,
    );
  }

  static ThemeData darkTheme() {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: AppColors.primaryDarkDm,
      onPrimary: AppColors.onSurface,
      secondary: AppColors.secondaryDarkDm,
      onSecondary: AppColors.onSecondary,
      surface: AppColors.surfaceDm,
      onSurface: AppColors.onSurfaceDm,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.outlineDm,
    );

    return _buildTheme(
      colorScheme: colorScheme.copyWith(
        surfaceContainerHighest: AppColors.primaryLightDarkDm,
        surfaceContainerLow: AppColors.surfaceDm,
        onSurfaceVariant: AppColors.onSurfaceVariantDm,
        outlineVariant: AppColors.dividerDm,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDm,
      appBarBackgroundColor: AppColors.surfaceDm,
      appBarForegroundColor: AppColors.onSurfaceDm,
      cardColor: AppColors.surfaceDm,
      chipBackgroundColor: AppColors.primaryLightDarkDm,
      chipLabelColor: AppColors.primaryDarkDm,
      inputFillColor: AppColors.surfaceDm,
      dividerColor: AppColors.dividerDm,
      bottomNavigationBackgroundColor: AppColors.surfaceDm,
      bottomNavigationSelectedColor: AppColors.primaryDarkDm,
      bottomNavigationUnselectedColor: AppColors.onSurfaceVariantDm,
      textColor: AppColors.onSurfaceDm,
      secondaryTextColor: AppColors.onSurfaceVariantDm,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required Color appBarBackgroundColor,
    required Color appBarForegroundColor,
    required Color cardColor,
    required Color chipBackgroundColor,
    required Color chipLabelColor,
    required Color inputFillColor,
    required Color dividerColor,
    required Color bottomNavigationBackgroundColor,
    required Color bottomNavigationSelectedColor,
    required Color bottomNavigationUnselectedColor,
    required Color textColor,
    required Color secondaryTextColor,
  }) {
    final TextTheme baseTextTheme = Typography.material2021().black.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );

    final TextTheme textTheme = baseTextTheme.copyWith(
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        color: textColor,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
        color: textColor,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 12,
        color: secondaryTextColor,
      ),
    );

    final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outline),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackgroundColor,
        foregroundColor: appBarForegroundColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: appBarForegroundColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 1,
        shape: cardShape,
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: chipBackgroundColor,
        selectedColor: chipBackgroundColor,
        disabledColor: chipBackgroundColor.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: colorScheme.outline),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: chipLabelColor,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
          color: chipLabelColor,
          fontWeight: FontWeight.w600,
        ),
        brightness: colorScheme.brightness,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        shape: CircleBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: bottomNavigationSelectedColor,
        unselectedItemColor: bottomNavigationUnselectedColor,
        backgroundColor: bottomNavigationBackgroundColor,
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
