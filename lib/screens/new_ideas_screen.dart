import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
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
      appBar: AppBar(title: const Text('רעיונות חדשים')),
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
                    onOpenPerson: (Person person) =>
                        context.push('/people/${person.id}'),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _openIdea(NewIdeaSuggestion idea) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
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
    context.push('/matches/${match.id}?justCreated=true');
  }

  Future<void> _skipIdea(NewIdeaSuggestion idea) async {
    await SuggestionDismissals.dismiss(idea.male.id, idea.female.id);
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('הרעיון הוסר מהרשימה'),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () async {
              await SuggestionDismissals.restore(idea.male.id, idea.female.id);
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
      );
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
                  'המאגר שלך מציע $count רעיונות',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'זוגות שמתאימים לפי גיל והשקפה ושעוד לא נפתח להם רעיון',
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
    required this.onOpenPerson,
  });

  final NewIdeaSuggestion idea;
  final VoidCallback onOpen;
  final VoidCallback onSkip;
  final void Function(Person person) onOpenPerson;

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
          Row(
            children: <Widget>[
              GestureDetector(
                onTap: () => onOpenPerson(idea.female),
                child: HomeCardCoupleAvatars(
                  personA: idea.female,
                  personB: idea.male,
                  radius: 24,
                ),
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
                child: const Text('לא עכשיו'),
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
