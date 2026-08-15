import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/match_detail_screen.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "רעיונות חדשים" — the screen behind the home page's opening button.
///
/// It does not invent anything: it walks the database, keeps the pairs that
/// already fit each other by the app's own matching rules, drops every pair
/// that already has a proposal or was pushed aside, and offers what is left in
/// the order the records argue for. Opening one creates a regular proposal.
class NewIdeasScreen extends StatefulWidget {
  const NewIdeasScreen({super.key});

  @override
  State<NewIdeasScreen> createState() => _NewIdeasScreenState();
}

class _NewIdeasScreenState extends State<NewIdeasScreen> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<NewIdeaSuggestion> ideas = NewIdeaSuggestions.build(
      people: personRepository.getAll(),
      matches: matchRepository.getAll(),
      dismissedFor: SuggestionDismissals.dismissedFor,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('רעיונות שהמאגר מציע לך')),
      body: SafeArea(
        child: ideas.isEmpty
            ? _EmptyState(theme: theme)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                itemCount: ideas.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return _Intro(count: ideas.length);
                  }
                  final NewIdeaSuggestion idea = ideas[index - 1];
                  return _IdeaCard(
                    idea: idea,
                    onOpen: () => _openIdea(idea),
                    onSkip: () => _skipIdea(idea),
                    onComparePair: () => _comparePair(idea),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _openIdea(NewIdeaSuggestion idea) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final NavigatorState navigator = Navigator.of(context);
    final MatchIdea? match = await matchRepository.create(
      idea.male.id,
      idea.female.id,
    );
    if (!mounted) {
      return;
    }
    if (match == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('כבר קיים רעיון לזוג הזה')),
        );
      return;
    }
    // This screen sits outside the navigation shell, and `/matches/:id` lives
    // inside one of its branches — routing to it from here left the shell
    // unbuilt and drew a blank page. The proposal is pushed as a plain page
    // instead, which also means closing it returns to this list.
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            MatchDetailScreen(matchId: match.id, autoPromptWhatsApp: true),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  /// The two candidates side by side — the same comparison התאמות uses.
  /// Agreeing to it there opens the proposal, so it does here too.
  Future<void> _comparePair(NewIdeaSuggestion idea) async {
    final bool? open = await openMatchComparison(
      context,
      source: idea.female,
      candidate: idea.male,
    );
    if (open == true && mounted) {
      await _openIdea(idea);
    }
  }

  /// "לא מתאים" is final. The pair leaves the database's suggestions for good
  /// and settles at the bottom of each side's own matches list, beside the
  /// ideas that were opened and turned down — which is where a matchmaker looks
  /// when they want to reconsider something they once ruled out.
  ///
  /// Recorded on *both* candidates, not just one. A dismissal written in one
  /// direction only would keep the pair out of one profile's list and leave it
  /// sitting at the top of the other's, and the same pair would come back round
  /// as a fresh suggestion the moment the scan started from the other side.
  Future<void> _skipIdea(NewIdeaSuggestion idea) async {
    await SuggestionDismissals.dismiss(idea.male.id, idea.female.id);
    await SuggestionDismissals.dismiss(idea.female.id, idea.male.id);
    if (!mounted) {
      return;
    }
    // The card leaving the list is the whole confirmation: a bar across the
    // bottom for a dismissal the matchmaker just chose is in the way.
    setState(() {});
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: dark
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : AppColors.primaryLight.withValues(alpha: 0.55),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.auto_awesome,
            size: 22,
            color: dark ? theme.colorScheme.primary : AppColors.primaryDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'המאגר שלך מציע רעיונות לזוגות שיכולים להתאים לפי גיל וסגנון דתי',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count רעיונות חדשים שעוד לא נפתחו',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.onOpen,
    required this.onSkip,
    required this.onComparePair,
  });

  final NewIdeaSuggestion idea;
  final VoidCallback onOpen;
  final VoidCallback onSkip;

  /// Tapping the couple opens the two cards facing each other.
  final VoidCallback onComparePair;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The whole pair tile — photos, names and reasons — opens the two
          // cards facing each other, which is the question this card asks.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onComparePair,
            child: Row(
              children: <Widget>[
                HomeCardCoupleAvatars(
                  personA: idea.female,
                  personB: idea.male,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${idea.female.fullName.trim()} & '
                        '${idea.male.fullName.trim()}',
                        maxLines: 2,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      if (idea.reasons.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          idea.reasons.join(' · '),
                          maxLines: 2,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.favorite_outline, size: 18),
                  label: const Text('פתיחת רעיון'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.brightness == Brightness.dark
                        ? theme.colorScheme.primary
                        : AppColors.primaryDark,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('לא מתאים'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'אין כרגע רעיונות חדשים',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'כשיתווספו למאגר עוד אנשים — או כשיתעדכנו פרטים בכרטיסים — '
              'יופיעו כאן זוגות שמתאימים זה לזה.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
