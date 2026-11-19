import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/matchmaker_rank.dart';

/// The matchmaker's rank, as one small pill under the name on a profile —
/// "שדכנית פעילה". Nothing below the first rung.
class MatchmakerRankBadge extends StatelessWidget {
  const MatchmakerRankBadge({super.key, required this.ideas, this.gender});

  /// Ideas opened, all time.
  final int ideas;
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final MatchmakerRank? rank = MatchmakerRanks.current(ideas);
    if (rank == null) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color warm = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    return Semantics(
      label: 'דרגה: ${rank.nameFor(gender)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: warm.withValues(alpha: dark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: warm.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.workspace_premium_outlined, size: 16, color: warm),
            const SizedBox(width: 6),
            Text(
              rank.nameFor(gender),
              style: theme.textTheme.labelLarge?.copyWith(
                color: warm,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
