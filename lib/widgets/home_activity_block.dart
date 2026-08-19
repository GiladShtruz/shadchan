import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "הפעילות" on the home screen: your score, the community's, one window at a
/// time.
///
/// **Two numbers and nothing else.** No leaderboard, no chart, no breakdown, no
/// shared target — those all live one tap away on a screen somebody opened *to
/// look at numbers*, and a home screen that leads with a scoreboard has stopped
/// being a workspace. What is left is the one comparison worth putting on the
/// landing page: "12 השבוע" says very little on its own and a great deal beside
/// "1,842 בקהילה".
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

  @override
  void initState() {
    super.initState();
    _load(_period);
  }

  Future<void> _load(CommunityPeriod period) async {
    if (_totals.containsKey(period)) {
      return;
    }
    // Cheap and harmless without an account — `CommunityService` refuses an
    // anonymous uid and answers with zeroes rather than reaching the network.
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
                    'הפעילות',
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
