import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_goal.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// The community, in four lines, on the home screen.
///
/// **A taste, not the meal.** Everything here is one week: your actions, the
/// community's, how many matchmakers were in it, and how the shared goal is
/// going. No leaderboard, no medals, no all-time totals — those are a tap away
/// on a screen somebody opened *to look at numbers*, and a home screen that
/// leads with a scoreboard has stopped being a workspace.
///
/// It draws immediately from local figures and fills the community column in
/// when the read lands, rather than holding a spinner in the middle of the
/// page: your own number is the one you came for, and it never needs a network.
class HomeCommunityTaster extends StatefulWidget {
  const HomeCommunityTaster({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<HomeCommunityTaster> createState() => _HomeCommunityTasterState();
}

class _HomeCommunityTasterState extends State<HomeCommunityTaster> {
  CommunityTotals? _week;
  ({int target, int actual})? _goal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final CommunityTotals week = await CommunityService.totals(
      CommunityPeriod.week,
    );
    final ({int target, int actual}) goal = await CommunityService.weeklyGoal();
    if (mounted) {
      setState(() {
        _week = week;
        _goal = goal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    final CommunityTotals? week = _week;
    final ({int target, int actual})? goal = _goal;

    // Nothing to show until the community has some life in it. An empty
    // community block is a worse advertisement than no block.
    if (week != null && week.actions == 0) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(20),
        child: CommunityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'הקהילה השבוע',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: CommunitySmallFigure(
                      value: community.myActions(CommunityPeriod.week),
                      label: 'הפעולות שלך',
                    ),
                  ),
                  Expanded(
                    child: CommunitySmallFigure(
                      value: week?.actions ?? 0,
                      label: 'פעולות בקהילה',
                    ),
                  ),
                  Expanded(
                    child: CommunitySmallFigure(
                      value: week?.activeMatchmakers ?? 0,
                      label: 'שדכנים פעילים',
                    ),
                  ),
                ],
              ),
              if (goal != null && goal.target > 0) ...<Widget>[
                const SizedBox(height: 12),
                CommunityMeter(
                  progress: CommunityGoal.progress(
                    actual: goal.actual,
                    target: goal.target,
                  ),
                  over: CommunityGoal.isOverTarget(
                    actual: goal.actual,
                    target: goal.target,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  CommunityGoal.message(
                    actual: goal.actual,
                    target: goal.target,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
