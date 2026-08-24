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
import 'package:shadchan/utils/think_rotation.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/widgets/app_notice.dart';
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
/// suit them — a face and a full name each, as three small cards across the
/// bottom. Tapping one opens the two cards facing each other; "לכל ההתאמות",
/// beside the friend's own name, opens the rest. The card is held to two short
/// rows on purpose: the screen is for running an eye over many friends, so
/// nothing on it is allowed to grow with its content.
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

  /// How many friends one page of this screen shows, and how many each press of
  /// "חברים נוספים" adds.
  ///
  /// **Ten, and not "all of them".** The page used to draw sixty cards in one
  /// scroll, which turns a moment of reflection into a queue to get through —
  /// and a queue nobody finishes is a queue nobody starts. Ten is a number a
  /// person can actually think about, and the button underneath says plainly
  /// that there are more when there are.
  static const int _pageSize = 10;

  /// Where this visit entered the ranked list. Read once, so the rotation does
  /// not move under the finger, and advanced on the way out so the *next* visit
  /// opens on different people.
  final int _cursor = ThinkRotation.cursor;

  /// Friends put away with "אחשוב עליו בהמשך", read once for the same reason.
  /// Added to as the screen is used, so a card leaves the moment it is tapped
  /// without the whole list re-ranking underneath.
  late final Set<String> _later = <String>{...ThinkLater.activeIds()};

  int _shown = _pageSize;

  @override
  void dispose() {
    // The next visit starts where this one stopped reading, so the page turns
    // the database over instead of greeting everybody with the same faces.
    ThinkRotation.advance(_shown);
    super.dispose();
  }

  void _thinkLater(Person person) {
    ThinkLater.remember(person.id);
    setState(() => _later.add(person.id));
    // An undo rather than a confirmation: putting somebody off is a one-tap
    // decision that should stay one tap, and a mis-tap here quietly hides a
    // friend for a month.
    AppNotice.show(
      context,
      person.gender == Gender.female
          ? 'נחשוב עליה שוב בהמשך'
          : 'נחשוב עליו שוב בהמשך',
      actionLabel: 'ביטול',
      onAction: () {
        ThinkLater.forget(person.id);
        if (mounted) {
          setState(() => _later.remove(person.id));
        }
      },
    );
  }

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
    // Ranked, then salted with the occasional stranger, then rotated to where
    // this visit starts, and finally cut to the page the reader has asked for.
    final List<_ThinkRow> ranked = ThinkRotation.rotate(
      _withOccasionalStranger(
        suggestions,
        people,
      ).where((_ThinkRow row) => !_later.contains(row.person.id)).toList(),
      _cursor,
    );
    final List<_ThinkRow> rows = ranked.take(_shown).toList();
    final bool hasMore = ranked.length > rows.length;
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
                    _later.isEmpty
                        ? 'כשיהיו במאגר עוד חברים, כאן יהיה על מי לחשוב.'
                        : 'עברת על כולם להיום. מי שסימנת "אחשוב עליו בהמשך" '
                              'יחזור לכאן בעוד כמה שבועות.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: ProfilePalette.muted(theme),
                    ),
                  ),
                ),
              )
            // One list, with the welcome as its first item and the way to more
            // friends as its last: a header pinned outside the scroll would
            // hold a full line of type on screen for the whole page, and the
            // greeting is worth reading once, not permanently.
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                itemCount: rows.length + 2,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return const _ThinkWelcome();
                  }
                  if (index == rows.length + 1) {
                    return _MoreFriendsFooter(
                      hasMore: hasMore,
                      onMore: () => setState(() => _shown += _pageSize),
                    );
                  }
                  final _ThinkRow row = rows[index - 1];
                  return _PersonThought(
                    person: row.person,
                    reason: row.reason,
                    candidates: lookup.topFor(row.person),
                    onTap: () => ThinkScreen.openPerson(context, row.person.id),
                    onCandidate: (Person candidate) =>
                        _considerPair(row.person, candidate),
                    onLater: () => _thinkLater(row.person),
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
/// and the name lead it and are the largest thing on it, with the way into all
/// the matches at the end of that same line; under them is the one sentence
/// saying why this friend is worth a thought *today*; under that, the three
/// matches the database found, each as a small card with a face and a full
/// name.
///
/// **Still sized to be scrolled through — but the reason is never cut.** The
/// screen exists to move an eye over many friends, so the name is one line and
/// the matches are one row of tiles. The reason is the exception: it is the
/// sentence that answers "why am I looking at this person", and clamped to one
/// line it was regularly ellipsized mid-clause, which turns the answer into a
/// riddle. It wraps to as many lines as it needs; the couple of pixels that
/// costs on some cards buys the only text on the card nobody can do without.
class _PersonThought extends StatelessWidget {
  const _PersonThought({
    required this.person,
    required this.reason,
    required this.candidates,
    required this.onTap,
    required this.onCandidate,
    required this.onLater,
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

  /// "אחשוב עליו בהמשך" — takes this friend off the page for a few weeks.
  ///
  /// **The card needed a third answer.** Until now a friend could be opened or
  /// scrolled past, and scrolling past leaves them exactly where they were, at
  /// the top of the next visit. This is the honest middle: not "no", not "now",
  /// but "not today" — and the app remembers it, which is the whole difference
  /// between a list that gets worked through and one that is scrolled through.
  final VoidCallback onLater;

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
                        const SizedBox(height: 2),
                        // The whole sentence, however many lines it takes.
                        // Clamped to one line it was routinely cut mid-clause
                        // — "יש במאגר 7 אנשים שעשויים…" — and the reason this
                        // person is on the screen at all is the one thing on
                        // the card that has to be read, not guessed at.
                        Text(
                          reason,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ProfilePalette.muted(theme),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Up here rather than at the end of the row of faces below.
                  // Those now carry a full name each, and the width that
                  // little button was taking is exactly what the names needed.
                  _AllMatchesButton(onTap: onTap),
                  // Deliberately an icon and not a third word on a line that
                  // already carries a name and a link: putting somebody off is
                  // the quietest of the card's three answers and should read
                  // that way.
                  _ThinkLaterButton(person: person, onTap: onLater),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // The matches, three across. Every tile is exactly one line of
            // name tall now (see `_CandidateChip`), so the row is level by
            // construction; `IntrinsicHeight` stays only to hold that true if
            // a tile ever grows something else.
            IntrinsicHeight(
              child: Row(
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
                    for (int i = 0; i < candidates.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: i == candidates.length - 1 ? 0 : 6,
                          ),
                          child: _CandidateChip(
                            person: candidates[i],
                            onTap: () => onCandidate(candidates[i]),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One possible match: a face and as much of their name as one line holds.
///
/// **The name is the full name, and it is exactly one line.** Showing only the
/// first name is unambiguous in a database of thirty friends and useless in one
/// of three hundred — half the point of this row is knowing *which* יוסי the app
/// means. But letting it wrap to a second line made the tile — and with it the
/// whole card — taller for one friend than for the next, and this is a screen
/// built to be run down with an eye. So the line never wraps and never grows the
/// tile: it shows the full name where that fits and gives up the end of the
/// surname where it does not, which still leaves "יוסי פרידמ…" — a first name
/// and enough of the family name to pick the right person out.
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
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PersonAvatar(person: person, radius: 17),
              const SizedBox(height: 5),
              Text(
                name,
                textAlign: TextAlign.center,
                // One line, and what gives way is the end of it: a name cut at
                // the end still identifies somebody, and a name cut at the
                // start does not.
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: ProfilePalette.text(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "לכל ההתאמות" — small, quiet, and never competing with the name it sits
/// beside.
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

/// "על מי אנחנו חושבים היום?" — the first thing on the page.
///
/// **A question, not a heading.** The bar above says what the screen is; this
/// says what it is *for*, and it asks rather than instructs, because nothing on
/// this page is a task. One warm line under it explains the only thing about
/// the page that is not obvious: that a friend can be put off without being
/// dismissed.
class _ThinkWelcome extends StatelessWidget {
  const _ThinkWelcome();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'על מי אנחנו חושבים היום?',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.2,
              color: ProfilePalette.text(theme),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'כמה חברים מהמאגר, והסיבה שכל אחד מהם עלה עכשיו. '
            'אפשר לפתוח, ואפשר לסמן "אחשוב עליו בהמשך".',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ProfilePalette.muted(theme),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The foot of the page: another ten friends, or the line that says there are
/// no more.
///
/// **The page ends in a sentence either way.** A list that simply stops leaves
/// the reader wondering whether it ran out or ran short, and on a screen whose
/// whole promise is "there is always somebody worth a thought" that is the one
/// ambiguity worth spending a line on.
class _MoreFriendsFooter extends StatelessWidget {
  const _MoreFriendsFooter({required this.hasMore, required this.onMore});

  final bool hasMore;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
        child: Text(
          'זה כל מי שעלה הפעם. בכניסה הבאה יחכו כאן חברים אחרים.',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ProfilePalette.muted(theme),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: OutlinedButton.icon(
        onPressed: onMore,
        icon: const Icon(Icons.expand_more_rounded, size: 20),
        label: const Text('חברים נוספים'),
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

/// "אחשוב עליו בהמשך", as a small clock on the friend's own line.
class _ThinkLaterButton extends StatelessWidget {
  const _ThinkLaterButton({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool female = person.gender == Gender.female;

    return IconButton(
      onPressed: onTap,
      tooltip: female ? 'אחשוב עליה בהמשך' : 'אחשוב עליו בהמשך',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(
        Icons.schedule_rounded,
        size: 19,
        color: ProfilePalette.muted(theme),
      ),
    );
  }
}
