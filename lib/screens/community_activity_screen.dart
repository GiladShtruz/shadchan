import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/app_menu_sheet.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_goal.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "הפעילות" — your own numbers and the community's, on one screen.
///
/// **Two areas, one period switch each.** Putting them on one page is the whole
/// point: "42 פעולות השבוע" says very little on its own, and a great deal
/// sitting beside "1,842 פעולות השבוע, 63 שדכנים". The comparison is not there
/// to rank anybody — it is there so that a matchmaker working alone on their
/// phone at eleven at night knows they are not the only one doing it.
///
/// The personal side needs no network at all; only the community column waits.
class CommunityActivityScreen extends StatefulWidget {
  const CommunityActivityScreen({super.key});

  @override
  State<CommunityActivityScreen> createState() =>
      _CommunityActivityScreenState();
}

class _CommunityActivityScreenState extends State<CommunityActivityScreen> {
  CommunityPeriod _minePeriod = CommunityPeriod.week;
  CommunityPeriod _communityPeriod = CommunityPeriod.week;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('הפעילות'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: <Widget>[
            _MineCard(
              period: _minePeriod,
              onPeriod: (CommunityPeriod period) =>
                  setState(() => _minePeriod = period),
              actions: community.myActions(_minePeriod),
              counts: community.myCounts,
            ),
            const SizedBox(height: 16),
            const _WeeklyGoalCard(),
            const SizedBox(height: 16),
            Text(
              'הקהילה',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            _CommunityCard(
              period: _communityPeriod,
              onPeriod: (CommunityPeriod period) =>
                  setState(() => _communityPeriod = period),
            ),
            const SizedBox(height: 16),
            const _LeaderboardCard(),
          ],
        ),
      ),
    );
  }
}

// --- Your own side ----------------------------------------------------------

class _MineCard extends StatelessWidget {
  const _MineCard({
    required this.period,
    required this.onPeriod,
    required this.actions,
    required this.counts,
  });

  final CommunityPeriod period;
  final ValueChanged<CommunityPeriod> onPeriod;
  final int actions;
  final CommunityMemberCounts? counts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return CommunityCard(
      title: 'הפעילות שלך',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: period,
            onChanged: onPeriod,
            // Your own numbers include "היום", which the community side does
            // not: a day is a meaningful unit for one person's work and a
            // misleading one for a crowd spread across time zones and habits.
            periods: CommunityPeriod.values,
          ),
          const SizedBox(height: 14),
          CommunityFigure(value: actions, label: 'פעולות ${period.label}'),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: CommunitySmallFigure(
                  value: counts?.ideas ?? 0,
                  label: 'רעיונות שפתחת',
                ),
              ),
              Expanded(
                child: CommunitySmallFigure(
                  value: counts?.couples ?? 0,
                  label: 'זוגות שהתחילו לצאת',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _PersonalRecordLine(),
          const SizedBox(height: 4),
          Text(
            'נספרות הוספת חבר, פתיחת רעיון ועדכון סטטוס של חבר או של רעיון. '
            'עדכון סטטוס נספר פעם אחת ביום לכל חבר או רעיון.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The standing personal weekly best, said quietly.
class _PersonalRecordLine extends StatelessWidget {
  const _PersonalRecordLine();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    final int best = CommunityProfileStore.bestWeek;
    final int thisWeek = community.myActions(CommunityPeriod.week);

    if (best <= 0) {
      return const SizedBox.shrink();
    }

    final bool leading = thisWeek >= best;
    return Row(
      children: <Widget>[
        Icon(
          Icons.emoji_events_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            leading
                ? 'השבוע הזה הוא השיא השבועי שלך — $thisWeek פעולות.'
                : 'השיא השבועי שלך: $best פעולות.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// --- The weekly goal --------------------------------------------------------

class _WeeklyGoalCard extends StatefulWidget {
  const _WeeklyGoalCard();

  @override
  State<_WeeklyGoalCard> createState() => _WeeklyGoalCardState();
}

class _WeeklyGoalCardState extends State<_WeeklyGoalCard> {
  ({int target, int actual})? _goal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ({int target, int actual}) goal = await CommunityService.weeklyGoal();
    if (mounted) {
      setState(() => _goal = goal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({int target, int actual})? goal = _goal;
    if (goal == null || goal.target <= 0) {
      return const SizedBox.shrink();
    }

    final bool over = CommunityGoal.isOverTarget(
      actual: goal.actual,
      target: goal.target,
    );

    return CommunityCard(
      title: 'היעד שלנו לשבוע הקרוב',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '${goal.actual}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.primary
                      : AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'מתוך ${goal.target}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CommunityMeter(
            progress: CommunityGoal.progress(
              actual: goal.actual,
              target: goal.target,
            ),
            over: over,
          ),
          const SizedBox(height: 8),
          Text(
            CommunityGoal.message(actual: goal.actual, target: goal.target),
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              fontWeight: over ? FontWeight.w700 : null,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: shareTheApp,
              icon: const Icon(Icons.ios_share_outlined, size: 18),
              label: const Text('צרפו עוד שדכנים לקהילה'),
            ),
          ),
        ],
      ),
    );
  }
}

// --- The community side -----------------------------------------------------

class _CommunityCard extends StatefulWidget {
  const _CommunityCard({required this.period, required this.onPeriod});

  final CommunityPeriod period;
  final ValueChanged<CommunityPeriod> onPeriod;

  @override
  State<_CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends State<_CommunityCard> {
  final Map<CommunityPeriod, CommunityTotals> _totals =
      <CommunityPeriod, CommunityTotals>{};
  bool _loading = true;

  /// Whether couples are worth showing at all yet — decided once, from the
  /// weekly figure, and applied to all three windows so the row does not
  /// appear and disappear as the period changes.
  bool _showCouples = false;

  @override
  void initState() {
    super.initState();
    _load(widget.period);
  }

  @override
  void didUpdateWidget(covariant _CommunityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      _load(widget.period);
    }
  }

  Future<void> _load(CommunityPeriod period) async {
    if (_totals.containsKey(period)) {
      return;
    }
    setState(() => _loading = true);
    final CommunityTotals totals = await CommunityService.totals(period);
    final CommunityTotals week = period == CommunityPeriod.week
        ? totals
        : await CommunityService.totals(CommunityPeriod.week);
    if (!mounted) {
      return;
    }
    setState(() {
      _totals[period] = totals;
      _showCouples = week.couples >= CommunityService.couplesThreshold;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CommunityTotals? totals = _totals[widget.period];

    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: widget.period,
            onChanged: widget.onPeriod,
            // No "היום" here: a day is a real unit for one person and a noisy
            // one for a crowd.
            periods: const <CommunityPeriod>[
              CommunityPeriod.week,
              CommunityPeriod.month,
              CommunityPeriod.allTime,
            ],
          ),
          const SizedBox(height: 14),
          if (totals == null && _loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...<Widget>[
            CommunityFigure(
              value: totals?.actions ?? 0,
              label: 'פעולות ${widget.period.label}',
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: CommunitySmallFigure(
                    value: totals?.activeMatchmakers ?? 0,
                    label: widget.period == CommunityPeriod.allTime
                        ? 'שדכנים בקהילה'
                        : 'שדכנים פעילים',
                  ),
                ),
                Expanded(
                  child: CommunitySmallFigure(
                    value: totals?.ideas ?? 0,
                    label: 'רעיונות שנפתחו',
                  ),
                ),
                // Held back entirely — not shown as zero — until the community
                // reliably produces couples. A "0 זוגות" line every week for a
                // year is a worse advertisement than no line.
                if (_showCouples)
                  Expanded(
                    child: CommunitySmallFigure(
                      value: totals?.couples ?? 0,
                      label: 'זוגות שהתחילו לצאת',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- The leaderboard --------------------------------------------------------

class _LeaderboardCard extends StatefulWidget {
  const _LeaderboardCard();

  @override
  State<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<_LeaderboardCard> {
  CommunityPeriod _period = CommunityPeriod.week;
  CommunityLeaderboard? _board;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final CommunityProvider community = context.read<CommunityProvider>();
    final CommunityLeaderboard board = await CommunityService.leaderboard(
      _period,
      includeMe: !community.isHidden,
      myActions: community.myActions(_period),
    );
    if (mounted) {
      setState(() {
        _board = board;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    final CommunityLeaderboard? board = _board;

    return CommunityCard(
      title: 'שדכנים מובילים',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: _period,
            onChanged: (CommunityPeriod period) {
              setState(() => _period = period);
              _load();
            },
            periods: CommunityPeriod.values,
          ),
          const SizedBox(height: 12),
          if (_loading && board == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (board == null || board.top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'עוד לא נרשמה פעילות בתקופה הזאת.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...<Widget>[
            for (int i = 0; i < board.top.length; i++)
              CommunityRankRow(place: i + 1, entry: board.top[i]),
            if (community.isHidden) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'הסתרת את עצמך מהדירוג, ולכן גם המיקום שלך לא מוצג.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ] else if (board.myRank != null &&
                board.myRank! > CommunityService.leaderboardSize) ...<Widget>[
              const Divider(height: 22),
              CommunityRankRow(
                place: board.myRank!,
                entry: CommunityRankEntry(
                  uid: 'me',
                  name: 'המיקום שלך',
                  actions: board.myActions,
                ),
                highlighted: true,
              ),
            ],
          ],
          const SizedBox(height: 6),
          const HideFromLeaderboardTile(),
        ],
      ),
    );
  }
}
