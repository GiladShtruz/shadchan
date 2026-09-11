import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "הפעילות שלי" beside "פעילות הקהילה" — two tiles, one number each.
///
/// **Two numbers and nothing else.** No leaderboard, no chart, no breakdown —
/// those all live one tap away on a screen somebody opened *to look at
/// numbers*, and a home screen that leads with a scoreboard has stopped being a
/// workspace.
///
/// What is left is the one comparison worth putting on the landing page: "12"
/// says very little on its own and a great deal beside "1,842 בקהילה".
///
/// **The window is chosen by hand, and remembered.** It rotated by itself for
/// a while — השבוע → החודש → כל הזמנים on a five-second timer — on the
/// reasoning that a landing page should answer rather than ask. What that
/// actually produced was a number that changed under the reader's thumb: you
/// cannot compare two figures that are about to become two different figures,
/// and there was no way to hold the one you wanted. The three windows are a row
/// of tabs again, both halves move together so the two figures on screen are
/// always about the same span of time, and whichever one is left selected is
/// the one that is there on the way back — see
/// [CommunityProfileStore.activityPeriod].
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

  /// The three offered, in the order they read best: this week first, because
  /// it is the window somebody is actually working in.
  static const List<CommunityPeriod> periods = <CommunityPeriod>[
    CommunityPeriod.week,
    CommunityPeriod.month,
    CommunityPeriod.allTime,
  ];

  @override
  State<HomeActivityBlock> createState() => _HomeActivityBlockState();
}

class _HomeActivityBlockState extends State<HomeActivityBlock> {
  /// The window on screen — the one this device was left on.
  CommunityPeriod _period = CommunityProfileStore.activityPeriod;

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
  }

  void _select(CommunityPeriod period) {
    if (period == _period) {
      return;
    }
    setState(() => _period = period);
    // Written on the tap rather than on leaving the screen: the home screen is
    // never "left" in a way this widget is told about, and a preference that
    // only survives a graceful exit is a preference that mostly does not.
    CommunityProfileStore.setActivityPeriod(period);
    _load(period);
  }

  /// All three windows at once rather than the one on screen.
  ///
  /// A tab is tapped and answered in the same frame that way, instead of
  /// showing "0 בקהילה" until a read lands — and the three reads share
  /// [CommunityService]'s process cache with the activity screen, so asking
  /// for them together costs the same as asking for them one at a time.
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

    final CommunityPeriod period = _period;
    final CommunityTotals? totals = _totals[period];

    return CommunityCard(
      surface: CommunitySurface.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The window both figures belong to, chosen once above the pair
          // rather than named twice inside them. The same control the activity
          // screen uses, so switching window means the same gesture in both
          // places.
          CommunityPeriodTabs(
            selected: period,
            onChanged: _select,
            periods: HomeActivityBlock.periods,
          ),
          const SizedBox(height: 10),
          // Not `stretch`: each tile sets its own height, and stretching would
          // hand them the column's unbounded height.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _FigureTile(
                  label: 'הפעילות שלי',
                  value: community.myPoints(period),
                  period: period,
                  // The warm tone the matchmaker's own surfaces wear, so the
                  // two tiles are told apart by colour as well as by their
                  // labels: this half is yours, the one beside it is
                  // everybody's.
                  accent: theme.brightness == Brightness.dark
                      ? AppColors.secondaryDarkDm
                      : AppColors.secondary,
                  onTap: widget.onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: signedIn
                    ? _FigureTile(
                        label: 'פעילות הקהילה',
                        // Zero until the read lands, which is also the honest
                        // answer on a device that has never reached the
                        // network.
                        value: totals?.points ?? 0,
                        period: period,
                        accent: communityLead(theme),
                        onTap: widget.onOpen,
                      )
                    : _JoinTile(onTap: widget.onOpen),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const ActivityScoringLink(),
        ],
      ),
    );
  }
}

/// One of the two tiles: the name at the top, the figure across the middle,
/// and the unit under it.
///
/// **Three lines and no square.** These were 1:1 boxes with the label sitting
/// directly on top of a headline number — as tall as they were wide, which on
/// a phone is a pair of 160px blocks for two figures, and they pushed the rest
/// of the page down for it. What is here now is a card the height of the type
/// in it: a small caption, the number in the largest size on the block, and
/// "נקודות פעילות" underneath in the smallest, so what the figure *is* is said
/// once and quietly instead of being inferred from a pill above the pair.
class _FigureTile extends StatelessWidget {
  const _FigureTile({
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

    return _Tile(
      accent: accent,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: FittedBox(
              key: ValueKey<String>('${period.name}:$value'),
              fit: BoxFit.scaleDown,
              child: Text(
                CommunityFigure.format(value),
                maxLines: 1,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'נקודות פעילות',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.1,
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
/// Deliberately the same tile as the figure beside it rather than a banner
/// under the pair: the shape is what says "there is a number that belongs
/// here", and the sentence says why it is missing.
class _JoinTile extends StatelessWidget {
  const _JoinTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);

    return _Tile(
      accent: lead,
      onTap: onTap,
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
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The shape both halves wear: equal, compact, and entirely a tap target.
///
/// No fixed height any more. It used to be squared off against its own width,
/// which is what made the pair the tallest thing on the home screen; the height
/// is the three lines of type inside it now, and it grows with the system font
/// instead of being clamped against it.
class _Tile extends StatelessWidget {
  const _Tile({required this.accent, required this.onTap, required this.child});

  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Material(
      color: dark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }
}
