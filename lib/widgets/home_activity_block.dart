import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "נתונים" on the home screen: your score, the community's, one window at a
/// time.
///
/// **Two numbers and nothing else.** No leaderboard, no chart, no breakdown —
/// those all live one tap away on a screen somebody opened *to look at
/// numbers*, and a home screen that leads with a scoreboard has stopped being a
/// workspace. (The week's shared target is not a number about the reader at
/// all; it belongs to `HomeCommunityPulse`, the block directly above this one.)
///
/// What is left is the one comparison worth putting on the landing page: "12
/// השבוע" says very little on its own and a great deal beside "1,842 בקהילה".
///
/// Your own figure needs no network and is drawn on the first frame. The
/// community column fills in when the read lands rather than holding a spinner
/// in the middle of the page.
///
/// **A matchmaker who has not connected an account keeps their own half.**
/// Where the community figure would be they get one sentence and a button
/// instead. The point is not to withhold anything they had — the personal
/// numbers are theirs and go on working — but to make the missing half legible:
/// there is a community here, and they are not in it yet.
class HomeActivityBlock extends StatefulWidget {
  const HomeActivityBlock({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<HomeActivityBlock> createState() => _HomeActivityBlockState();
}

class _HomeActivityBlockState extends State<HomeActivityBlock> {
  CommunityPeriod _period = CommunityPeriod.week;

  /// Kept per window so switching back to one already read is instant and free.
  final Map<CommunityPeriod, CommunityTotals> _totals =
      <CommunityPeriod, CommunityTotals>{};

  /// Whether the last look at [AccountProvider] said there was an account.
  ///
  /// The block is built before Firebase has finished restoring the session, so
  /// the first read of every window happens with no account and comes back
  /// unresolved. Watching this is how the community column fills itself in a
  /// moment later instead of sitting on "0" until the next launch.
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _load(_period);
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

  void _select(CommunityPeriod period) {
    setState(() => _period = period);
    _load(period);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;
    final CommunityTotals? totals = _totals[_period];

    // Firebase resolves the session a moment after launch, so the read fired
    // from `initState` usually happened with no account at all. This is the
    // rebuild that follows; asking again here is what fills the community
    // column in instead of leaving it on "0" until the next launch.
    if (signedIn && !_wasSignedIn) {
      _wasSignedIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(_period));
    }

    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The heading and the figures open the full screen; the switch and
          // the explanation below do not, so neither swallows the other's tap.
          InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    // "נתונים" rather than "הפעילות": what is under the heading
                    // is two figures and the way into the charts, and the block
                    // sat directly above a page that says "הפעילות שלך" — the
                    // same word twice, meaning two different things.
                    'נתונים',
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
          ),
          const SizedBox(height: 12),
          CommunityPeriodTabs(
            selected: _period,
            onChanged: _select,
            periods: CommunityPeriodTabs.weekMonthAllTime,
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CommunitySmallFigure(
                    value: community.myPoints(_period),
                    label: 'הפעילות שלך',
                  ),
                ),
                if (signedIn)
                  Expanded(
                    child: CommunitySmallFigure(
                      // Zero until the read lands, which is also the honest
                      // answer on a device that has never reached the network.
                      value: totals?.points ?? 0,
                      label: 'פעילות הקהילה',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const ActivityScoringLink(),
          if (!signedIn) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const CommunitySignInCard.joinTheCommunity(),
          ],
        ],
      ),
    );
  }
}
