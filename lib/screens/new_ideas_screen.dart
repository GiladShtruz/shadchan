import 'package:flutter/material.dart';
import 'package:shadchan/widgets/sketch_actions.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "רעיונות שהמאגר מציע לך" — the screen behind the home page's second banner.
///
/// It does not invent anything: it walks the database, keeps the pairs that
/// already fit each other by the app's own matching rules, drops every pair
/// that already has an idea open or was pushed aside, and offers what is left
/// in the order the records argue for. Opening one creates a regular idea.
///
/// **It is drawn as the twin of "עוצרים רגע לחשוב על החברים".** The two are one
/// feature from where the matchmaker stands — both are the app putting people
/// in front of them that they did not go looking for — and they were arriving
/// as two different apps: one on the warm canvas with a centred bar and its
/// opening line on bare paper, this one on the theme's default page with a
/// tinted, framed banner and outlined cards. Same canvas, same bar, same
/// opening line, same unframed cards now. See `ThinkScreen`.
class NewIdeasScreen extends StatefulWidget {
  const NewIdeasScreen({super.key});

  @override
  State<NewIdeasScreen> createState() => _NewIdeasScreenState();
}

class _NewIdeasScreenState extends State<NewIdeasScreen> {
  /// Which round the list opens on.
  ///
  /// Starts where the last visit left off and moves on as it opens, so coming
  /// back tomorrow shows ten different friends rather than the same ten
  /// forever.
  late final int _batch = NewIdeaRotation.cursor;

  /// How many rounds are on screen, for the rotation cursor.
  int _roundsShown = 1;

  /// The pairs on screen, in order, as [NewIdeaSuggestions.keyOf].
  ///
  /// **The list belongs to this visit, not to the ranking.** It used to be
  /// recomputed from scratch on every change, so turning one pair down could
  /// reshuffle the whole screen — and usually brought back the same popular
  /// friend with somebody else. It is built once from the opening round, and
  /// after that only grows ("רעיונות נוספים") or has one card swapped in place
  /// ("לא מתאים"). A pair that stops being a suggestion — opened as an idea —
  /// drops out on its own. Null until the first build.
  List<String>? _shownKeys;

  /// Which side the next "לא מתאים" keeps — see
  /// [NewIdeaSuggestions.replacementFor]. Flips on every one.
  bool _keepMaleNext = true;

  @override
  void initState() {
    super.initState();
    // Recorded on the way in rather than on the way out: a matchmaker who
    // closes the app from this screen has still seen this round.
    NewIdeaRotation.setCursor(_batch + 1);
  }

  List<NewIdeaSuggestion> _ranked(
    PersonRepository personRepository,
    MatchRepository matchRepository,
  ) {
    return NewIdeaSuggestions.build(
      people: personRepository.getAll(),
      matches: matchRepository.getAll(),
      dismissedFor: SuggestionDismissals.dismissedFor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<NewIdeaSuggestion> ranked = _ranked(
      personRepository,
      matchRepository,
    );
    final List<String> shownKeys = _shownKeys ??= _openingRound(ranked);
    final Map<String, NewIdeaSuggestion> byKey = <String, NewIdeaSuggestion>{
      for (final NewIdeaSuggestion idea in ranked)
        NewIdeaSuggestions.keyOf(idea): idea,
    };
    final List<NewIdeaSuggestion> ideas = <NewIdeaSuggestion>[
      for (final String key in shownKeys)
        if (byKey[key] case final NewIdeaSuggestion idea) idea,
    ];
    final Set<String> shownSet = shownKeys.toSet();
    final bool hasMoreRounds = ranked.any(
      (NewIdeaSuggestion idea) =>
          !shownSet.contains(NewIdeaSuggestions.keyOf(idea)),
    );

    return Scaffold(
      backgroundColor: ProfilePalette.canvas(theme),
      appBar: AppBar(
        backgroundColor: ProfilePalette.canvas(theme),
        foregroundColor: ProfilePalette.text(theme),
        titleTextStyle: ProfilePalette.appBarTitleStyle(theme),
        title: const Text('רעיונות שהמאגר מציע לך'),
      ),
      body: SafeArea(
        child: ideas.isEmpty
            ? _EmptyState(theme: theme)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                itemCount: ideas.length + (hasMoreRounds ? 2 : 1),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return const _Intro();
                  }
                  if (index > ideas.length) {
                    return _MoreIdeasButton(
                      onPressed: () => _moreIdeas(ranked),
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

  /// The round this visit opens on, as keys.
  List<String> _openingRound(List<NewIdeaSuggestion> ranked) {
    final List<List<NewIdeaSuggestion>> rounds = NewIdeaSuggestions.batches(
      ranked,
    );
    if (rounds.isEmpty) {
      return <String>[];
    }
    return rounds[_batch % rounds.length]
        .map(NewIdeaSuggestions.keyOf)
        .toList();
  }

  /// Another round, added under the ones already on screen — see
  /// [NewIdeaSuggestions.nextRound].
  void _moreIdeas(List<NewIdeaSuggestion> ranked) {
    final List<String> shown = _shownKeys ?? <String>[];
    final List<NewIdeaSuggestion> round = NewIdeaSuggestions.nextRound(
      ranked,
      shownKeys: shown.toSet(),
    );
    if (round.isEmpty) {
      return;
    }
    setState(() {
      _shownKeys = <String>[...shown, ...round.map(NewIdeaSuggestions.keyOf)];
      _roundsShown++;
    });
    NewIdeaRotation.setCursor(_batch + _roundsShown);
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
      AppNotice.show(context, 'כבר קיים רעיון לזוג הזה');
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
  ///
  /// **The card is replaced where it stood**, by the next idea for one of the
  /// two — the man this time, the woman the next — so the list moves on
  /// instead of reshuffling. See [NewIdeaSuggestions.replacementFor].
  Future<void> _skipIdea(NewIdeaSuggestion idea) async {
    final OverlayState? notices = AppNotice.capture(context);
    final PersonRepository personRepository = context.read<PersonRepository>();
    final MatchRepository matchRepository = context.read<MatchRepository>();
    await SuggestionDismissals.dismiss(idea.male.id, idea.female.id);
    await SuggestionDismissals.dismiss(idea.female.id, idea.male.id);
    if (!mounted) {
      return;
    }

    final String key = NewIdeaSuggestions.keyOf(idea);
    final List<String> shown = List<String>.of(_shownKeys ?? <String>[]);
    final int index = shown.indexOf(key);
    final bool keepMale = _keepMaleNext;
    final NewIdeaSuggestion? next = NewIdeaSuggestions.replacementFor(
      _ranked(personRepository, matchRepository),
      dismissed: idea,
      keepMale: keepMale,
      shownKeys: shown.toSet(),
    );
    final String? nextKey = next == null
        ? null
        : NewIdeaSuggestions.keyOf(next);
    setState(() {
      if (index >= 0) {
        if (nextKey != null) {
          shown[index] = nextKey;
        } else {
          shown.removeAt(index);
        }
      }
      _shownKeys = shown;
      _keepMaleNext = !keepMale;
    });

    // A small banner for two seconds, with a way back. The dismissal is
    // permanent — the pair never returns as a suggestion — which is exactly why
    // a mis-tap on a button sitting beside "פתיחת רעיון" needs an answer that
    // is not "go and find the two of them and undo it by hand".
    // At the foot of the screen, where it covers nothing the reader is about
    // to look at — at the top it sat on the next card down.
    AppNotice.showOn(
      notices,
      'הרעיון הוסר',
      atBottom: true,
      duration: const Duration(seconds: 2),
      actionLabel: 'ביטול',
      onAction: () => _restoreIdea(idea, index: index, replacedBy: nextKey),
    );
  }

  /// Puts a turned-down pair back in the place it had, over the card that had
  /// taken it — that one was never judged, so it simply goes.
  Future<void> _restoreIdea(
    NewIdeaSuggestion idea, {
    required int index,
    String? replacedBy,
  }) async {
    await SuggestionDismissals.restore(idea.male.id, idea.female.id);
    await SuggestionDismissals.restore(idea.female.id, idea.male.id);
    if (!mounted) {
      return;
    }
    final String key = NewIdeaSuggestions.keyOf(idea);
    setState(() {
      final List<String> shown = List<String>.of(_shownKeys ?? <String>[]);
      final int at = replacedBy == null ? -1 : shown.indexOf(replacedBy);
      if (at >= 0) {
        shown[at] = key;
      } else if (index >= 0 && !shown.contains(key)) {
        shown.insert(index.clamp(0, shown.length), key);
      }
      _shownKeys = shown;
    });
  }
}

/// The first thing on the page: an invitation, and nothing under it.
///
/// **The same shape "עוצרים רגע לחשוב על החברים" opens with**, which is the
/// point — see `_ThinkWelcome`. It was a tinted, rounded banner with a sparkle
/// glyph and a sentence explaining the matching rules; its twin opens with one
/// warm line on bare paper, and two screens of one feature should not disagree
/// about how they say hello.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // One line, shrunk to fit rather than wrapped: broken over two lines the
    // welcome read as a heading with a stray word under it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          'כמה זוגות מהמאגר שאולי דווקא מתאימים!',
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.2,
            color: ProfilePalette.text(theme),
          ),
        ),
      ),
    );
  }
}

/// "רעיונות נוספים" — the next ten, added under these.
///
/// At the bottom of the list rather than in the app bar: it is the answer to
/// "I have read these ten", and that question is asked at the end of them. It
/// is worded as *more* rather than as a refresh, because nothing is replaced —
/// the new pairs join the list and the ones already read stay above them.
class _MoreIdeasButton extends StatelessWidget {
  const _MoreIdeasButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The same button, in the same place, as "חברים נוספים" at the foot of the
    // thinking page.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more_rounded, size: 20),
        label: const Text('רעיונות נוספים'),
        style: OutlinedButton.styleFrom(
          foregroundColor: ProfilePalette.accent(theme),
          side: BorderSide(
            color: ProfilePalette.accent(theme).withValues(alpha: 0.45),
          ),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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

    // Unframed, on the same warm surface and at the same radius as a card on
    // the thinking page: the wash is what separates it from the canvas, and an
    // outline round it was the loudest difference between two screens that are
    // meant to be one feature.
    return Material(
      color: ProfilePalette.surface(theme),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
            const SizedBox(height: 8),
            // The three answers, drawn by hand: both full cards side by side,
            // open the idea, or not suitable.
            SketchActionBar(
              onFullCard: onComparePair,
              fullCardLabel: 'השוואת כרטיסים',
              onOpenIdea: onOpen,
              onNotSuitable: onSkip,
            ),
          ],
        ),
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
