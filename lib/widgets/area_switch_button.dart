import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The way across between the two areas of one account: "למעבר לאזור האישי"
/// on the matchmaker's home, "למעבר לאזור השדכן" on the personal home.
///
/// **One widget for both, on purpose.** The two buttons are the same act seen
/// from either side, so they are drawn identically — the same outlined pill,
/// the same swap icon, the same size — and sit in the same place, the far
/// corner of the greeting's first line (`HomeGreeting.trailing`). Seeing one
/// tells the user where the other one is.
class AreaSwitchButton extends StatelessWidget {
  const AreaSwitchButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink.withValues(alpha: 0.45)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
