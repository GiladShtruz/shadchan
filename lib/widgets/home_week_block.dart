import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/mazel_tov_sheet.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_engagements_service.dart';
import 'package:shadchan/services/community_goal_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/mazel_tov_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_highlight.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/community_widgets.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "השבוע בשדכן" — the matchmaker's own activity, the community's, the
/// week's shared target and one live line, in one compact card.
///
/// **Three blocks became one.** "הפעילות שלי והקהילה", "מה קורה בקהילה
/// עכשיו" and the weekly target used to stand one under the other, three
/// cards about the same subject on a page whose job is to say what to do
/// next. They share one window switch now (השבוע | החודש | כל הזמנים) — the
/// two figures and the live line follow it; the weekly target is always the
/// week's, and says so.
///
/// **What it does not know it does not say.** Without an account the
/// community half is an invitation; before the server has answered it is a
/// dash, never a zero; and the target and the live line are only drawn once
/// the week's read has resolved.
///
/// The reads (today, week, month, all time) go through [CommunityService]'s
/// process cache, shared with the activity screen. The goal is the
/// administrator's `communityGoals/weekly`, edited from the console.
class HomeWeekBlock extends StatefulWidget {
  const HomeWeekBlock({
    super.key,
    required this.onOpen,
    this.watchGoal = CommunityGoalService.watch,
    this.loadTotals = CommunityService.totals,
    this.loadNamedEngagements = CommunityEngagementsService.namedThisWeek,
  });

  static const String title = 'השבוע בשדכן';

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
  final Future<List<CommunityEngagement>> Function() loadNamedEngagements;

  @override
  State<HomeWeekBlock> createState() => _HomeWeekBlockState();
}

class _HomeWeekBlockState extends State<HomeWeekBlock>
    with WidgetsBindingObserver {
  /// Long enough to read a short sentence, short enough that a glance at the
  /// page catches it moving.
  static const Duration _dwell = Duration(seconds: 5);

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
  List<CommunityEngagement> _named = const <CommunityEngagement>[];
  final Set<String> _congratulated = <String>{};

  Timer? _timer;
  int _index = 0;

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
    _timer?.cancel();
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

  Future<void> _loadAll() async {
    await Future.wait(<Future<void>>[
      _load(CommunityPeriod.day),
      for (final CommunityPeriod p in HomeWeekBlock.periods) _load(p),
    ]);
    final CommunityTotals? week = _totals[CommunityPeriod.week];
    if (week != null && week.resolved) {
      // The only place this is written. Next week it is what "בשבוע שעבר
      // הגענו ל־X" reads — see [CommunityProfileStore.recordCommunityWeek].
      CommunityProfileStore.recordCommunityWeek(
        weekKey: CommunityPeriods.weekKey(),
        friends: week.friends,
        ideas: week.ideas,
        couples: week.couples,
      );
      if (week.engagements > 0) {
        final int generation = _generation;
        List<CommunityEngagement> named;
        try {
          named = await widget.loadNamedEngagements();
        } catch (_) {
          named = const <CommunityEngagement>[];
        }
        if (mounted && generation == _generation) {
          setState(() => _named = named);
        }
      }
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
    setState(() {
      _period = period;
      _index = 0;
    });
    _load(period);
  }

  void _syncTimer(int lineCount) {
    if (lineCount < 2) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_dwell, (_) {
      if (mounted) setState(() => _index++);
    });
  }

  List<CommunityPulseLine> _lines() {
    final CommunityTotals? totals = _totals[_period];
    if (totals == null || !totals.resolved) {
      return const <CommunityPulseLine>[];
    }
    if (_period == CommunityPeriod.week) {
      final CommunityTotals day = _totals[CommunityPeriod.day] ?? totals;
      return <CommunityPulseLine>[
        ...CommunityHighlight.pulseLines(
          day: day.resolved ? day : CommunityTotals.empty,
          week: totals,
          namedEngagements: _named,
        ),
        if (totals.newMatchmakers > 0)
          CommunityPulseLine(
            text: totals.newMatchmakers == 1
                ? 'שדכן חדש הצטרף לקהילה השבוע'
                : '${totals.newMatchmakers} שדכנים הצטרפו השבוע',
          ),
      ];
    }
    return CommunityHighlight.periodLines(
      totals,
      allTime: _period == CommunityPeriod.allTime,
    );
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
        _named = const <CommunityEngagement>[];
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
    final List<CommunityPulseLine> lines = signedIn
        ? _lines()
        : const <CommunityPulseLine>[];
    _syncTimer(lines.length);
    final CommunityPulseLine? line = lines.isEmpty
        ? null
        : lines[_index % lines.length];
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

    return HomePaperCard(
      stripe: dark ? AppColors.primaryDarkDm : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: <Widget>[
                _LivePulse(beat: _index),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    HomeWeekBlock.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.muted(dark: dark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          CommunityPeriodTabs(
            selected: _period,
            onChanged: _select,
            periods: HomeWeekBlock.periods,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 10),
              Expanded(
                child: signedIn
                    ? _Figure(
                        label: 'פעילות הקהילה',
                        value: totals?.resolved == true ? totals!.points : null,
                        period: _period,
                        color: communityLead(theme),
                        onTap: widget.onOpen,
                      )
                    : _JoinFigure(onTap: widget.onOpen),
              ),
            ],
          ),
          if (line != null) ...<Widget>[
            const SizedBox(height: 10),
            _RotatingLine(
              line: line,
              onTap: line.isActionable ? () => _congratulate(line) : null,
              sent:
                  line.engagement != null &&
                  _congratulated.contains(line.engagement!.id),
            ),
          ],
          if (challenge != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'היעד השבועי של הקהילה',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            _ChallengeBar(challenge: challenge),
          ],
          const SizedBox(height: 4),
          const ActivityScoringLink(),
        ],
      ),
    );
  }

  /// "שלחו מזל טוב" — four ready-made brachot and a field, delivered into the
  /// other matchmaker's journal for that couple.
  Future<void> _congratulate(CommunityPulseLine line) async {
    final CommunityEngagement engagement = line.engagement!;
    final OverlayState? notices = AppNotice.capture(context);
    final String myName =
        context.read<UserProfileProvider>().communityDisplayName ?? '';
    final String? text = await MazelTovSheet.show(context);
    if (text == null || !mounted) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    final bool ok = await MazelTovService.send(
      toUid: engagement.authorUid,
      matchId: engagement.matchId,
      text: text,
      fromName: CommunityProfileStore.isHidden ? '' : myName,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (ok) _congratulated.add(engagement.id);
    });
    AppNotice.showOn(
      notices,
      ok
          ? 'הברכה נשלחה. תודה!'
          : 'לא הצלחנו לשלוח כרגע. כדאי לנסות שוב כשיש חיבור לאינטרנט.',
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
                  style: theme.textTheme.titleLarge?.copyWith(
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

/// The one sentence, changing.
///
/// Fades and rises a few pixels rather than sliding a whole line width: this is
/// a small area on a calm page, and a sentence that flies in from the side
/// turns a quiet banner into a ticker tape.
class _RotatingLine extends StatelessWidget {
  const _RotatingLine({required this.line, this.onTap, this.sent = false});

  final CommunityPulseLine line;

  /// Present only on a line that can be acted on — today that is one thing, a
  /// bracha to a matchmaker whose couple got engaged.
  final VoidCallback? onTap;

  /// Whether that bracha has already gone. The line stays in the rotation and
  /// stops offering the action, which is the honest thing for it to say.
  final bool sent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);
    final bool actionable = onTap != null && !sent;

    final Widget row = Row(
      key: ValueKey<String>('${line.text}|$sent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: lead),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            sent ? '${line.text} — הברכה נשלחה 💛' : line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
              // Only a line that does something wears the colour that says so.
              color: actionable ? lead : null,
              decoration: actionable ? TextDecoration.underline : null,
              decorationColor: actionable ? lead.withValues(alpha: 0.5) : null,
            ),
          ),
        ),
        if (actionable) ...<Widget>[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.favorite_rounded, size: 15, color: lead),
          ),
        ],
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      // The line's own tap has to beat the card's, and an `InkWell` inside the
      // card's `InkWell` is exactly how: the innermost hit wins, so the news
      // that can be answered is answered and everything else still opens the
      // activity screen.
      child: actionable
          ? InkWell(
              key: ValueKey<String>('action:${line.text}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: row,
              ),
            )
          : row,
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
        // Both halves give way. At 1.5x system text "43 מתוך 150 רעיונות" is
        // wider than a third of a 320px card, and a figure that cannot shrink
        // put an overflow stripe across the bottom of the block.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Flexible(
              flex: 5,
              child: Text(
                challenge.subline,
                style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 4,
              child: Text(
                challenge.progressLabel,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: fill,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The green dot that says the figures beside it are current.
///
/// **It beats once when the line changes, and is otherwise still.** The obvious
/// version — `repeat(reverse: true)` — is a permanently running animation on
/// the landing screen: the page would repaint sixty times a second for as long
/// as it is open, for a 14-pixel decoration. Tying the single pulse to the
/// moment the sentence beside it turns over costs nothing between beats, and
/// says the same thing better: the dot moves *because* something happened.
class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.beat});

  /// Changes each time the banner turns over. Any new value fires one pulse.
  final int beat;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void didUpdateWidget(covariant _LivePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.beat != oldWidget.beat) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The palette's own green, not Material's: this dot sits a few pixels
    // from blocks drawn in `statusDating`, and a second green there is one
    // green too many.
    const Color live = AppColors.statusDating;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final double t = _controller.value;
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // The ring rides out and fades, once.
              Container(
                width: 8 + 8 * t,
                height: 8 + 8 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: live,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
