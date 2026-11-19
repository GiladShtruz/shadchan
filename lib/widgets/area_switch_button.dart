import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The way across between the two areas of one account: "למעבר לאזור האישי"
/// on the matchmaker's home, "למעבר לאזור השדכן" on the personal home.
///
/// **One widget for both, on purpose.** The two are the same act seen from
/// either side, so they are drawn identically — a quiet light-blue link, no
/// frame and no icon — and sit in the same place, the far corner of the
/// greeting's first line (`HomeGreeting.trailing`). Seeing one tells the user
/// where the other one is.
class AreaSwitchButton extends StatelessWidget {
  const AreaSwitchButton({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Smaller and quieter — a small person glyph and a short word in small
  /// type — for the matchmaker's home, where it must stay findable without
  /// weighing on the greeting. The tap target keeps its height.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primary;
    if (compact) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(Icons.person_outline_rounded, size: 14, color: ink),
          label: const Text('אזור אישי', maxLines: 1),
          style: TextButton.styleFrom(
            foregroundColor: ink,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
