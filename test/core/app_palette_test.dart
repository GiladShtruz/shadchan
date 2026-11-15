import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/profile_palette.dart';

void main() {
  test('the palette has exactly one cream, #F7F4EE, on a white page', () {
    expect(AppColors.page, const Color(0xFFFFFFFF));
    expect(AppColors.cardCream, const Color(0xFFF7F4EE));
    expect(AppColors.background, AppColors.cardCream);
    // The near-white "warm" shade is white now, not a second cream.
    expect(AppColors.surface, AppColors.page);
  });

  test('the light theme draws cards, tiles and secondary grounds in it', () {
    final ThemeData theme = AppTheme.lightTheme();
    expect(theme.scaffoldBackgroundColor, AppColors.page);
    expect(theme.colorScheme.surface, AppColors.cardCream);
    expect(theme.cardColor, AppColors.cardCream);
    expect(theme.colorScheme.surfaceContainerLow, AppColors.cardCream);
    expect(ProfilePalette.surface(theme), AppColors.cardCream);
    expect(ProfilePalette.warmSurface(theme), AppColors.cardCream);
  });

  test('the brand colours are unchanged', () {
    expect(AppColors.primary, const Color(0xFF7F9EAA));
    expect(AppColors.primaryDark, const Color(0xFF5F7F8C));
    expect(AppColors.secondary, const Color(0xFFC1845B));
    expect(AppColors.femaleAccent, const Color(0xFFA9748A));
  });
}
