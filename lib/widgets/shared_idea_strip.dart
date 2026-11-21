import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
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
        // The idea was offered for a card the other matchmaker shared: if
        // they took it out of the share, the idea and what is needed to go
        // on stay — the card is shown dimmed, with the way to ask again.
        final bool mineOffered = p != null && me != null && p.fromUid == me;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _strip(context, theme, link, p, partner, who),
            if (mineOffered)
              _AccessCheck(
                ownerUid: p.toUid,
                personId: p.targetPersonId,
                ownerName: p.toName,
                personName: p.targetFirstName,
              ),
          ],
        );
      },
    );
  }

  Widget _strip(
    BuildContext context,
    ThemeData theme,
    SharedIdeaLink link,
    IdeaProposal? p,
    MatchStatus? partner,
    String who,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.push('/network/proposals/${link.proposalId}'),
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
  }
}

/// "השדכן הסיר את הגישה לכרטיס" — one read of the card, once per session
/// (remembered by [MatchmakerNetwork.fetchCard]); nothing while it is shared.
class _AccessCheck extends StatefulWidget {
  const _AccessCheck({
    required this.ownerUid,
    required this.personId,
    required this.ownerName,
    required this.personName,
  });

  final String ownerUid;
  final String personId;
  final String ownerName;
  final String personName;

  @override
  State<_AccessCheck> createState() => _AccessCheckState();
}

class _AccessCheckState extends State<_AccessCheck> {
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _gone = MatchmakerNetwork.isGone(widget.ownerUid, widget.personId);
    if (!_gone &&
        MatchmakerNetwork.cardOf(widget.ownerUid, widget.personId) == null) {
      unawaited(
        MatchmakerNetwork.fetchCard(widget.ownerUid, widget.personId).then((
          SharedCard? card,
        ) {
          if (mounted && card == null) setState(() => _gone = true);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_gone) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final String owner = widget.ownerName.trim().isEmpty
        ? 'השדכן/ית'
        : widget.ownerName.trim().split(RegExp(r'\s+')).first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Opacity(
        opacity: 0.85,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'השדכן הסיר את הגישה לכרטיס',
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  'הרעיון והפרטים שכבר יש לך נשארים להמשך הטיפול.',
                  style: theme.textTheme.bodySmall,
                ),
                Wrap(
                  spacing: 4,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => NetworkActions.chatWith(
                        context,
                        otherUid: widget.ownerUid,
                        otherName: widget.ownerName,
                        ref: ChatRef(
                          kind: 'card',
                          id: widget.personId,
                          ownerUid: widget.ownerUid,
                          label: widget.personName,
                        ),
                        message:
                            'אפשר לפתוח לי שוב את הכרטיס של ${widget.personName}? '
                            'יש בינינו רעיון פתוח עליו/ה.',
                      ),
                      child: const Text('בקש גישה מחדש'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final String? phone = _phoneOf(context);
                        final bool ok = await WhatsAppUtils.openChatWithPhone(
                          phone,
                        );
                        if (!ok && context.mounted) {
                          AppNotice.show(
                            context,
                            'לא מצאנו מספר שמור ל$owner.',
                            isError: true,
                          );
                        }
                      },
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                      label: Text('WhatsApp ל$owner'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _phoneOf(BuildContext context) {
    try {
      for (final CardHelper h
          in context.read<CardAccessProvider>().knownHelpers) {
        if (h.uid == widget.ownerUid) {
          return ContactHashUpload.phoneFor(h.phoneHash);
        }
      }
    } catch (_) {}
    return null;
  }
}
