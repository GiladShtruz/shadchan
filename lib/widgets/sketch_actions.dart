import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The three hand-drawn answers a suggested match can be given: "כרטיס מלא",
/// "לפתוח רעיון" and "לא מתאים".
///
/// **Drawn, not picked from an icon font.** The arrow, the heart and the cross
/// are marker drawings (`action_arrow.png`, `action_heart.png`,
/// `action_x.png`), shown exactly as drawn — thick, uneven and in their own
/// colours. They are what makes a list of suggestions feel like somebody
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
    this.compact = false,
  });

  /// Null draws the card action dimmed: there is no card to show.
  final VoidCallback? onFullCard;
  final VoidCallback onOpenIdea;
  final VoidCallback onNotSuitable;

  /// For a card that opens in place: the label says it will close again.
  final bool fullCardExpanded;

  /// A smaller drawing, for a row inside a list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SketchAction(
            asset: 'assets/action_arrow.png',
            label: fullCardExpanded ? 'הסתרת הכרטיס' : 'כרטיס מלא',
            onTap: onFullCard,
            compact: compact,
          ),
        ),
        Expanded(
          child: SketchAction(
            asset: 'assets/action_heart.png',
            label: 'לפתוח רעיון',
            onTap: onOpenIdea,
            compact: compact,
          ),
        ),
        Expanded(
          child: SketchAction(
            asset: 'assets/action_x.png',
            label: 'לא מתאים',
            onTap: onNotSuitable,
            compact: compact,
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
  });

  final String asset;
  final String label;
  final VoidCallback? onTap;
  final bool compact;

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
                  child: Image.asset(
                    asset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
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
}
