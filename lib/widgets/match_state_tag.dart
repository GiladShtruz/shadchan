import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';

/// Where a proposal stands, as a small dot and one word in the status's own
/// colour — and nothing drawn around it.
///
/// **No frame and no tinted ground.** A pill behind every status turned a list
/// of proposals into a column of coloured badges; the dot and the word say the
/// same thing at a glance and leave the card calm. The colour comes from
/// [AppColors.matchState], the one place a status is given a colour.
class MatchStateTag extends StatelessWidget {
  const MatchStateTag({super.key, required this.status, this.label});

  final MatchStatus status;

  /// Overrides the word — for a surface that wants the finer stored status
  /// ("בבדיקה") rather than [MatchStatus.stateLabel].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.matchState(
      status,
      dark: theme.brightness == Brightness.dark,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label ?? status.stateLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
