import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

abstract final class AppTheme {
  static ThemeData lightTheme() {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryLight,
      onSecondaryContainer: AppColors.onSurface,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      error: AppColors.error,
      onError: AppColors.surface,
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
      inputFillColor: AppColors.surface,
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
      primaryContainer: AppColors.primaryLightDarkDm,
      onPrimaryContainer: AppColors.onSurfaceDm,
      secondary: AppColors.secondaryDarkDm,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryLightDarkDm,
      onSecondaryContainer: AppColors.onSurfaceDm,
      surface: AppColors.surfaceDm,
      onSurface: AppColors.onSurfaceDm,
      error: AppColors.error,
      onError: AppColors.surface,
      outline: AppColors.outlineDm,
    );

    return _buildTheme(
      colorScheme: colorScheme.copyWith(
        surfaceContainerHighest: AppColors.primaryLightDarkDm,
        surfaceContainerLow: AppColors.secondaryLightDarkDm,
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
    const String fontFamily = 'Google Sans';
    final TextTheme baseTextTheme = Typography.material2021().black.apply(
      bodyColor: textColor,
      displayColor: textColor,
      fontFamily: fontFamily,
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
      fontFamily: fontFamily,
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
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const CircleBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      // The four themes below are what make the app's *forgotten* surfaces
      // match the ones that were redesigned by hand. A dialog, a sheet, a
      // snackbar and an expander are each raised from a dozen call sites
      // scattered through the app, and restyling them one at a time is how a
      // codebase ends up with five different corner radii — so the shape is
      // stated once, here, and every caller inherits it whether or not anybody
      // remembered it existed.
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: textColor,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: textColor,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cardColor,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: secondaryTextColor.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.surface,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colorScheme.primary,
        collapsedIconColor: secondaryTextColor,
        textColor: textColor,
        collapsedTextColor: textColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: appBarForegroundColor,
        unselectedLabelColor: appBarForegroundColor.withValues(alpha: 0.7),
        indicatorColor: appBarForegroundColor,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
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
