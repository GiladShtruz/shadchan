import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';

/// **The palette as theme tokens** — one set for the light theme and one for
/// the dark, read with `context.tokens`.
///
/// A widget names the *role* ("the card", "secondary text", "a woman's
/// accent", "the main action") and the theme answers with the colour for the
/// mode it is in. So the dark theme is never the light palette laid on a dark
/// ground, and changing a colour is one edit here. New widgets use tokens
/// only; [AppColors] holds the raw values the two sets are made of.
///
/// Colour is an accent, never a screen: cards are [surface] whatever they
/// are about, and the category speaks through an icon, a rule, a figure, a
/// badge or bold text in its accent.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.surfaceActive,
    required this.textPrimary,
    required this.textSecondary,
    required this.maleAccent,
    required this.femaleAccent,
    required this.femaleInk,
    required this.ctaAccent,
    required this.ctaInk,
    required this.softHighlight,
    required this.lightAccent,
    required this.outline,
    required this.maleWash,
    required this.femaleWash,
    required this.ctaWash,
    required this.onAccent,
    required this.badge,
    required this.onBadge,
  });

  /// The page.
  final Color background;

  /// An ordinary card, a sheet, the search field.
  final Color surface;

  /// A raised or active card, a selected row, a hovered tile.
  final Color surfaceActive;

  /// Headings and important text.
  final Color textPrimary;

  /// Explanations, dates, hints, placeholders.
  final Color textSecondary;

  /// The blue: men, open ideas, "הוספת חברים", highlights.
  final Color maleAccent;

  /// The bordeaux-mauve: women, dating couples.
  final Color femaleAccent;

  /// [femaleAccent] as text — legible on [surface].
  final Color femaleInk;

  /// The terracotta: CTA, "+", "הוספת רעיון", progress.
  final Color ctaAccent;

  /// [ctaAccent] as text on its own wash.
  final Color ctaInk;

  /// The peach (dark) / sand (light): gentle highlights.
  final Color softHighlight;

  /// The light blue for grounds, tags and rules — the light [AppColors.teal];
  /// at night the blue itself, never the teal on the dark.
  final Color lightAccent;

  /// A card's edge, a field's border, a hairline.
  final Color outline;

  /// Soft grounds behind a mark in each accent.
  final Color maleWash;
  final Color femaleWash;
  final Color ctaWash;

  /// Text and icons drawn on an accent fill.
  final Color onAccent;

  /// The notification badge and the text on it.
  final Color badge;
  final Color onBadge;

  static const AppTokens light = AppTokens(
    background: AppColors.cream,
    surface: AppColors.white,
    surfaceActive: AppColors.primaryLight,
    textPrimary: AppColors.headingInk,
    textSecondary: AppColors.mutedInk,
    maleAccent: AppColors.blue,
    femaleAccent: AppColors.rose,
    femaleInk: AppColors.femaleInk,
    ctaAccent: AppColors.copper,
    ctaInk: AppColors.secondaryInk,
    softHighlight: AppColors.softSand,
    lightAccent: AppColors.teal,
    outline: AppColors.outline,
    maleWash: AppColors.softBlue,
    femaleWash: AppColors.softRose,
    ctaWash: AppColors.secondaryLight,
    onAccent: AppColors.white,
    badge: AppColors.rose,
    onBadge: AppColors.white,
  );

  static const AppTokens dark = AppTokens(
    background: AppColors.backgroundDm,
    surface: AppColors.surfaceDm,
    surfaceActive: AppColors.surfaceActiveDm,
    textPrimary: AppColors.onSurfaceDm,
    textSecondary: AppColors.onSurfaceVariantDm,
    maleAccent: AppColors.primaryDarkDm,
    femaleAccent: AppColors.femaleAccentDm,
    femaleInk: AppColors.femaleInkDm,
    ctaAccent: AppColors.secondaryDarkDm,
    ctaInk: AppColors.secondaryDarkDm,
    softHighlight: AppColors.softHighlightDm,
    lightAccent: AppColors.primaryDarkDm,
    outline: AppColors.outlineDm,
    maleWash: AppColors.surfaceActiveDm,
    femaleWash: Color(0xFF4B505E),
    ctaWash: AppColors.secondaryLightDarkDm,
    onAccent: AppColors.backgroundDm,
    badge: AppColors.femaleAccentDm,
    onBadge: AppColors.onSurfaceDm,
  );

  /// A light-palette colour as this theme draws it: itself in the light
  /// theme, its night twin in the dark (alpha kept). For widgets that are
  /// handed a palette colour as a parameter — a card's rule, a tag's tint —
  /// so a caller that names [AppColors.copper] still gets the terracotta at
  /// night, never the light copper on the dark ground.
  Color adapt(Color color) {
    if (identical(this, light) || background == AppColors.cream) return color;
    final int rgb = color.toARGB32() & 0x00FFFFFF;
    final Color? night = _night[rgb];
    if (night == null) return color;
    return night.withValues(alpha: color.a);
  }

  static final Map<int, Color> _night = <int, Color>{
    _rgb(AppColors.blue): AppColors.primaryDarkDm,
    _rgb(AppColors.teal): AppColors.primaryDarkDm,
    _rgb(AppColors.copper): AppColors.secondaryDarkDm,
    _rgb(AppColors.rose): AppColors.femaleAccentDm,
    _rgb(AppColors.darkBlue): AppColors.onSurfaceDm,
    _rgb(AppColors.mutedInk): AppColors.onSurfaceVariantDm,
    _rgb(AppColors.secondaryInk): AppColors.secondaryDarkDm,
    _rgb(AppColors.femaleInk): AppColors.femaleInkDm,
    _rgb(AppColors.white): AppColors.surfaceDm,
    _rgb(AppColors.cream): AppColors.backgroundDm,
    _rgb(AppColors.primaryLight): AppColors.surfaceActiveDm,
    _rgb(AppColors.softGreen): AppColors.surfaceActiveDm,
    _rgb(AppColors.softRose): const Color(0xFF4B505E),
    _rgb(AppColors.secondaryLight): AppColors.secondaryLightDarkDm,
    _rgb(AppColors.softSand): AppColors.secondaryLightDarkDm,
    _rgb(AppColors.outline): AppColors.outlineDm,
    _rgb(AppColors.divider): AppColors.dividerDm,
  };

  static int _rgb(Color c) => c.toARGB32() & 0x00FFFFFF;

  /// The accent of [gender]: blue for a man (and an unknown), the
  /// bordeaux for a woman.
  Color gender(Gender gender) =>
      gender == Gender.female ? femaleAccent : maleAccent;

  /// [gender] as text.
  Color genderInk(Gender gender) =>
      gender == Gender.female ? femaleInk : maleAccent;

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceActive,
    Color? textPrimary,
    Color? textSecondary,
    Color? maleAccent,
    Color? femaleAccent,
    Color? femaleInk,
    Color? ctaAccent,
    Color? ctaInk,
    Color? softHighlight,
    Color? lightAccent,
    Color? outline,
    Color? maleWash,
    Color? femaleWash,
    Color? ctaWash,
    Color? onAccent,
    Color? badge,
    Color? onBadge,
  }) {
    return AppTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      maleAccent: maleAccent ?? this.maleAccent,
      femaleAccent: femaleAccent ?? this.femaleAccent,
      femaleInk: femaleInk ?? this.femaleInk,
      ctaAccent: ctaAccent ?? this.ctaAccent,
      ctaInk: ctaInk ?? this.ctaInk,
      softHighlight: softHighlight ?? this.softHighlight,
      lightAccent: lightAccent ?? this.lightAccent,
      outline: outline ?? this.outline,
      maleWash: maleWash ?? this.maleWash,
      femaleWash: femaleWash ?? this.femaleWash,
      ctaWash: ctaWash ?? this.ctaWash,
      onAccent: onAccent ?? this.onAccent,
      badge: badge ?? this.badge,
      onBadge: onBadge ?? this.onBadge,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceActive: l(surfaceActive, other.surfaceActive),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      maleAccent: l(maleAccent, other.maleAccent),
      femaleAccent: l(femaleAccent, other.femaleAccent),
      femaleInk: l(femaleInk, other.femaleInk),
      ctaAccent: l(ctaAccent, other.ctaAccent),
      ctaInk: l(ctaInk, other.ctaInk),
      softHighlight: l(softHighlight, other.softHighlight),
      lightAccent: l(lightAccent, other.lightAccent),
      outline: l(outline, other.outline),
      maleWash: l(maleWash, other.maleWash),
      femaleWash: l(femaleWash, other.femaleWash),
      ctaWash: l(ctaWash, other.ctaWash),
      onAccent: l(onAccent, other.onAccent),
      badge: l(badge, other.badge),
      onBadge: l(onBadge, other.onBadge),
    );
  }
}

extension AppTokensContext on BuildContext {
  /// The palette for the theme this widget is drawn in. Falls back to the
  /// set matching the theme's brightness when a theme carries no tokens
  /// (a bare `MaterialApp` in a test).
  AppTokens get tokens {
    final ThemeData theme = Theme.of(this);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);
  }
}
