import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/services/matchmaker_connections.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/shared_pool.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "רעיונות שהמאגר מציע לך" — from the connected matchmakers' shared cards:
/// one of this matchmaker's own friends with somebody from another's pool,
/// paired by the same rules as the database's own ideas. Acting on one is
/// offering it to the matchmaker who holds the card — never contacting the
/// single.
class NetworkIdeasList extends StatefulWidget {
  const NetworkIdeasList({super.key});

  /// Pure: the pairs of [mine] × [pool], each pair with exactly one side from
  /// the pool, best first, minus pairs already offered.
  static List<NewIdeaSuggestion> pairs({
    required List<Person> mine,
    required List<SharedCard> pool,
    required List<IdeaProposal> proposals,
    required List<MatchIdea> myMatches,
    Set<String> Function(String personId)? dismissedFor,
  }) {
    final Set<String> offered = <String>{
      for (final IdeaProposal p in proposals)
        if (p.status != IdeaProposalStatus.withdrawn) ...<String>{
          '${p.candidatePersonId}|${SharedCard.keyOf(p.toUid, p.targetPersonId)}',
          '${p.targetPersonId}|${SharedCard.keyOf(p.fromUid, p.candidatePersonId)}',
        },
    };
    final List<NewIdeaSuggestion> all = NewIdeaSuggestions.build(
      people: <Person>[...mine, for (final SharedCard c in pool) c.person],
      matches: myMatches,
      dismissedFor: dismissedFor,
    );
    return <NewIdeaSuggestion>[
      for (final NewIdeaSuggestion s in all)
        if (_network(s.male) != _network(s.female) &&
            !offered.contains(_offerKey(s)))
          s,
    ];
  }

  static bool _network(Person p) => p.id.startsWith('shared:');

  static String _offerKey(NewIdeaSuggestion s) {
    final Person mine = _network(s.male) ? s.female : s.male;
    final Person theirs = _network(s.male) ? s.male : s.female;
    return '${mine.id}|${theirs.id}';
  }

  @override
  State<NetworkIdeasList> createState() => _NetworkIdeasListState();
}

class _NetworkIdeasListState extends State<NetworkIdeasList> {
  int _shown = 20;

  @override
  void initState() {
    super.initState();
    unawaited(MatchmakerNetwork.start());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repo = context.watch<PersonRepository>();
    final MatchRepository matches = context.watch<MatchRepository>();
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        MatchmakerNetwork.cards,
        MatchmakerNetwork.proposals,
        MatchmakerConnections.connections,
      ]),
      builder: (BuildContext context, _) {
        if (MatchmakerNetwork.connectedNames.isEmpty) {
          return _Empty(
            text:
                'כשתתחבר/י לשדכנים שאת/ה מכיר/ה והם ישתפו כרטיסים, יופיעו כאן '
                'רעיונות שמחברים בין החברים שלך לחברים שלהם.',
            button: 'לשדכנים שאני מכיר',
            onPressed: () => context.push('/known-matchmakers'),
          );
        }
        final List<Person> mine = <Person>[
          for (final Person p in repo.getAll())
            if (!SharedIdeas.isPartnersPerson(p.id)) p,
        ];
        final Set<String> myIds = <String>{
          for (final Person p in mine)
            if (!p.hidden && PhoneIdentity.hash(p.phone) != null)
              PhoneIdentity.hash(p.phone)!,
        };
        final List<SharedCard> pool = <SharedCard>[
          for (final SharedPoolEntry e in SharedPool.build(
            MatchmakerNetwork.cards.value,
            myIdentities: myIds,
          ))
            e.primary,
        ];
        final Map<String, SharedCard> byKey = <String, SharedCard>{
          for (final SharedCard c in pool) c.key: c,
        };
        final List<NewIdeaSuggestion> pairs = NetworkIdeasList.pairs(
          mine: mine,
          pool: pool,
          proposals: MatchmakerNetwork.proposals.value,
          myMatches: matches.getAll(),
          dismissedFor: SuggestionDismissals.dismissedFor,
        );
        if (pairs.isEmpty) {
          return const _Empty(
            text:
                'עוד אין רעיונות מהמאגרים של השדכנים המחוברים. כשישותפו עוד '
                'כרטיסים, הם יופיעו כאן.',
          );
        }
        final List<NewIdeaSuggestion> shown = pairs.take(_shown).toList();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          itemCount: shown.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int i) {
            if (i == shown.length) {
              return pairs.length > shown.length
                  ? TextButton(
                      onPressed: () => setState(() => _shown += 20),
                      child: const Text('הצג עוד'),
                    )
                  : const SizedBox.shrink();
            }
            final NewIdeaSuggestion s = shown[i];
            final bool maleIsTheirs = s.male.id.startsWith('shared:');
            final Person myPerson = maleIsTheirs ? s.female : s.male;
            final SharedCard? card =
                byKey[(maleIsTheirs ? s.male : s.female).id];
            if (card == null) return const SizedBox.shrink();
            return HomePaperCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _Side(
                            avatar: PersonAvatar(person: myPerson, radius: 28),
                            person: myPerson,
                            caption: 'מהמאגר שלך',
                          ),
                        ),
                        Icon(
                          Icons.favorite_rounded,
                          color: AppColors.femaleAccent,
                          size: 20,
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => context.push(
                              '/network/card/${card.ownerUid}/${card.personId}',
                            ),
                            child: _Side(
                              avatar: SharedPhoto(
                                ownerUid: card.ownerUid,
                                path: card.photoPaths.firstOrNull,
                                person: card.person,
                                radius: 28,
                              ),
                              person: card.person,
                              caption: 'מהמאגר של ${card.ownerFirstName}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (s.reasons.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        s.reasons.join(' · '),
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => NetworkActions.propose(
                              context,
                              card,
                              candidate: myPerson,
                            ),
                            child: Text('להציע ל${card.ownerFirstName}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await SuggestionDismissals.dismiss(
                              s.male.id,
                              s.female.id,
                            );
                            await SuggestionDismissals.dismiss(
                              s.female.id,
                              s.male.id,
                            );
                            if (mounted) setState(() {});
                          },
                          child: const Text('לא מתאים'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.avatar,
    required this.person,
    required this.caption,
  });

  final Widget avatar;
  final Person person;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        avatar,
        const SizedBox(height: 4),
        Text(
          person.fullName,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.genderAccent(person.gender),
          ),
        ),
        Text(sharedSummaryOf(person), style: theme.textTheme.bodySmall),
        Text(caption, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.button, this.onPressed});

  final String text;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, textAlign: TextAlign.center),
            if (button != null) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(onPressed: onPressed, child: Text(button!)),
            ],
          ],
        ),
      ),
    );
  }
}
