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

/// The community card on בית — no heading of its own any more.
///
/// **Less text, more air.** The community's weekly target is the centre of
/// it — one sentence, one bar, one figure — and the matchmaker's own activity
/// and the community's sit under it in small type on a single line. The whole
/// card opens the activity screen, which has everything else (the windows,
/// the live lines, the leaderboard).
///
/// **What it does not know it does not say.** Without an account the
/// community half is an invitation; before the server has answered it is a
/// dash, never a zero; and the target is only drawn once the week's read has
/// resolved. A matchmaker hidden from the community sees a sentence saying
/// that hiding is mutual instead of the community's figures.
///
/// The goal is the administrator's `communityGoals/weekly`, edited from the
/// console.
class HomeWeekBlock extends StatefulWidget {
  const HomeWeekBlock({
    super.key,
    required this.onOpen,
    this.watchGoal = CommunityGoalService.watch,
    this.loadTotals = CommunityService.totals,
  });

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
  /// The week's community figures, with the week key they were read under —
  /// kept only while that key is still the current one (a phone left open
  /// over Saturday night must not carry last week into this one).
  CommunityTotals? _week;
  String? _weekKey;
  int _request = 0;
  int _generation = 0;

  WeeklyCommunityGoal? _goal;
  StreamSubscription<WeeklyCommunityGoal?>? _goalSubscription;

  bool _wasSignedIn = false;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWeek();
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
      _loadWeek();
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

  Future<void> _loadWeek() async {
    final String key = CommunityPeriods.keyFor(CommunityPeriod.week);
    final bool rolledOver = _weekKey != null && _weekKey != key;
    if (!rolledOver && (_week?.resolved ?? false)) {
      return;
    }
    final int generation = _generation;
    final int request = ++_request;
    CommunityTotals totals;
    try {
      totals = await widget.loadTotals(
        CommunityPeriod.week,
        forceRefresh: rolledOver,
      );
    } catch (_) {
      return; // Keep the last verified value; an unavailable total is not zero.
    }
    if (!mounted ||
        generation != _generation ||
        request != _request ||
        key != CommunityPeriods.keyFor(CommunityPeriod.week)) {
      return;
    }
    setState(() {
      _week = totals;
      _weekKey = key;
    });
    if (totals.resolved) {
      // The only place this is written. Next week it is what "בשבוע שעבר
      // הגענו ל־X" reads — see [CommunityProfileStore.recordCommunityWeek].
      CommunityProfileStore.recordCommunityWeek(
        weekKey: CommunityPeriods.weekKey(),
        friends: totals.friends,
        ideas: totals.ideas,
        couples: totals.couples,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;
    final CommunityProvider community = context.watch<CommunityProvider>();

    // Firebase resolves the session a moment after launch, so the read fired
    // from `initState` usually came back unresolved; this is the rebuild that
    // follows, and the one after the first publish of the session.
    if (signedIn != _wasSignedIn) {
      _wasSignedIn = signedIn;
      _generation++;
      _week = null;
      _weekKey = null;
      if (signedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _listenGoal();
          _loadWeek();
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
        _week = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadWeek();
        });
      }
    }

    final CommunityTotals? week = _week;
    final CommunityChallenge? challenge =
        signedIn && week != null && week.resolved
        ? CommunityChallenge.build(
            weekKey: CommunityPeriods.weekKey(),
            week: week,
            previousWeek: CommunityProfileStore.previousCommunityWeek,
            goal: _goal,
          )
        : null;
    final Color warm = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    final bool hidden = community.isHidden;
    final CommunityTotals? weekTotals = week;

    // **Less text, more air.** The community's weekly target is the one thing
    // this card is about; the two activity figures sit beside it in small
    // type on one line, and the card opens the activity screen for the rest.
    return HomePaperCard(
      stripe: dark ? AppColors.primaryDarkDm : AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (signedIn && hidden)
              const CommunityHiddenNotice(compact: true)
            else if (challenge != null)
              _ChallengeBar(challenge: challenge)
            else if (!signedIn)
              _JoinFigure(onTap: widget.onOpen),
            const SizedBox(height: 10),
            _FiguresLine(
              mine: community.myPoints(CommunityPeriod.week),
              community: signedIn && !hidden && weekTotals?.resolved == true
                  ? weekTotals!.points
                  : null,
              showCommunity: signedIn && !hidden,
              mineColor: warm,
              communityColor: communityLead(theme),
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

/// The week's shared target, as one bar.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          challenge.headline,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: challenge.progress),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: dark
                    ? AppColors.dividerDm
                    : AppColors.primaryLight,
                valueColor: AlwaysStoppedAnimation<Color>(fill),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          challenge.progressLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: fill,
          ),
        ),
      ],
    );
  }
}

/// "השבוע · שלי 12 · הקהילה 340 ›" — the two activity figures, small, on
/// one line under the target.
class _FiguresLine extends StatelessWidget {
  const _FiguresLine({
    required this.mine,
    required this.community,
    required this.showCommunity,
    required this.mineColor,
    required this.communityColor,
  });

  final int mine;
  final int? community;
  final bool showCommunity;
  final Color mineColor;
  final Color communityColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final TextStyle? base = theme.textTheme.labelSmall;
    final TextStyle? figure = base?.copyWith(fontWeight: FontWeight.w900);
    return Row(
      children: <Widget>[
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              TextSpan(
                style: base,
                children: <InlineSpan>[
                  const TextSpan(text: 'השבוע · הפעילות שלי '),
                  TextSpan(
                    text: CommunityFigure.format(mine),
                    style: figure?.copyWith(color: mineColor),
                  ),
                  if (showCommunity) ...<InlineSpan>[
                    const TextSpan(text: '  ·  הקהילה '),
                    TextSpan(
                      text: community == null
                          ? '—'
                          : CommunityFigure.format(community!),
                      style: figure?.copyWith(color: communityColor),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.muted(dark: dark),
        ),
      ],
    );
  }
}
