import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

abstract final class AppTheme {
  static ThemeData lightTheme() {
    // **The page's two inks, and no third one.** `onSurface` is the blue the
    // app writes every heading, name and figure in, and `onSurfaceVariant` the
    // neutral grey every small explanatory line takes — the same pair
    // [HomeTypography] folds the home screen onto, stated here so the whole
    // app inherits it rather than the one screen that was reworked by hand.
    const ColorScheme colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryLight,
      onSecondaryContainer: AppColors.headingInk,
      surface: AppColors.surface,
      onSurface: AppColors.headingInk,
      error: AppColors.error,
      onError: AppColors.surface,
      outline: AppColors.outline,
    );

    return _buildTheme(
      colorScheme: colorScheme.copyWith(
        surfaceContainerHighest: AppColors.primaryLight,
        surfaceContainerLow: AppColors.secondaryLight,
        onSurfaceVariant: AppColors.mutedInk,
        outlineVariant: AppColors.divider,
      ),
      scaffoldBackgroundColor: AppColors.background,
      // Every bar is the page itself — cream paper, the heading ink — the way
      // the three tabs' own banner is drawn. The wide blue-grey band this used
      // to paint across the top of every pushed screen was the last of the
      // old design.
      appBarBackgroundColor: AppColors.background,
      appBarForegroundColor: AppColors.headingInk,
      cardColor: AppColors.surface,
      chipBackgroundColor: AppColors.primaryLight,
      chipLabelColor: AppColors.primary,
      inputFillColor: AppColors.surface,
      dividerColor: AppColors.divider,
      bottomNavigationBackgroundColor: AppColors.surface,
      bottomNavigationSelectedColor: AppColors.primary,
      bottomNavigationUnselectedColor: AppColors.mutedInk,
      textColor: AppColors.headingInk,
      secondaryTextColor: AppColors.mutedInk,
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
      appBarBackgroundColor: AppColors.backgroundDm,
      appBarForegroundColor: AppColors.headingInkDm,
      cardColor: AppColors.surfaceDm,
      chipBackgroundColor: AppColors.primaryLightDarkDm,
      chipLabelColor: AppColors.primaryDarkDm,
      inputFillColor: AppColors.surfaceDm,
      dividerColor: AppColors.dividerDm,
      bottomNavigationBackgroundColor: AppColors.surfaceDm,
      bottomNavigationSelectedColor: AppColors.primaryDarkDm,
      bottomNavigationUnselectedColor: AppColors.mutedInkDm,
      textColor: AppColors.headingInkDm,
      secondaryTextColor: AppColors.mutedInkDm,
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

    // **Two inks, folded onto the roles once.** Everything that titles, names
    // or counts is written in [textColor] — the brand's blue — and everything
    // that explains, dates or qualifies in [secondaryTextColor], a neutral
    // grey. The split is by *role*, which is the app's stand-in for size:
    // `titleSmall` and above plus `bodyLarge`/`labelLarge` lead, and the
    // smaller `body`/`label` roles are the quiet ones. A widget that means
    // something specific by a colour — a status, a gender, a warning — still
    // says so, and an explicit colour always wins over this fold.
    final TextTheme textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(color: textColor),
      displayMedium: baseTextTheme.displayMedium?.copyWith(color: textColor),
      displaySmall: baseTextTheme.displaySmall?.copyWith(color: textColor),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(color: textColor),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(color: textColor),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(color: textColor),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(color: textColor),
      // No letter spacing: `bodyLarge` is what every text field types in, and
      // Material's 0.5 is a Latin setting that Hebrew never uses — in a field
      // it is what lets a tap put the caret in the middle of a letter.
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0,
        color: textColor,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(color: textColor),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
        color: secondaryTextColor,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(color: secondaryTextColor),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        color: secondaryTextColor,
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
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: appBarForegroundColor,
          fontWeight: FontWeight.w900,
          height: 1.15,
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
        unselectedLabelColor: secondaryTextColor,
        indicatorColor: colorScheme.secondary,
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
