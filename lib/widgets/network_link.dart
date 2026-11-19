import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/matchmaker_connections.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "המאגר המשותף" at the head of המאגר שלי: how many cards the connected
/// matchmakers share, and ideas waiting for an answer — or, with nobody
/// connected yet, the way to the matchmakers among the contacts.
class NetworkLink extends StatelessWidget {
  const NetworkLink({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        MatchmakerNetwork.cards,
        MatchmakerNetwork.proposals,
        MatchmakerConnections.connections,
      ]),
      builder: (BuildContext context, _) {
        final int connected = MatchmakerNetwork.connectedNames.length;
        final int cards = MatchmakerNetwork.cards.value.length;
        final int waiting = MatchmakerNetwork.incomingPending.length;
        final String title = connected == 0
            ? 'המאגר המשותף של שדכנים שמכירים'
            : 'המאגר המשותף';
        final String line = connected == 0
            ? 'מתחברים לשדכנים מאנשי הקשר, ורואים כרטיסים שהם בוחרים לשתף'
            : waiting > 0
            ? (waiting == 1
                  ? 'הצעת רעיון אחת ממתינה לתשובה שלך'
                  : '$waiting הצעות רעיון ממתינות לתשובה שלך')
            : '$cards כרטיסים מ־$connected שדכנים מחוברים';
        return Material(
          color: dark ? AppColors.surfaceDm : AppColors.cardCream,
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
