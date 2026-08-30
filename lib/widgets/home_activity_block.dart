import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "הפעילות שלי" beside "פעילות הקהילה" — two squares, one number each.
///
/// **Two numbers and nothing else.** No leaderboard, no chart, no breakdown —
/// those all live one tap away on a screen somebody opened *to look at
/// numbers*, and a home screen that leads with a scoreboard has stopped being a
/// workspace.
///
/// What is left is the one comparison worth putting on the landing page: "12"
/// says very little on its own and a great deal beside "1,842 בקהילה".
///
/// **The window turns over by itself, and the two squares turn together.** The
/// three windows used to be a row of tabs, which asked the reader to pick one
/// before the block would say anything — on a landing page that is a question,
/// not an answer. They rotate now, השבוע → החודש → כל הזמנים, both halves in
/// step so the two figures on screen are always about the same span of time,
/// with the span named between them.
///
/// **A window the matchmaker did nothing in is skipped entirely**, however busy
/// the community was in it. "0 השבוע" beside "1,842 בקהילה" is not a
/// comparison, it is a reproach — and it is the one thing this block must never
/// be. What is shown instead is the next window they *were* active in.
///
/// Your own figures need no network and are drawn on the first frame. The
/// community column fills in when the reads land rather than holding a spinner
/// in the middle of the page.
///
/// **A matchmaker who has not connected an account keeps their own half.**
/// Where the community figure would be they get an invitation instead. The
/// point is not to withhold anything they had — the personal numbers are theirs
/// and go on working — but to make the missing half legible: there is a
/// community here, and they are not in it yet.
class HomeActivityBlock extends StatefulWidget {
  const HomeActivityBlock({super.key, required this.onOpen});

  final VoidCallback onOpen;

  /// The rotation, in the order it reads best: this week first, because it is
  /// the window somebody is actually working in.
  static const List<CommunityPeriod> periods = <CommunityPeriod>[
    CommunityPeriod.week,
    CommunityPeriod.month,
    CommunityPeriod.allTime,
  ];

  @override
  State<HomeActivityBlock> createState() => _HomeActivityBlockState();
}

class _HomeActivityBlockState extends State<HomeActivityBlock> {
  /// Long enough to read two numbers and their window without hurrying, short
  /// enough that a glance at the page catches it moving.
  static const Duration _dwell = Duration(seconds: 5);

  /// Advances through whichever windows are worth showing. Counted rather than
  /// held as a period, so a window dropping in or out of the rotation — the
  /// first idea of the week lands, and השבוע becomes showable — never leaves
  /// the block pointing at something that is no longer in the list.
  int _beat = 0;
  Timer? _timer;

  /// Kept per window so a window already read is instant and free.
  final Map<CommunityPeriod, CommunityTotals> _totals =
      <CommunityPeriod, CommunityTotals>{};

  /// Whether the last look at [AccountProvider] said there was an account.
  ///
  /// The block is built before Firebase has finished restoring the session, so
  /// the first read of every window happens with no account and comes back
  /// unresolved. Watching this is how the community column fills itself in a
  /// moment later instead of sitting on "0" until the next launch.
  bool _wasSignedIn = false;

  /// The publish this block last read after — see
  /// [CommunityProvider.publishRevision]. A window that resolved is never asked
  /// for again, which is right until this device tells the server something:
  /// at that moment every community figure in hand is one publish out of date,
  /// including the reader's own contribution to it.
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _timer = Timer.periodic(_dwell, (_) {
      if (mounted) {
        setState(() => _beat++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// All three windows at once rather than the one on screen.
  ///
  /// The block turns itself over every few seconds, so a window fetched only
  /// when it comes up would show "0 בקהילה" for the first second of every
  /// rotation — and the three reads share [CommunityService]'s process cache
  /// with the activity screen, so asking for them together costs the same as
  /// asking for them one at a time.
  Future<void> _loadAll() async {
    for (final CommunityPeriod period in HomeActivityBlock.periods) {
      await _load(period);
    }
  }

  Future<void> _load(CommunityPeriod period) async {
    // A window that actually came back is never asked for again; one that did
    // not — no account yet, no network — always is. Storing an unresolved zero
    // as though it were an answer is what used to leave a live community
    // showing "0" for the whole session. See [CommunityTotals.resolved].
    if (_totals[period]?.resolved ?? false) {
      return;
    }
    // Cheap and harmless without an account — `CommunityService` refuses an
    // anonymous uid and answers with an unresolved zero rather than reaching
    // the network.
    final CommunityTotals totals = await CommunityService.totals(period);
    if (mounted) {
      setState(() => _totals[period] = totals);
    }
  }

  /// The windows worth showing: the ones the matchmaker actually did something
  /// in.
  ///
  /// Falls back to the whole rotation when they have done nothing anywhere,
  /// which is a brand-new matchmaker on their first launch. A single honest "0
  /// השבוע" is the right thing to show somebody who has not started yet; what
  /// the rule above exists to prevent is a *busy* matchmaker being shown the
  /// one window they happen to have been quiet in.
  List<CommunityPeriod> _showable(CommunityProvider community) {
    final List<CommunityPeriod> live = <CommunityPeriod>[
      for (final CommunityPeriod period in HomeActivityBlock.periods)
        if (community.myPoints(period) > 0) period,
    ];
    return live.isEmpty ? const <CommunityPeriod>[CommunityPeriod.week] : live;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;

    // Firebase resolves the session a moment after launch, so the reads fired
    // from `initState` usually happened with no account at all. This is the
    // rebuild that follows; asking again here is what fills the community
    // column in instead of leaving it on "0" until the next launch.
    if (signedIn && !_wasSignedIn) {
      _wasSignedIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    }
    final int revision = community.publishRevision;
    if (revision != _revision) {
      _revision = revision;
      if (revision > 0) {
        _totals.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
      }
    }

    final List<CommunityPeriod> showable = _showable(community);
    final CommunityPeriod period = showable[_beat % showable.length];
    final CommunityTotals? totals = _totals[period];

    return CommunityCard(
      surface: CommunitySurface.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The window the two figures belong to, named once between them
          // rather than twice inside them. It changes with the numbers, so a
          // reader who looks up mid-rotation is never left working out which
          // span of time they are looking at.
          _PeriodPill(period: period),
          const SizedBox(height: 12),
          // Not `stretch`: each square sets its own height from its own width,
          // and stretching would hand them the column's unbounded height.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _FigureSquare(
                  label: 'הפעילות שלי',
                  value: community.myPoints(period),
                  period: period,
                  // The warm tone the matchmaker's own surfaces wear, so the
                  // two squares are told apart by colour as well as by their
                  // labels: this half is yours, the one beside it is
                  // everybody's.
                  accent: theme.brightness == Brightness.dark
                      ? AppColors.secondaryDarkDm
                      : AppColors.secondary,
                  onTap: widget.onOpen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: signedIn
                    ? _FigureSquare(
                        label: 'פעילות הקהילה',
                        // Zero until the read lands, which is also the honest
                        // answer on a device that has never reached the
                        // network.
                        value: totals?.points ?? 0,
                        period: period,
                        accent: communityLead(theme),
                        onTap: widget.onOpen,
                      )
                    : _JoinSquare(onTap: widget.onOpen),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const ActivityScoringLink(),
        ],
      ),
    );
  }
}

/// The name of the window the two figures belong to.
class _PeriodPill extends StatelessWidget {
  const _PeriodPill({required this.period});

  final CommunityPeriod period;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        child: Container(
          key: ValueKey<CommunityPeriod>(period),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: lead.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            period.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: lead,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two squares: a name, and one number under it.
///
/// The number is the only thing in it that is allowed to be large. Everything
/// that could be said *about* the number — what it is made of, how it compares,
/// who else is on the board — is on the screen this square opens.
class _FigureSquare extends StatelessWidget {
  const _FigureSquare({
    required this.label,
    required this.value,
    required this.period,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final int value;

  /// Only ever the key of the animation: it is what makes the figure fade from
  /// one window's number to the next rather than snap.
  final CommunityPeriod period;

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _Square(
      accent: accent,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              child: FittedBox(
                key: ValueKey<String>('${period.name}:$value'),
                fit: BoxFit.scaleDown,
                child: Text(
                  CommunityFigure.format(value),
                  maxLines: 1,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The community half before there is an account to compare with.
///
/// Deliberately the same square as the figure beside it rather than a banner
/// under the pair: the shape is what says "there is a number that belongs
/// here", and the sentence says why it is missing.
class _JoinSquare extends StatelessWidget {
  const _JoinSquare({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);

    return _Square(
      accent: lead,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.groups_outlined, size: 26, color: lead),
          const SizedBox(height: 8),
          Text(
            'הצטרפו לקהילת השדכנים',
            maxLines: 3,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: lead,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

/// The shape both halves wear: equal, square-ish, and entirely a tap target.
class _Square extends StatelessWidget {
  const _Square({
    required this.accent,
    required this.onTap,
    required this.child,
  });

  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    // Square at the width a phone actually gives it, and taller only where the
    // system font asks for it. A strict 1:1 would clip the label at 1.5x text;
    // a free height would let the two halves come out different shapes.
    final double scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.6);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.maxWidth.clamp(96.0, 168.0) * scale;

        return SizedBox(
          height: side,
          child: Material(
            color: dark
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: <Color>[
                      accent.withValues(alpha: dark ? 0.16 : 0.08),
                      dark
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surface,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
