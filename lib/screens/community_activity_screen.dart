import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/community_highlight.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "הפעילות והנתונים" — everything the app counts, on one screen, in the order
/// a matchmaker cares about it.
///
/// **The hierarchy is the design.** הנתונים שלי → הפעילות שלי → פעילות הקהילה →
/// הדירוג. It opens on four real numbers about real people the reader helped,
/// and only then turns them into a score; the community comes after that, and
/// the competitive part comes last. Reversed — leaderboard first — the same
/// figures read as a game with matchmaking as its scoring mechanism, which is
/// the one thing this screen must not feel like.
///
/// The personal half needs no network at all. Only the community half waits —
/// and for a matchmaker who has not connected an account there is no community
/// half at all. Their own two cards are unchanged, and where the totals and the
/// board would be there is one invitation. That is the whole of the gate: their
/// own history is theirs whether or not they ever sign in.
class CommunityActivityScreen extends StatefulWidget {
  const CommunityActivityScreen({super.key});

  /// How many Hebrew months the personal chart reaches back.
  static const int chartMonths = 6;

  @override
  State<CommunityActivityScreen> createState() =>
      _CommunityActivityScreenState();
}

class _CommunityActivityScreenState extends State<CommunityActivityScreen> {
  CommunityPeriod _minePeriod = CommunityPeriod.week;

  @override
  Widget build(BuildContext context) {
    final CommunityProvider community = context.watch<CommunityProvider>();
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<Person> people = personRepository.getAll();
    final List<MatchIdea> matches = matchRepository.getAll();
    final List<MatchStatusEvent> statusEvents = matchRepository
        .getAllStatusEvents();
    final Set<String> excluded = DatingCountExclusions.all();

    final ActivityBreakdown everything = ActivityStats.allTime(
      people: people,
      matches: matches,
      matchStatusEvents: statusEvents,
      excludedFromDating: excluded,
    );

    final List<ActivityBucket> bars = ActivityStats.monthlyBars(
      periods: MonthlyStats.buildPeriods(
        DateTime.now(),
        CommunityActivityScreen.chartMonths,
      ),
      people: people,
      matches: matches,
      matchStatusEvents: statusEvents,
      excludedFromDating: excluded,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('הפעילות שלי'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: <Widget>[
            _MyNumbersCard(breakdown: everything),
            const SizedBox(height: 16),
            _MyActivityCard(
              period: _minePeriod,
              onPeriod: (CommunityPeriod period) =>
                  setState(() => _minePeriod = period),
              points: community.myPoints(_minePeriod),
              bars: bars,
            ),
            const SizedBox(height: 16),
            if (signedIn) ...<Widget>[
              const _CommunityActivityCard(),
              const SizedBox(height: 16),
              const _LeaderboardCard(),
            ] else
              const CommunityCard(
                child: CommunitySignInCard.communityIsForMembers(),
              ),
          ],
        ),
      ),
    );
  }
}

// --- 1. הנתונים שלך ---------------------------------------------------------

/// Four real counts, all-time, and no period switch.
///
/// **These are not points.** "3 חתונות" is a fact about three homes; turning it
/// into 150 anything is the second question, and it is asked in the card below
/// rather than here. There is no week/month switch either: a couple you married
/// last year is still a couple you married, and a matchmaker looking at their
/// own history should not have to choose a window to see it.
class _MyNumbersCard extends StatelessWidget {
  const _MyNumbersCard({required this.breakdown});

  final ActivityBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return CommunityCard(
      title: 'הנתונים שלך',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberTile(
                  value: breakdown.friends,
                  label: 'חברים שהוספת',
                  metric: MonthlyStatMetric.people,
                ),
              ),
              Expanded(
                child: _NumberTile(
                  value: breakdown.ideas,
                  label: 'רעיונות שפתחת',
                  metric: MonthlyStatMetric.ideas,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberTile(
                  value: breakdown.couples,
                  label: 'זוגות שהוצאת לדייט',
                  metric: MonthlyStatMetric.dating,
                ),
              ),
              Expanded(
                child: _NumberTile(
                  value: breakdown.engagements,
                  label: 'חתונות/אירוסין',
                  metric: MonthlyStatMetric.weddings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the four, and the way into the records behind it.
class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.value,
    required this.label,
    required this.metric,
  });

  final int value;
  final String label;

  /// Which list of records this number opens. The drill-downs already exist on
  /// the monthly stats screen and are the honest answer to "which ones?".
  final MonthlyStatMetric metric;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/stats/month/${metric.name}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: CommunitySmallFigure(value: value, label: label),
      ),
    );
  }
}

// --- 2. הפעילות שלך ---------------------------------------------------------

class _MyActivityCard extends StatelessWidget {
  const _MyActivityCard({
    required this.period,
    required this.onPeriod,
    required this.points,
    required this.bars,
  });

  final CommunityPeriod period;
  final ValueChanged<CommunityPeriod> onPeriod;
  final int points;
  final List<ActivityBucket> bars;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return CommunityCard(
      title: 'הפעילות שלך',
      trailing: TextButton(
        onPressed: () => context.push('/stats/month'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('לפי חודשים'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: period,
            onChanged: onPeriod,
            periods: CommunityPeriodTabs.weekMonthAllTime,
          ),
          const SizedBox(height: 14),
          CommunityFigure(
            value: points,
            label: 'נקודות פעילות ${period.label}',
          ),
          const _WeeklyBestLine(),
          const SizedBox(height: 16),
          _ActivityChart(bars: bars),
          const SizedBox(height: 10),
          Text(
            ActivityPoints.shortExplanation,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The personal weekly best, said in one line and never in a window.
///
/// It used to raise a "שיא שבועי חדש!!!" dialog on the launch *after* the week
/// it happened in — an interruption, about something the matchmaker had already
/// forgotten, arriving with no context. Here it costs a line, sits beside the
/// figure it is a record of, and is read by somebody who came to look at their
/// own numbers.
class _WeeklyBestLine extends StatelessWidget {
  const _WeeklyBestLine();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int best = CommunityProfileStore.bestWeek;
    if (best <= 0) {
      return const SizedBox.shrink();
    }

    final bool isThisWeek =
        CommunityProfileStore.bestWeekKey == CommunityPeriods.weekKey();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.trending_up_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isThisWeek
                  ? 'שיא חדש השבוע! $best נקודות'
                  : 'השיא השבועי שלך: $best נקודות',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The personal activity chart: one bar per Hebrew month, oldest first.
///
/// **Only the reader is on it.** A second series for the community would turn
/// a picture of somebody's own year into a picture of how far behind they are,
/// and the community's own figures are two cards further down where they belong.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.bars});

  final List<ActivityBucket> bars;

  static const double _height = 76;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);
    final int peak = bars.fold<int>(
      0,
      (int max, ActivityBucket bucket) =>
          bucket.points > max ? bucket.points : max,
    );

    if (bars.isEmpty || peak == 0) {
      return Text(
        'הגרף יתמלא ברגע שתהיה פעילות ראשונה.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final ActivityBucket bucket in bars)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${bucket.points}',
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: bucket.points == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : lead,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // A hairline for an empty month rather than nothing at all:
                  // a gap in a row of bars reads as missing data.
                  Container(
                    height: (_height * bucket.points / peak).clamp(
                      2.0,
                      _height,
                    ),
                    decoration: BoxDecoration(
                      color: lead.withValues(
                        alpha: bucket.points == 0 ? 0.2 : 0.75,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bucket.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// --- 3. פעילות הקהילה -------------------------------------------------------

class _CommunityActivityCard extends StatefulWidget {
  const _CommunityActivityCard();

  @override
  State<_CommunityActivityCard> createState() => _CommunityActivityCardState();
}

class _CommunityActivityCardState extends State<_CommunityActivityCard> {
  CommunityPeriod _period = CommunityPeriod.week;
  final Map<CommunityPeriod, CommunityTotals> _totals =
      <CommunityPeriod, CommunityTotals>{};
  CommunityTotals? _week;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(_period);
  }

  Future<void> _load(CommunityPeriod period) async {
    if (_totals.containsKey(period)) {
      return;
    }
    setState(() => _loading = true);
    final CommunityTotals totals = await CommunityService.totals(period);
    // The human sentence is always about the week, whichever window is on
    // screen: "השבוע יצאו 6 זוגות" is news, and "מאז ומעולם יצאו 6 זוגות" is a
    // statistic.
    final CommunityTotals week = period == CommunityPeriod.week
        ? totals
        : _week ?? await CommunityService.totals(CommunityPeriod.week);
    if (!mounted) {
      return;
    }
    setState(() {
      _totals[period] = totals;
      _week = week;
      _loading = false;
    });
  }

  void _select(CommunityPeriod period) {
    setState(() => _period = period);
    _load(period);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityTotals? totals = _totals[_period];
    final CommunityTotals? week = _week;
    final String? highlight = week == null
        ? null
        : CommunityHighlight.forWeek(
            week,
            seed: CommunityHighlight.seedFor(DateTime.now()),
          );

    return CommunityCard(
      title: 'פעילות הקהילה',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (highlight != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.volunteer_activism_outlined,
                  size: 16,
                  color: communityLead(theme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    highlight,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          CommunityPeriodTabs(
            selected: _period,
            onChanged: _select,
            periods: CommunityPeriodTabs.weekMonthAllTime,
          ),
          const SizedBox(height: 14),
          if (totals == null && _loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...<Widget>[
            CommunityFigure(
              value: totals?.points ?? 0,
              label: 'נקודות פעילות ${_period.label}',
            ),
            const SizedBox(height: 10),
            // One quiet list rather than six cards competing with each other.
            CommunityStatLine(
              icon: Icons.person_add_alt_1_outlined,
              label: 'חברים שנוספו',
              value: totals?.friends ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.lightbulb_outline_rounded,
              label: 'רעיונות שנפתחו',
              value: totals?.ideas ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.favorite_outline_rounded,
              label: 'זוגות שהתחילו לצאת',
              value: totals?.couples ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.diamond_outlined,
              label: 'אירוסין/חתונות',
              value: totals?.engagements ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.groups_outlined,
              label: 'שדכנים פעילים',
              value: totals?.activeMatchmakers ?? 0,
            ),
          ],
        ],
      ),
    );
  }
}

// --- 4. דירוג השדכנים -------------------------------------------------------

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
      myPoints: community.myPoints(_period),
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
      title: 'דירוג השדכנים',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: _period,
            onChanged: (CommunityPeriod period) {
              setState(() => _period = period);
              _load();
            },
            // The only place "היום" appears. A daily board resets at midnight
            // Israel time and is worth checking; a daily *total* is noise.
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
              _MyPlaceLine(board: board),
            ],
          ],
        ],
      ),
    );
  }
}

/// Where the reader stands when they are not in the ten.
///
/// **A position and a score, and nothing else.** No "עוד 4 פעולות ואתה עוקף
/// את…": a board is competition enough, and a running commentary on the gap
/// turns other matchmakers into obstacles.
class _MyPlaceLine extends StatelessWidget {
  const _MyPlaceLine({required this.board});

  final CommunityLeaderboard board;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = board.activeMatchmakers < (board.myRank ?? 0)
        ? board.myRank!
        : board.activeMatchmakers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'המיקום שלך: ${board.myRank} מתוך $total שדכנים פעילים',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${CommunityFigure.format(board.myPoints)} נקודות פעילות',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
