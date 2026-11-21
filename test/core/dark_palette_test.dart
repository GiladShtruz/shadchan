import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/app_tokens.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance(), lb = b.computeLuminance();
  final double hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const AppTokens d = AppTokens.dark;

  test('the night palette is exactly the one asked for', () {
    expect(d.background, const Color(0xFF1B2C35));
    expect(d.surface, const Color(0xFF304954));
    expect(d.surfaceActive, const Color(0xFF3F606D));
    expect(d.textPrimary, const Color(0xFFF5F1E8));
    expect(d.textSecondary, const Color(0xFFB8C8CD));
    expect(d.maleAccent, const Color(0xFF79B4C5));
    expect(d.femaleAccent, const Color(0xFFB86A87));
    expect(d.ctaAccent, const Color(0xFFD49262));
    expect(d.softHighlight, const Color(0xFFE8B78F));
    expect(d.badge, const Color(0xFFB86A87));
  });

  test('text reads on every dark ground', () {
    expect(_contrast(d.textPrimary, d.background), greaterThan(7));
    for (final Color ground in <Color>[d.surface, d.surfaceActive]) {
      expect(_contrast(d.textPrimary, ground), greaterThan(4.5));
    }
    expect(_contrast(d.textSecondary, d.background), greaterThan(4.5));
    expect(_contrast(d.textSecondary, d.surface), greaterThan(4.5));
    // Accents as text and marks on a card.
    expect(_contrast(d.maleAccent, d.surface), greaterThan(3));
    expect(_contrast(d.ctaAccent, d.surface), greaterThan(3));
    expect(_contrast(d.femaleInk, d.surface), greaterThan(3.5));
    // Labels on an accent fill (buttons, the "+").
    expect(_contrast(d.onAccent, d.ctaAccent), greaterThan(4.5));
    expect(_contrast(d.onAccent, d.maleAccent), greaterThan(4.5));
    // The badge's number.
    expect(_contrast(d.onBadge, d.badge), greaterThan(3));
  });

  test('the light theme is untouched by the tokens', () {
    const AppTokens l = AppTokens.light;
    expect(l.background, AppColors.cream);
    expect(l.surface, AppColors.white);
    expect(l.maleAccent, AppColors.blue);
    expect(l.ctaAccent, AppColors.copper);
    expect(l.femaleAccent, AppColors.rose);
    for (final Color c in <Color>[
      AppColors.blue,
      AppColors.copper,
      AppColors.teal,
      AppColors.mutedInk,
    ]) {
      expect(l.adapt(c), c);
    }
  });

  test('a light palette colour is never drawn as itself at night', () {
    expect(d.adapt(AppColors.teal), AppColors.primaryDarkDm);
    expect(d.adapt(AppColors.copper), AppColors.secondaryDarkDm);
    expect(d.adapt(AppColors.rose), AppColors.femaleAccentDm);
    expect(d.adapt(AppColors.darkBlue), AppColors.onSurfaceDm);
    expect(d.adapt(AppColors.white), AppColors.surfaceDm);
    // Alpha is kept.
    expect(
      d.adapt(AppColors.copper.withValues(alpha: 0.3)).a,
      closeTo(0.3, 0.01),
    );
  });

  test('both themes carry their tokens', () {
    expect(AppTheme.darkTheme().extension<AppTokens>(), same(AppTokens.dark));
    expect(AppTheme.lightTheme().extension<AppTokens>(), same(AppTokens.light));
    expect(AppTheme.darkTheme().scaffoldBackgroundColor, d.background);
    expect(AppTheme.darkTheme().colorScheme.surface, d.surface);
    expect(AppTheme.darkTheme().badgeTheme.backgroundColor, d.badge);
  });
}
