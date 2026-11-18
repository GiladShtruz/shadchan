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
  const AreaSwitchButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primary;
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
