import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/art_tint.dart';

/// The three hand-drawn answers a suggested match can be given: "כרטיס מלא",
/// "לפתוח רעיון" and "לא מתאים".
///
/// **Drawn, not picked from an icon font.** The arrow, the heart and the cross
/// are marker drawings (`action_arrow.png`, `action_heart.png`,
/// `action_x.png`), shown with their strokes as drawn — thick and uneven — but
/// inked in the palette: the heart in the rose, the cross in the copper and
/// the card in the blue. See [artTint]. They are what makes a list of suggestions feel like somebody
/// thinking on paper rather than a dating app's swipe buttons.
///
/// Read in RTL the row is: the card (right), the heart in the middle — the one
/// answer that moves anything forward — and the cross at the far end.
class SketchActionBar extends StatelessWidget {
  const SketchActionBar({
    super.key,
    required this.onFullCard,
    required this.onOpenIdea,
    required this.onNotSuitable,
    this.fullCardExpanded = false,
    this.fullCardLabel,
    this.compact = false,
    this.restoresInstead = false,
  });

  /// For a candidate already marked "לא מתאים": the third answer takes them
  /// back ("החזרה לרשימה", the arrow) instead of turning them down again.
  final bool restoresInstead;

  /// Null draws the card action dimmed: there is no card to show.
  final VoidCallback? onFullCard;
  final VoidCallback onOpenIdea;
  final VoidCallback onNotSuitable;

  /// For a card that opens in place: the label says it will close again.
  final bool fullCardExpanded;

  /// What the first drawing is called, when it is not the full card —
  /// "השוואת כרטיסים" for a pair, "לבקשת פרטים בוואטסאפ" for a friend with no
  /// card yet.
  final String? fullCardLabel;

  /// A smaller drawing, for a row inside a list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        Expanded(
          child: SketchAction(
            asset: 'assets/action_arrow.png',
            label:
                fullCardLabel ??
                (fullCardExpanded ? 'הסתרת הכרטיס' : 'כרטיס מלא'),
            onTap: onFullCard,
            compact: compact,
            tint: artTint(
              dark ? AppColors.primaryDarkDm : AppColors.primaryDark,
              ArtTint.actionArrow,
            ),
          ),
        ),
        Expanded(
          child: SketchAction(
            asset: 'assets/action_heart.png',
            label: 'לפתוח רעיון',
            onTap: onOpenIdea,
            compact: compact,
            tint: artTint(
              dark ? AppColors.femaleAccentDm : AppColors.femaleAccent,
              ArtTint.actionHeart,
            ),
          ),
        ),
        Expanded(
          child: restoresInstead
              ? SketchAction(
                  asset: 'assets/action_arrow.png',
                  label: 'החזרה לרשימה',
                  onTap: onNotSuitable,
                  compact: compact,
                  tint: artTint(
                    dark ? AppColors.secondaryDarkDm : AppColors.secondary,
                    ArtTint.actionArrow,
                  ),
                )
              : SketchAction(
                  asset: 'assets/action_x.png',
                  label: 'לא מתאים',
                  onTap: onNotSuitable,
                  compact: compact,
                  tint: artTint(
                    dark ? AppColors.secondaryDarkDm : AppColors.secondary,
                    ArtTint.actionX,
                  ),
                ),
        ),
      ],
    );
  }
}

/// One drawing with its word under it, as a single tap target.
class SketchAction extends StatelessWidget {
  const SketchAction({
    super.key,
    required this.asset,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.tint,
  });

  final String asset;
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  /// Recolours the drawing into a palette colour; null shows it as drawn.
  final ColorFilter? tint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: compact ? 26 : 34,
                  child: _tinted(
                    Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading(dark: dark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tinted(Widget image) {
    final ColorFilter? filter = tint;
    return filter == null
        ? image
        : ColorFiltered(colorFilter: filter, child: image);
  }
}
