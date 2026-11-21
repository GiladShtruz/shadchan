import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/matchmaker_rank.dart';

/// The matchmaker's rank, as one small pill under the name on a profile —
/// "🔥 שדכנית פעילה+". A tap opens the whole ladder and how it works.
class MatchmakerRankBadge extends StatelessWidget {
  const MatchmakerRankBadge({
    super.key,
    required this.ideas,
    this.gender,
    this.own = false,
  });

  /// The matchmaker's own rank: the ladder then also says how far they are.
  final bool own;

  /// Ideas opened, all time.
  final int ideas;
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color warm = dark
        ? AppColors.secondaryDarkDm
        : context.tokens.ctaAccent;
    final String title = MatchmakerRanks.titleAt(ideas, gender);
    return Semantics(
      button: true,
      label: 'דרגה: ${MatchmakerRanks.nameAt(ideas, gender)}',
      excludeSemantics: true,
      child: Material(
        color: warm.withValues(alpha: dark ? 0.18 : 0.10),
        shape: StadiumBorder(
          side: BorderSide(color: warm.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => MatchmakerRankSheet.show(
            context,
            ideas: ideas,
            gender: gender,
            own: own,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: warm,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline_rounded, size: 14, color: warm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole ladder, with the matchmaker's own rank marked and a line on how
/// it is decided.
abstract final class MatchmakerRankSheet {
  static Future<void> show(
    BuildContext context, {
    required int ideas,
    Gender? gender,
    bool own = true,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialog) {
        final ThemeData theme = Theme.of(dialog);
        final MatchmakerRank mine = MatchmakerRanks.current(ideas);
        final List<MatchmakerRank> ladder = MatchmakerRanks.ladder;
        return AlertDialog(
          title: const Text('סולם הדירוגים'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  MatchmakerRanks.explanation,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < ladder.length; i++)
                  _LadderRow(
                    rank: ladder[i],
                    range: i == ladder.length - 1
                        ? '${ladder[i].ideas}+'
                        : '${ladder[i].ideas}–${ladder[i + 1].ideas - 1}',
                    gender: gender,
                    mine: identical(ladder[i], mine),
                  ),
                if (own) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'פתחת עד היום $ideas רעיונות · '
                    '${MatchmakerRanks.progressLine(ideas, gender)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('סגירה'),
            ),
          ],
        );
      },
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.rank,
    required this.range,
    required this.gender,
    required this.mine,
  });

  final MatchmakerRank rank;
  final String range;
  final Gender? gender;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color warm = theme.brightness == Brightness.dark
        ? AppColors.secondaryDarkDm
        : context.tokens.ctaAccent;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: mine ? warm.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 26, child: Text(rank.emoji)),
          Expanded(
            child: Text(
              rank.nameFor(gender),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: mine ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(range, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
