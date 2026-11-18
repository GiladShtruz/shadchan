import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_goal_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The activity card on בית — "הפעילות שלי" beside "פעילות הקהילה", large,
/// under one window switch (השבוע | החודש | כל הזמנים), and the community's
/// weekly target under them. No heading of its own: the two captions say
/// what it is.
///
/// **The figures are the centre again.** For a few days the target stood in
/// the middle and the two figures were a footnote under it; the figures are
/// what a matchmaker looks for, so they are back as they were — two equal
/// halves, the number large — and the shared target follows, with last week's
/// result beside it in small type.
///
/// **What it does not know it does not say.** Without an account the
/// community half is an invitation; before the server has answered it is a
/// dash, never a zero; and the target is only drawn once the week's read has
/// resolved. A matchmaker hidden from the community sees a sentence saying
/// that hiding is mutual instead of the community's figures.
///
/// The reads go through [CommunityService]'s process cache, shared with the
/// activity screen. The goal is the administrator's `communityGoals/weekly`,
/// edited from the console.
class HomeWeekBlock extends StatefulWidget {
  const HomeWeekBlock({
    super.key,
    required this.onOpen,
    this.watchGoal = CommunityGoalService.watch,
    this.loadTotals = CommunityService.totals,
  });

  static const List<CommunityPeriod> periods = <CommunityPeriod>[
    CommunityPeriod.week,
    CommunityPeriod.month,
    CommunityPeriod.allTime,
  ];

  /// The activity screen — the long form of everything summarised here.
  final VoidCallback onOpen;

  final Stream<WeeklyCommunityGoal?> Function() watchGoal;
  final Future<CommunityTotals> Function(
    CommunityPeriod period, {
    bool forceRefresh,
  })
  loadTotals;

  @override
  State<HomeWeekBlock> createState() => _HomeWeekBlockState();
}

class _HomeWeekBlockState extends State<HomeWeekBlock>
    with WidgetsBindingObserver {
  CommunityPeriod _period = CommunityPeriod.week;

  /// Per window, with the period key each was read under — a resolved window
  /// is kept only while its key is still the current one (a phone left open
  /// over Saturday night must not carry last week into this one).
  final Map<CommunityPeriod, CommunityTotals> _totals =
      <CommunityPeriod, CommunityTotals>{};
  final Map<CommunityPeriod, String> _keys = <CommunityPeriod, String>{};
  final Map<CommunityPeriod, int> _requests = <CommunityPeriod, int>{};
  int _generation = 0;

  WeeklyCommunityGoal? _goal;
  StreamSubscription<WeeklyCommunityGoal?>? _goalSubscription;

  bool _wasSignedIn = false;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    _goalSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAll();
    }
  }

  void _listenGoal() {
    _goalSubscription?.cancel();
    _goalSubscription = widget.watchGoal().listen(
      (WeeklyCommunityGoal? goal) {
        if (mounted) setState(() => _goal = goal);
      },
      // Keep the last known target offline; Firestore reconnects the listener.
      onError: (Object error) => debugPrint('Weekly goal read failed: $error'),
    );
  }

  /// The week (always — the target needs it) and the window on show.
  Future<void> _loadAll() async {
    await Future.wait(<Future<void>>[
      _load(CommunityPeriod.week),
      if (_period != CommunityPeriod.week) _load(_period),
    ]);
    final CommunityTotals? week = _totals[CommunityPeriod.week];
    if (week != null && week.resolved) {
      // The only place this is written. Next week it is what "בשבוע שעבר"
      // reads — see [CommunityProfileStore.recordCommunityWeek].
      CommunityProfileStore.recordCommunityWeek(
        weekKey: CommunityPeriods.weekKey(),
        friends: week.friends,
        ideas: week.ideas,
        couples: week.couples,
      );
    }
  }

  Future<void> _load(CommunityPeriod period) async {
    final String key = CommunityPeriods.keyFor(period);
    final bool rolledOver = _keys[period] != null && _keys[period] != key;
    if (!rolledOver && (_totals[period]?.resolved ?? false)) {
      return;
    }
    final int generation = _generation;
    final int request = (_requests[period] ?? 0) + 1;
    _requests[period] = request;
    CommunityTotals totals;
    try {
      totals = await widget.loadTotals(period, forceRefresh: rolledOver);
    } catch (_) {
      return; // Keep the last verified value; an unavailable total is not zero.
    }
    if (mounted &&
        generation == _generation &&
        _requests[period] == request &&
        key == CommunityPeriods.keyFor(period)) {
      setState(() {
        _totals[period] = totals;
        _keys[period] = key;
      });
    }
  }

  void _select(CommunityPeriod period) {
    if (period == _period) {
      return;
    }
    setState(() => _period = period);
    _load(period);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;
    final CommunityProvider community = context.watch<CommunityProvider>();

    // Firebase resolves the session a moment after launch, so the reads fired
    // from `initState` usually came back unresolved; this is the rebuild that
    // follows, and the one after the first publish of the session.
    if (signedIn != _wasSignedIn) {
      _wasSignedIn = signedIn;
      _generation++;
      _totals.clear();
      _keys.clear();
      if (signedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _listenGoal();
          _loadAll();
        });
      } else {
        _goalSubscription?.cancel();
        _goalSubscription = null;
        _goal = null;
      }
    }
    final int revision = community.publishRevision;
    if (revision != _revision) {
      _revision = revision;
      if (revision > 0) {
        _generation++;
        _totals.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadAll();
        });
      }
    }

    final CommunityTotals? totals = _totals[_period];
    final CommunityTotals? week = _totals[CommunityPeriod.week];
    final bool hidden = community.isHidden;
    final CommunityChallenge? challenge =
        signedIn && !hidden && week != null && week.resolved
        ? CommunityChallenge.build(
            weekKey: CommunityPeriods.weekKey(),
            week: week,
            previousWeek: CommunityProfileStore.previousCommunityWeek,
            goal: _goal,
          )
        : null;
    final Color warm = dark ? AppColors.secondaryDarkDm : AppColors.secondary;

    return HomePaperCard(
      stripe: dark ? AppColors.primaryDarkDm : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: _period,
            onChanged: _select,
            periods: HomeWeekBlock.periods,
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _Figure(
                    label: 'הפעילות שלי',
                    value: community.myPoints(_period),
                    period: _period,
                    color: warm,
                    onTap: widget.onOpen,
                  ),
                ),
                VerticalDivider(
                  width: 20,
                  thickness: 0.6,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: !signedIn
                      ? _JoinFigure(onTap: widget.onOpen)
                      : hidden
                      ? const Center(
                          child: CommunityHiddenNotice(compact: true),
                        )
                      : _Figure(
                          label: 'פעילות הקהילה',
                          value: totals?.resolved == true
                              ? totals!.points
                              : null,
                          period: _period,
                          color: communityLead(theme),
                          onTap: widget.onOpen,
                        ),
                ),
              ],
            ),
          ),
          if (challenge != null) ...<Widget>[
            const SizedBox(height: 14),
            _ChallengeBar(challenge: challenge),
          ],
        ],
      ),
    );
  }
}

/// One of the two figures: a caption over the number, "נקודות" under it.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.period,
    required this.color,
    required this.onTap,
  });

  final String label;

  /// Null when the figure is not known yet — drawn as a dash, never a zero.
  final int? value;
  final CommunityPeriod period;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: FittedBox(
                key: ValueKey<String>('${period.name}:$value'),
                fit: BoxFit.scaleDown,
                child: Text(
                  value == null ? '—' : CommunityFigure.format(value!),
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: color,
                  ),
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value == null ? 'עדיין לא זמין' : 'נקודות',
                maxLines: 1,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The community half before there is an account.
class _JoinFigure extends StatelessWidget {
  const _JoinFigure({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.groups_outlined, size: 20, color: lead),
            const SizedBox(height: 4),
            Text(
              'הצטרפו לקהילת השדכנים',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: lead,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The week's shared target: one sentence, one bar, how far it got — and,
/// compact beside it, what the community reached last week.
class _ChallengeBar extends StatelessWidget {
  const _ChallengeBar({required this.challenge});

  final CommunityChallenge challenge;

  /// The one colour in the app that means "the community did it": the same
  /// green the dating band wears, because reaching a shared target is the same
  /// kind of good news.
  static const Color _done = AppColors.statusDating;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = communityLead(theme);
    final bool won = challenge.reachedTarget || challenge.beatsRecord;
    final Color fill = won ? (dark ? AppColors.statusDatingDm : _done) : lead;
    final String? lastWeek = challenge.lastWeekLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              won ? Icons.emoji_events_outlined : Icons.flag_outlined,
              size: 15,
              color: fill,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                challenge.headline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: challenge.progress),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 9,
                backgroundColor: dark
                    ? AppColors.dividerDm
                    : AppColors.primaryLight,
                valueColor: AlwaysStoppedAnimation<Color>(fill),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        // Both halves give way: at 1.5x text neither may push the other off.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Flexible(
              flex: 4,
              child: Text(
                challenge.progressLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: fill,
                ),
              ),
            ),
            if (lastWeek != null) ...<Widget>[
              const SizedBox(width: 10),
              Flexible(
                flex: 5,
                child: Text(
                  lastWeek,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
