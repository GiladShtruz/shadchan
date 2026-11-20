import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/utils/gender_text.dart';

/// The value line at the head of המאגר שלי: "אתה משתף X כרטיסים · השדכנים
/// שלך משתפים איתך Y" — a tap on it opens what is shared with me. With
/// nothing shared either way, the way to the matchmakers among the contacts.
/// Every figure here is a count already on the share rows: nothing is read.
class NetworkLink extends StatelessWidget {
  const NetworkLink({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        MatchmakerShares.rows,
        MatchmakerNetwork.proposals,
        NetworkSharing.revision,
      ]),
      builder: (BuildContext context, _) {
        final int mine = NetworkSharing.sharedNow(
          context.watch<PersonRepository>().getAll(),
          accessTo: context.watch<CardAccessProvider>().accessTo,
        ).length;
        final int connected = MatchmakerNetwork.connectedNames.length;
        final int cards = MatchmakerShares.totalSharedWithMe;
        final int waiting = MatchmakerNetwork.incomingPending.length;
        final String title = connected == 0
            ? 'שיתוף כרטיסים עם שדכנים שמכירים'
            : 'שדכנים שותפים';
        final String line = connected == 0
            ? 'בוחרים מה לשתף עם כל שדכן מאנשי הקשר, ורואים מה הם משתפים'
            : waiting > 0
            ? (waiting == 1
                  ? 'הצעת רעיון אחת ממתינה לתשובה שלך'
                  : '$waiting הצעות רעיון ממתינות לתשובה שלך')
            : '{אתה משתף|את משתפת} $mine כרטיסים · השדכנים שלך משתפים '
                      'איתך $cards'
                  .forGender(context.userGender);
        return Material(
          color: dark ? AppColors.surfaceDm : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push(
              connected == 0 ? '/known-matchmakers' : '/network',
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: ink.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ink.withValues(alpha: dark ? 0.22 : 0.12),
                    ),
                    child: Badge(
                      isLabelVisible: waiting > 0,
                      label: Text('$waiting'),
                      child: Icon(
                        Icons.diversity_3_outlined,
                        size: 22,
                        color: ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(line, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (connected > 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: ink,
                      ),
                      onPressed: () => context.push('/network/sharing'),
                      child: const Text('ניהול'),
                    ),
                  Icon(Icons.chevron_right_rounded, color: ink),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
