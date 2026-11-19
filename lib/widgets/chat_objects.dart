import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// What a chat message is about, drawn **inside the conversation** as
/// something to act on — a card to open, an idea to answer — the way a
/// shared contact or location is drawn in WhatsApp. Opening one raises a
/// sheet over the chat; nobody has to leave the conversation.
class ChatObject extends StatelessWidget {
  const ChatObject({super.key, required this.chatRef, required this.me});

  final ChatRef chatRef;
  final String me;

  @override
  Widget build(BuildContext context) {
    return switch (chatRef.kind) {
      'card' => _CardObject(chatRef: chatRef, me: me),
      'proposal' || 'idea' => _ProposalObject(chatRef: chatRef, me: me),
      _ => Text(chatRef.label),
    };
  }
}

/// A small line the system wrote — "הרעיון אושר", "עבר להמתנה" — centred and
/// quiet, never a bubble.
class ChatSystemLine extends StatelessWidget {
  const ChatSystemLine({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
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

class _ObjectFrame extends StatelessWidget {
  const _ObjectFrame({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: BorderDirectional(
                start: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CardObject extends StatelessWidget {
  const _CardObject({required this.chatRef, required this.me});

  final ChatRef chatRef;
  final String me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? owner = chatRef.ownerUid;
    final bool mine = owner == null || owner == me;
    if (mine) {
      final Person? person = context.watch<PersonRepository>().getById(
        chatRef.id,
      );
      return _ObjectFrame(
        onTap: person == null
            ? null
            : () => context.push('/people/${person.id}'),
        child: _row(
          theme,
          avatar: person == null
              ? const CircleAvatar(radius: 22)
              : PersonAvatar(person: person, radius: 22),
          name: person?.fullName ?? chatRef.label,
          gender: person?.gender,
          summary: person == null ? '' : sharedSummaryOf(person),
          caption: 'הכרטיס מהמאגר שלך',
        ),
      );
    }
    return ValueListenableBuilder<List<SharedCard>>(
      valueListenable: MatchmakerNetwork.cards,
      builder: (BuildContext context, _, _) {
        final SharedCard? card = MatchmakerNetwork.cardOf(owner, chatRef.id);
        if (card == null) {
          return _ObjectFrame(
            child: _row(
              theme,
              avatar: const CircleAvatar(
                radius: 22,
                child: Icon(Icons.person_outline_rounded),
              ),
              name: chatRef.label,
              summary: '',
              caption: 'הכרטיס כבר לא זמין לך',
            ),
          );
        }
        final Person person = card.person;
        return _ObjectFrame(
          onTap: () => SharedCardScreen.showSheet(
            context,
            ownerUid: card.ownerUid,
            personId: card.personId,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _row(
                theme,
                avatar: SharedPhoto(
                  ownerUid: card.ownerUid,
                  path: card.photoPaths.firstOrNull,
                  person: person,
                  radius: 22,
                ),
                name: person.fullName,
                gender: person.gender,
                summary: sharedSummaryOf(person),
                caption: 'דרך ${card.ownerFirstName} · לצפייה בלבד',
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => NetworkActions.propose(context, card),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                  label: const Text('להציע רעיון'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    ThemeData theme, {
    required Widget avatar,
    required String name,
    required String summary,
    required String caption,
    Gender? gender,
  }) {
    return Row(
      children: <Widget>[
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: gender == null ? null : AppColors.genderAccent(gender),
                ),
              ),
              if (summary.isNotEmpty)
                Text(summary, style: theme.textTheme.bodySmall),
              Text(
                caption,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_left_rounded, size: 18),
      ],
    );
  }
}

class _ProposalObject extends StatelessWidget {
  const _ProposalObject({required this.chatRef, required this.me});

  final ChatRef chatRef;
  final String me;

  static String stateOf(IdeaProposal p, String me) {
    switch (p.status) {
      case IdeaProposalStatus.pending:
        return p.isIncomingFor(me) ? 'ממתין לתשובה שלך' : 'ממתין לתשובה';
      case IdeaProposalStatus.approved:
        final String partner = p.partnerStatusFor(me)?.displayName ?? '';
        return partner.isEmpty
            ? 'הרעיון נפתח'
            : 'הרעיון נפתח · אצל ${p.otherNameOf(me)}: $partner';
      case IdeaProposalStatus.declined:
        return 'הרעיון לא אושר';
      case IdeaProposalStatus.withdrawn:
        return 'ההצעה בוטלה';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<List<IdeaProposal>>(
      valueListenable: MatchmakerNetwork.proposals,
      builder: (BuildContext context, _, _) {
        final IdeaProposal? p = MatchmakerNetwork.proposal(chatRef.id);
        final String pair = p == null
            ? chatRef.label
            : '${p.candidateFirstName} ו${p.targetFirstName}';
        final SharedIdeaLink? link = p == null ? null : SharedIdeas.links[p.id];
        final bool answer =
            p != null &&
            p.status == IdeaProposalStatus.pending &&
            p.isIncomingFor(me);
        return _ObjectFrame(
          onTap: p == null
              ? null
              : () => ProposalScreen.showSheet(context, chatRef.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.favorite_rounded,
                    size: 20,
                    color: AppColors.femaleAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'רעיון: $pair',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          p == null ? 'טוען…' : stateOf(p, me),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, size: 18),
                ],
              ),
              if (answer)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    children: <Widget>[
                      FilledButton(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          if (!OfflineGuard.allow(context)) return;
                          final bool ok = await MatchmakerNetwork.answer(
                            p,
                            approve: true,
                          );
                          if (!context.mounted) return;
                          AppNotice.show(
                            context,
                            ok
                                ? 'הרעיון נפתח אצל שניכם ב"הרעיונות שלי"'
                                : 'לא הצלחנו לאשר. נסו שוב.',
                            isError: !ok,
                          );
                        },
                        child: const Text('פותחים'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          if (!OfflineGuard.allow(context)) return;
                          await MatchmakerNetwork.answer(p, approve: false);
                        },
                        child: const Text('לא הפעם'),
                      ),
                    ],
                  ),
                )
              else if (link != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => context.push('/matches/${link.matchId}'),
                    child: const Text('לרעיון שלי'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
