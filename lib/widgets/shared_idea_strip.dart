import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/utils/enums.dart';

/// One line on a shared idea's card: "רעיון משותף עם יונתן · אצלו: בבדיקה"
/// and the chat with him. Nothing at all on an idea that is not shared.
///
/// Each matchmaker moves their own half; this only says where the other half
/// stands — what the partner reported, never more.
class SharedIdeaStrip extends StatelessWidget {
  const SharedIdeaStrip({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        SharedIdeas.revision,
        MatchmakerNetwork.proposals,
      ]),
      builder: (BuildContext context, _) {
        final SharedIdeaLink? link = SharedIdeas.forMatch(matchId);
        if (link == null) return const SizedBox.shrink();
        final ThemeData theme = Theme.of(context);
        final IdeaProposal? p = MatchmakerNetwork.proposal(link.proposalId);
        final String? me = MatchmakerNetwork.uid;
        final MatchStatus? partner = (p != null && me != null)
            ? p.partnerStatusFor(me)
            : null;
        final String who = link.partnerFirstName;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Material(
            color: theme.colorScheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () =>
                  context.push('/network/proposals/${link.proposalId}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.diversity_3_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        partner == null
                            ? 'רעיון משותף עם $who'
                            : 'רעיון משותף עם $who · אצל $who: ${partner.displayName}',
                        style: theme.textTheme.labelMedium,
                        maxLines: 2,
                      ),
                    ),
                    IconButton(
                      tooltip: 'צ\'אט עם $who',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => NetworkActions.chatWith(
                        context,
                        otherUid: link.partnerUid,
                        otherName: link.partnerName,
                        ref: ChatRef(
                          kind: 'idea',
                          id: link.proposalId,
                          label: p == null
                              ? 'רעיון משותף'
                              : '${p.candidateFirstName} ו${p.targetFirstName}',
                        ),
                      ),
                      icon: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
