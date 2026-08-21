import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_suggestions.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// "עוצרים רגע לחשוב על החברים" — friends, one after another, each with the
/// reason they came up.
///
/// This page is the *whole* of that idea. The home screen shows only the
/// banner: no faces, no names, no count. Putting people in front of the
/// matchmaker on the landing page turns a moment of reflection into another
/// queue to get through, and the point of this is the opposite — it is here
/// when there is room to think and invisible when there is not.
///
/// There is no session here either: no timer, no "5 people left", no progress.
/// Thinking about one person and closing the screen is a complete use of it.
///
/// **One friend per card, with the answer under the question.** Each card puts
/// one person's face and name at the top, says in one line why they are worth a
/// thought today, and then shows the three people the database thinks could
/// suit them — a face and a name each, in one compact row. Tapping one opens
/// the two cards facing each other; "לכל ההתאמות" opens the rest. The card is
/// held to two short rows on purpose: the screen is for running an eye over
/// many friends, so nothing on it is allowed to grow with its content.
class ThinkScreen extends StatefulWidget {
  const ThinkScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ThinkScreen(),
      ),
    );
  }

  /// Tapping a person opens the question this page is asking — "who could this
  /// one go with?" — which is the matches screen, not the profile.
  ///
  /// The profile is pushed underneath it rather than skipped, so backing out of
  /// the matches lands on the person's own card and backing out again returns
  /// here. That is the route a matchmaker actually walks: consider the pairs,
  /// then look at who this person is, then move on to the next thought.
  static void openPerson(BuildContext context, String personId) {
    final NavigatorState navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PersonDetailScreen(personId: personId),
      ),
    );
    openSuggestionsFor(context, personId);
  }

  @override
  State<ThinkScreen> createState() => _ThinkScreenState();
}

class _ThinkScreenState extends State<ThinkScreen> {
  /// Fixed for the life of the screen so the list does not reshuffle under the
  /// finger while it is being scrolled.
  final int _seed = DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<Person> people = personRepository
        .getAll()
        .where((Person person) => !person.hidden && !person.needsReview)
        .toList();
    final List<MatchIdea> matches = matchRepository.getAll();

    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: people,
      matches: matches,
      events: personRepository.getAllEvents(),
      activity: RecentActivityStore.instance.entries,
      limit: 60,
    );
    final List<_ThinkRow> rows = _withOccasionalStranger(suggestions, people);
    final _MatchLookup lookup = _MatchLookup(people: people, matches: matches);

    return Scaffold(
      backgroundColor: ProfilePalette.canvas(theme),
      appBar: AppBar(
        backgroundColor: ProfilePalette.canvas(theme),
        foregroundColor: ProfilePalette.text(theme),
        titleTextStyle: ProfilePalette.appBarTitleStyle(theme),
        title: const Text('עוצרים רגע לחשוב על החברים'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'כשיהיו במאגר עוד חברים, כאן יהיה על מי לחשוב.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: ProfilePalette.muted(theme),
                    ),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final _ThinkRow row = rows[index];
                  return _PersonThought(
                    person: row.person,
                    reason: row.reason,
                    candidates: lookup.topFor(row.person),
                    onTap: () => ThinkScreen.openPerson(context, row.person.id),
                    onCandidate: (Person candidate) =>
                        _considerPair(row.person, candidate),
                  );
                },
              ),
      ),
    );
  }

  /// The two cards facing each other, and a proposal if the matchmaker agrees.
  ///
  /// The same comparison the suggestions list and "רעיונות חדשים" open, so a
  /// pair considered from here goes through exactly the route it would
  /// anywhere else.
  Future<void> _considerPair(Person person, Person candidate) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? existing = matchRepository.findExisting(
      person.id,
      candidate.id,
    );
    if (existing != null) {
      // The pair already has a proposal, so there is nothing to decide — only
      // the two cards to read against each other, which is what the proposal
      // screen was mostly used for before it was folded into the list.
      await openMatchComparison(
        context,
        source: person,
        candidate: candidate,
        showOpenIdeaAction: false,
      );
      return;
    }

    final bool? open = await openMatchComparison(
      context,
      source: person,
      candidate: candidate,
    );
    if (open != true || !mounted) {
      return;
    }
    final MatchIdea? created = await matchRepository.create(
      person.gender == Gender.male ? person.id : candidate.id,
      person.gender == Gender.male ? candidate.id : person.id,
    );
    if (created == null || !mounted) {
      return;
    }
    await MatchQuickActions.promote(
      context,
      created,
      female: person.gender == Gender.male ? candidate : person,
      male: person.gender == Gender.male ? person : candidate,
    );
    if (mounted) {
      setState(() {});
    }
  }

  /// Every so often, someone with no particular reason at all.
  ///
  /// A list built only from rules keeps returning the same corner of the
  /// database. One genuinely random face every few rows is what opens a
  /// direction nobody was looking for.
  List<_ThinkRow> _withOccasionalStranger(
    List<HomeSuggestion> suggestions,
    List<Person> people,
  ) {
    final List<_ThinkRow> rows = <_ThinkRow>[
      for (final HomeSuggestion suggestion in suggestions)
        _ThinkRow(person: suggestion.person, reason: suggestion.reason),
    ];
    if (people.length < 6) {
      return rows;
    }

    final math.Random random = math.Random(_seed);
    final Set<String> shown = rows
        .map((_ThinkRow row) => row.person.id)
        .toSet();
    final List<Person> strangers = people
        .where((Person person) => !shown.contains(person.id))
        .toList();
    if (strangers.isEmpty) {
      return rows;
    }
    strangers.shuffle(random);

    final List<_ThinkRow> mixed = <_ThinkRow>[];
    int next = 0;
    for (int i = 0; i < rows.length; i++) {
      mixed.add(rows[i]);
      if ((i + 1) % 7 == 0 && next < strangers.length) {
        mixed.add(
          _ThinkRow(
            person: strangers[next++],
            reason: 'סתם ככה — אולי דווקא עכשיו יעלה הרעיון הנכון',
          ),
        );
      }
    }
    return mixed;
  }
}

class _ThinkRow {
  const _ThinkRow({required this.person, required this.reason});

  final Person person;
  final String reason;
}

/// Who each friend could go with, worked out once for the whole screen.
///
/// **Built once and cached per person**, because the naive version is a scan of
/// the whole database inside a list builder — sixty rows times a few hundred
/// friends, re-run on every scroll frame. The answer for one person does not
/// change while the screen is open, so it is computed the first time a row
/// asks for it and kept.
class _MatchLookup {
  _MatchLookup({required this.people, required this.matches});

  /// Three, and no more. The point of this screen is to move quickly over many
  /// friends; a fourth face is another thing to weigh up on a card that is
  /// meant to be read in a second, and three chips are what fits across a
  /// narrow phone beside "לכל ההתאמות", which opens the full list.
  static const int shown = 3;

  final List<Person> people;
  final List<MatchIdea> matches;

  final Map<String, List<Person>> _cache = <String, List<Person>>{};

  List<Person> topFor(Person person) {
    return _cache.putIfAbsent(person.id, () {
      if (person.gender == Gender.unknown) {
        return const <Person>[];
      }
      final Set<String> alreadyPaired = <String>{
        for (final MatchIdea match in matches)
          if (match.personAId == person.id)
            match.personBId
          else if (match.personBId == person.id)
            match.personAId,
      };
      final Set<String> dismissed = SuggestionDismissals.dismissedFor(
        person.id,
      );

      final List<Person> candidates =
          people
              .where(
                (Person other) =>
                    other.id != person.id &&
                    !alreadyPaired.contains(other.id) &&
                    !dismissed.contains(other.id) &&
                    !other.profileStatus.pausesMatches &&
                    MatchSuggestionUtils.matchesOwnPreferences(
                      source: person,
                      candidate: other,
                    ),
              )
              .toList()
            // The card edited most recently first, matching the order the full
            // matches list uses — the same people in the same order, just fewer.
            ..sort((Person a, Person b) => b.updatedAt.compareTo(a.updatedAt));

      return candidates.take(shown).toList();
    });
  }
}

/// One friend to think about, and the three people they could go with.
///
/// **One person is the subject of the card, not one row of a list.** The photo
/// and the name lead it and are the largest thing on it; under them is the one
/// sentence saying why this friend is worth a thought *today*; under that, the
/// three matches the database found, each as a small chip with a face and a
/// full name over two lines; and at the end, the way into all of them.
///
/// **Still sized to be scrolled through.** The screen exists to move an eye
/// over many friends, so the card is two short rows and never more: the name is
/// one line, the reason is one line, the matches are one row of chips. Nothing
/// here grows with its content — a long name and a long reason are clamped, not
/// given a second line, because a card that is tall for one friend is a card
/// that shows six friends where it could show ten.
class _PersonThought extends StatelessWidget {
  const _PersonThought({
    required this.person,
    required this.reason,
    required this.candidates,
    required this.onTap,
    required this.onCandidate,
  });

  final Person person;
  final String reason;

  /// At most [_MatchLookup.shown]. Empty for a friend with nobody to pair them
  /// with yet, and the card says so in a line instead of drawing empty chips.
  final List<Person> candidates;

  /// Opens every possible match for this friend — the name, the photo and
  /// "לכל ההתאמות" all lead here, because they are all asking the same
  /// question.
  final VoidCallback onTap;

  final ValueChanged<Person> onCandidate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: ProfilePalette.surface(theme),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The friend: face, name, and the reason this is the moment.
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: <Widget>[
                  PersonAvatar(person: person, radius: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          person.fullName.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: ProfilePalette.text(theme),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ProfilePalette.muted(theme),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // The matches, and the way to the rest of them, on one line.
            Row(
              children: <Widget>[
                if (candidates.isEmpty)
                  Expanded(
                    child: Text(
                      'עוד לא נמצאו התאמות מתאימות במאגר',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ProfilePalette.muted(theme),
                      ),
                    ),
                  )
                else
                  for (final Person candidate in candidates)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: _CandidateChip(
                          person: candidate,
                          onTap: () => onCandidate(candidate),
                        ),
                      ),
                    ),
                _AllMatchesButton(onTap: onTap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One possible match: a face and a name, small enough that three of them fit
/// across a narrow phone.
///
/// Tapping it opens the two cards facing each other — the same comparison
/// "רעיונות חדשים" and the matches list open, so a pair considered from here
/// goes through exactly the route it would anywhere else.
class _CandidateChip extends StatelessWidget {
  const _CandidateChip({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // First name *and* surname. A database has four people called אסתר in it
    // by the time it is useful, and a chip that only says "אסתר" asks the
    // matchmaker to tap it to find out which one is being suggested.
    final String name = person.fullName.trim().isNotEmpty
        ? person.fullName.trim()
        : person.firstName.trim();

    return Material(
      color: ProfilePalette.canvas(theme),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 5, 6, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PersonAvatar(person: person, radius: 13),
              const SizedBox(width: 6),
              Flexible(
                // Two lines, so "שם פרטי שם משפחה" fits three across a narrow
                // phone without either half being cut to an ellipsis.
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: ProfilePalette.text(theme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "לכל ההתאמות" — small, last, and never competing with the three faces
/// beside it.
class _AllMatchesButton extends StatelessWidget {
  const _AllMatchesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: ProfilePalette.muted(theme),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      child: const Text('לכל ההתאמות'),
    );
  }
}
