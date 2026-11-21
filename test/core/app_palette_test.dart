import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/profile_palette.dart';

void main() {
  test('the seven palette colours, exactly', () {
    expect(AppColors.darkBlue, const Color(0xFF324754));
    expect(AppColors.blue, const Color(0xFF5F91A3));
    expect(AppColors.teal, const Color(0xFF8FB7C4));
    expect(AppColors.rose, const Color(0xFFA3647E));
    expect(AppColors.copper, const Color(0xFFC98657));
    expect(AppColors.cream, const Color(0xFFFAF7F1));
    expect(AppColors.white, const Color(0xFFFFFFFF));
  });

  test('cream page, white cards', () {
    expect(AppColors.page, AppColors.cream);
    expect(AppColors.background, AppColors.cream);
    expect(AppColors.cardCream, AppColors.white);
    expect(AppColors.surface, AppColors.white);
  });

  test(
    'the light theme draws the page cream and cards, tiles and grounds white',
    () {
      final ThemeData theme = AppTheme.lightTheme();
      expect(theme.scaffoldBackgroundColor, AppColors.cream);
      expect(theme.colorScheme.surface, AppColors.white);
      expect(theme.cardColor, AppColors.white);
      expect(theme.colorScheme.surfaceContainerLow, AppColors.white);
      expect(ProfilePalette.surface(theme), AppColors.white);
      expect(ProfilePalette.canvas(theme), AppColors.cream);
    },
  );

  test('the roles are palette members', () {
    expect(AppColors.primary, AppColors.blue);
    expect(AppColors.secondary, AppColors.copper);
    expect(AppColors.femaleAccent, AppColors.rose);
    expect(AppColors.headingInk, AppColors.darkBlue);
  });
}
