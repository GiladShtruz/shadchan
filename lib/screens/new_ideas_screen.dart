import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
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
  /// Which round of ten is on screen.
  ///
  /// Starts where the last visit left off and moves on as it opens, so coming
  /// back tomorrow shows ten different friends rather than the same ten
  /// forever. "לרעיונות נוספים" moves it by hand.
  late int _batch = NewIdeaRotation.cursor;

  @override
  void initState() {
    super.initState();
    // Recorded on the way in rather than on the way out: a matchmaker who
    // closes the app from this screen has still seen this round.
    NewIdeaRotation.setCursor(_batch + 1);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<List<NewIdeaSuggestion>> rounds = NewIdeaSuggestions.batches(
      NewIdeaSuggestions.build(
        people: personRepository.getAll(),
        matches: matchRepository.getAll(),
        dismissedFor: SuggestionDismissals.dismissedFor,
      ),
    );
    final List<NewIdeaSuggestion> ideas = rounds.isEmpty
        ? const <NewIdeaSuggestion>[]
        : rounds[_batch % rounds.length];
    final bool hasMoreRounds = rounds.length > 1;

    return Scaffold(
      appBar: AppBar(title: const Text('רעיונות שהמאגר מציע לך')),
      body: SafeArea(
        child: ideas.isEmpty
            ? _EmptyState(theme: theme)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                itemCount: ideas.length + (hasMoreRounds ? 2 : 1),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return const _Intro();
                  }
                  if (index > ideas.length) {
                    return _MoreIdeasButton(
                      onPressed: () => _nextBatch(rounds),
                    );
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

  /// Another ten. Wraps at the end rather than emptying the screen.
  void _nextBatch(List<List<NewIdeaSuggestion>> rounds) {
    setState(() => _batch = (_batch + 1) % rounds.length);
    NewIdeaRotation.setCursor(_batch + 1);
  }

  /// Opens a real proposal for the pair, after asking.
  ///
  /// [confirm] is false only when the matchmaker has *already* answered the
  /// same question: the side-by-side comparison ends in "לפתוח רעיון?" of its
  /// own, and asking twice in a row about the same two people reads as the app
  /// not having heard the first answer.
  Future<void> _openIdea(NewIdeaSuggestion idea, {bool confirm = true}) async {
    if (confirm) {
      final bool go = await ConfirmDialog.show(
        context,
        title:
            'לפתוח רעיון בין ${_shortName(idea.female)} '
            'ל־${_shortName(idea.male)}?',
        message:
            'הרעיון ייפתח ברשימת הרעיונות שלך, ותוכלו להתקדם איתו משם. '
            'אפשר לסגור אותו בכל שלב.',
        confirmText: 'פתיחת רעיון',
      );
      if (!go || !mounted) {
        return;
      }
    }

    if (!mounted) {
      return;
    }
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
    // A proposal has no page of its own any more — see the `/matches/:id`
    // redirect in `AppRouter`. What the pushed page was actually for from
    // here is the half of "opening an idea" that gets forgotten: telling
    // somebody about it. So that is what happens, in place, and this list
    // stays where it is.
    if (!mounted) {
      return;
    }
    await MatchQuickActions.promote(
      context,
      match,
      female: idea.female,
      male: idea.male,
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
      await _openIdea(idea, confirm: false);
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await SuggestionDismissals.dismiss(idea.male.id, idea.female.id);
    await SuggestionDismissals.dismiss(idea.female.id, idea.male.id);
    if (!mounted) {
      return;
    }
    setState(() {});

    // A small banner for three seconds, with a way back. The dismissal is
    // permanent — the pair never returns as a suggestion — which is exactly why
    // a mis-tap on a button sitting beside "פתיחת רעיון" needs an answer that
    // is not "go and find the two of them and undo it by hand".
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('הרעיון הוסר'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () => _restoreIdea(idea),
          ),
        ),
      );
  }

  Future<void> _restoreIdea(NewIdeaSuggestion idea) async {
    await SuggestionDismissals.restore(idea.male.id, idea.female.id);
    await SuggestionDismissals.restore(idea.female.id, idea.male.id);
    if (mounted) {
      setState(() {});
    }
  }
}

/// One line saying what this list is, and nothing about how long it is.
///
/// "המאגר מציע לך 40 רעיונות" was a number nobody could use: it was not a
/// queue to get through, it changed every time a card was edited, and its only
/// real effect was to make ten cards feel like the start of a chore.
class _Intro extends StatelessWidget {
  const _Intro();

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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "לרעיונות נוספים" — the next ten.
///
/// At the bottom of the list rather than in the app bar: it is the answer to
/// "I have read these ten", and that question is asked at the end of them. It
/// is worded as *more* rather than as a refresh, because nothing is being
/// reloaded — the list moves on to pairs that have not been shown yet.
class _MoreIdeasButton extends StatelessWidget {
  const _MoreIdeasButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('לרעיונות נוספים'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: theme.brightness == Brightness.dark
              ? theme.colorScheme.primary
              : AppColors.primaryDark,
          shape: const StadiumBorder(),
        ),
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

/// The name used in the confirmation question: a first name where there is one,
/// because "לפתוח רעיון בין רבקה ל־יוסי?" is a sentence and the same question
/// with two full names is a form.
String _shortName(Person person) {
  final String first = person.firstName.trim();
  return first.isNotEmpty ? first : person.fullName.trim();
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
