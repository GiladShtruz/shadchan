import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
/// bottom — and above those, any proposal that is already open for them, which
/// is the one thing that outranks a pair the database imagined. Tapping a
/// suggestion opens the two cards facing each other; tapping an open idea goes
/// to it on הרעיונות שלי. At the foot of the card, under a hairline,
/// "התאמות נוספות" opens the rest and "אחשוב עליו בהזדמנות אחרת" puts this
/// friend away for a few weeks.
///
/// Only friends marked פנוי appear here at all: the page asks who somebody
/// could go with, and that is not a question about a person who is out with
/// somebody else.
class ThinkScreen extends StatefulWidget {
  const ThinkScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ThinkScreen(),
      ),
    );
  }

  // A tap used to push the profile *and* the matches list on top of it, from
  // one gesture. The card splits them now: the photograph is the profile, the
  // words beside it are the matches. See `_PersonThought`.

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
  /// not move under the finger.
  late final int _cursor;

  /// Friends put away with "אחשוב עליו בהזדמנות אחרת", read once for the same
  /// reason. Added to as the screen is used, so a card leaves the moment it is
  /// tapped without the whole list re-ranking underneath.
  late final Set<String> _later = <String>{...ThinkLater.activeIds()};

  /// Friends taken off *this* visit's page, by id.
  ///
  /// **Held apart from [_later] because the list must not move.** Putting one
  /// friend away used to be enough to re-rank and re-rotate everything — a
  /// different cursor over a shorter list is a different page — so answering
  /// one card replaced every card under it. The rows are decided once, into
  /// [_ranked], and this is what quietly takes one of them out.
  final Set<String> _removed = <String>{};

  /// The friends this visit is showing, computed once and then left alone.
  List<_ThinkRow>? _ranked;

  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    // **Advanced on the way in, not on the way out.** The next visit used to
    // be moved on from `dispose`, which is a callback the screen does not
    // always get to run — and when it did not, the page opened on exactly the
    // faces it had opened on before. Taken here it is spent the moment the
    // screen exists, so no two visits in a row start in the same place.
    _cursor = ThinkRotation.cursor;
    ThinkRotation.advance(_pageSize);
  }

  @override
  void dispose() {
    // Whatever was read past the first page counts too, so "חברים נוספים"
    // does not hand the next visit people who were already looked at.
    ThinkRotation.advance(_shown - _pageSize);
    super.dispose();
  }

  void _thinkLater(Person person) {
    ThinkLater.remember(person.id);
    // Only this friend leaves, and only from this page: `_removed` is read by
    // the already-built list rather than by the ranking behind it.
    setState(() {
      _later.add(person.id);
      _removed.add(person.id);
    });
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
          setState(() {
            _later.remove(person.id);
            _removed.remove(person.id);
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    // **Only friends who are actually available.** The page asks "who could
    // this one go with?", and asking it about somebody who is out with
    // somebody else, on a break or already married is a question with no
    // answer — the matchmaker reads the card, works out why it cannot be acted
    // on, and moves on. `pausesMatches` and `isArchived` between them cover
    // תפוס, בהפסקה and מזל טוב.
    final List<Person> people = personRepository
        .getAll()
        .where(
          (Person person) =>
              !person.hidden &&
              !person.needsReview &&
              person.profileStatus == ProfileStatus.available,
        )
        .toList();
    final List<MatchIdea> matches = matchRepository.getAll();

    // The rows this visit shows are decided once. Rebuilding them on every
    // `setState` is what made putting one friend away reshuffle the page —
    // a shorter list rotates to a different place. See [_removed].
    final List<_ThinkRow> ranked = _ranked ??= ThinkRotation.rotate(
      _withOccasionalStranger(
        HomeSuggestions.build(
          people: people,
          matches: matches,
          events: personRepository.getAllEvents(),
          activity: RecentActivityStore.instance.entries,
          limit: 60,
        ),
        people,
      ).where((_ThinkRow row) => !_later.contains(row.person.id)).toList(),
      _cursor,
    );
    final List<_ThinkRow> live = ranked
        .where((_ThinkRow row) => !_removed.contains(row.person.id))
        .toList();
    final List<_ThinkRow> rows = live.take(_shown).toList();
    final bool hasMore = live.length > rows.length;
    final _MatchLookup lookup = _MatchLookup(people: people, matches: matches);

    return Scaffold(
      backgroundColor: ProfilePalette.canvas(theme),
      appBar: AppBar(
        backgroundColor: ProfilePalette.canvas(theme),
        foregroundColor: ProfilePalette.text(theme),
        // Lighter than the page's own headings, and a size down. The bar was
        // set in the same black weight as a title, which on a screen whose
        // whole point is that nothing on it is a task made the top of it read
        // as an instruction.
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: ProfilePalette.muted(theme),
        ),
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
                    openIdeas: lookup.openIdeasFor(row.person),
                    candidates: lookup.topFor(row.person),
                    // The photograph goes to the person's own card; everything
                    // else on the tile asks the page's question, which is who
                    // they could go with.
                    onOpenProfile: () => _openProfile(row.person.id),
                    onTap: () => openSuggestionsFor(context, row.person.id),
                    onOpenIdea: (_OpenIdea idea) =>
                        context.push('/matches/${idea.match.id}'),
                    onCandidate: (Person candidate) =>
                        _considerPair(row.person, candidate),
                    onLater: () => _thinkLater(row.person),
                  );
                },
              ),
      ),
    );
  }

  /// One friend's own card, and nothing pushed on top of it.
  ///
  /// The tile used to open the profile *and* the matches list over it from a
  /// single tap, which is two destinations for one gesture. The face is the
  /// profile; the rest of the tile is the matches.
  Future<void> _openProfile(String personId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PersonDetailScreen(personId: personId),
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

/// A proposal already open for the friend on the card, and who it is with.
class _OpenIdea {
  const _OpenIdea({required this.match, required this.other});

  final MatchIdea match;
  final Person other;
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
  /// meant to be read in a second, and three is what fits across a narrow
  /// phone. "התאמות נוספות" under them opens the full list.
  static const int shown = 3;

  final List<Person> people;
  final List<MatchIdea> matches;

  final Map<String, List<Person>> _cache = <String, List<Person>>{};
  final Map<String, List<_OpenIdea>> _openCache = <String, List<_OpenIdea>>{};

  /// The proposals already open for this friend, with the other side named.
  ///
  /// **They come before the suggestions on the card.** A friend with a live
  /// proposal in flight is not somebody to think of new pairs for — they are
  /// somebody with a pair already, waiting on an answer — and the page was
  /// showing them three fresh faces while saying nothing about the idea that
  /// already exists. Newest first, capped at three for the same reason the
  /// suggestions are.
  List<_OpenIdea> openIdeasFor(Person person) {
    return _openCache.putIfAbsent(person.id, () {
      final List<_OpenIdea> open = <_OpenIdea>[];
      for (final MatchIdea match in matches) {
        if (match.status.isArchived) {
          continue;
        }
        final String? otherId = match.personAId == person.id
            ? match.personBId
            : match.personBId == person.id
            ? match.personAId
            : null;
        if (otherId == null) {
          continue;
        }
        for (final Person other in people) {
          if (other.id == otherId) {
            open.add(_OpenIdea(match: match, other: other));
            break;
          }
        }
      }
      open.sort(
        (_OpenIdea a, _OpenIdea b) =>
            b.match.updatedAt.compareTo(a.match.updatedAt),
      );
      return open.take(shown).toList();
    });
  }

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

/// One friend to think about, and the people they could go with.
///
/// **One person is the subject of the card, not one row of a list.** The photo
/// and the name lead it and are the largest thing on it, and nothing shares
/// that line; under them is the one sentence saying why this friend is worth a
/// thought *today*; then any proposal already open for them; then the three
/// matches the database found, each as a small card with a face and a full
/// name; and under those, behind a hairline, the card's two answers.
///
/// **The face and the words beside it go to different places.** A photograph
/// means "this person's card" everywhere else in the app, and the rest of the
/// heading asks the page's own question, which is who they could go with. One
/// tap used to push both, one on top of the other.
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
    required this.openIdeas,
    required this.candidates,
    required this.onOpenProfile,
    required this.onTap,
    required this.onOpenIdea,
    required this.onCandidate,
    required this.onLater,
  });

  final Person person;
  final String reason;

  /// The proposals already open for this friend. Drawn above the suggestions,
  /// because an idea that exists outranks one the database imagined.
  final List<_OpenIdea> openIdeas;

  /// At most [_MatchLookup.shown]. Empty for a friend with nobody to pair them
  /// with yet, and the card says so in a line instead of drawing empty chips.
  final List<Person> candidates;

  /// The photograph, and only the photograph: this friend's own card.
  final VoidCallback onOpenProfile;

  /// Opens every possible match for this friend — the name, the rest of the
  /// heading and "התאמות נוספות" all lead here, because they are all asking the
  /// same question.
  final VoidCallback onTap;

  /// Goes straight to a proposal that already exists, on הרעיונות שלי.
  final ValueChanged<_OpenIdea> onOpenIdea;

  final ValueChanged<Person> onCandidate;

  /// "אחשוב עליו בהזדמנות אחרת" — takes this friend off the page for a few
  /// weeks.
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
            //
            // **Two targets on one line, and the split is deliberate.** The
            // face opens the person's own card — which is what a photograph
            // means everywhere else in the app — and the words beside it open
            // the question this page is asking, which is who they could go
            // with. One tap used to do both, pushing the profile and then the
            // matches on top of it.
            Row(
              children: <Widget>[
                InkWell(
                  onTap: onOpenProfile,
                  customBorder: const CircleBorder(),
                  child: PersonAvatar(person: person, radius: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
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
                ),
              ],
            ),
            // The proposals that already exist, above the ones the database
            // imagined: a friend waiting on an answer is not a friend to think
            // of new pairs for. Each one goes straight to that proposal.
            if (openIdeas.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                openIdeas.length == 1 ? 'רעיון פתוח' : 'רעיונות פתוחים',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ProfilePalette.accent(theme),
                ),
              ),
              const SizedBox(height: 4),
              IntrinsicHeight(
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < openIdeas.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: i == openIdeas.length - 1 ? 0 : 6,
                          ),
                          child: _CandidateChip(
                            person: openIdeas[i].other,
                            status: openIdeas[i].match.status.stateLabel,
                            onTap: () => onOpenIdea(openIdeas[i]),
                          ),
                        ),
                      ),
                    // Fewer than three open ideas leaves the row ragged
                    // otherwise, and a half-width tile beside two full ones
                    // reads as a tile that failed to load.
                    for (int i = openIdeas.length; i < 3; i++)
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Named only when there is something above it to be told apart
            // from. On a card with no open proposal the row of faces is the
            // only row there is, and a heading over the one thing on a card is
            // a label on a box.
            if (openIdeas.isNotEmpty) ...<Widget>[
              Text(
                'התאמות אפשריות',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ProfilePalette.muted(theme),
                ),
              ),
              const SizedBox(height: 4),
            ],
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
            const SizedBox(height: 6),
            _ThoughtActions(onMore: onTap, onSkip: onLater),
          ],
        ),
      ),
    );
  }
}

/// The two answers the card offers: centred at its foot, under a hairline.
///
/// **A rule above them, and the middle of the card under them.** Pinned to the
/// reading edge the pair read as two more links belonging to the row of faces
/// directly above; a thin line and a centred pair say instead "this is what
/// the card asks of you", which is what they are. Still small and still quiet
/// — the faces are the card, and these are the two ways out of it.
///
/// **"דלג" became "אחשוב עליו בהזדמנות אחרת".** "דלג" is what you do to an
/// advert. What actually happens is a postponement — the friend comes back in
/// a few weeks — and saying so is what stops the button feeling like a
/// dismissal of somebody.
class _ThoughtActions extends StatelessWidget {
  const _ThoughtActions({required this.onMore, required this.onSkip});

  /// Every possible match for this friend, not only the three shown.
  final VoidCallback onMore;

  /// The friend leaves this page for a few weeks rather than being dismissed.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    ButtonStyle style(Color ink) => TextButton.styleFrom(
      foregroundColor: ink,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
      textStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Divider(
          height: 9,
          thickness: 1,
          color: ProfilePalette.muted(theme).withValues(alpha: 0.18),
        ),
        // Side by side while both fit, stacked on a narrow phone at a large
        // system font — "אחשוב עליו בהזדמנות אחרת" is a long label and must
        // never be cut down to "אחשוב עליו…".
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton(
              onPressed: onMore,
              style: style(ProfilePalette.accent(theme)),
              child: const Text('התאמות נוספות'),
            ),
            TextButton(
              onPressed: onSkip,
              style: style(ProfilePalette.muted(theme)),
              child: const Text('אחשוב עליו בהזדמנות אחרת'),
            ),
          ],
        ),
      ],
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
  const _CandidateChip({
    required this.person,
    required this.onTap,
    this.status,
  });

  final Person person;
  final VoidCallback onTap;

  /// Where the proposal stands, for the tiles that stand for one that already
  /// exists. Null for a suggestion, which is not a proposal and has no status.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = person.fullName.trim().isNotEmpty
        ? person.fullName.trim()
        : person.firstName.trim();
    final String? state = status;

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
              if (state != null)
                Text(
                  state,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: ProfilePalette.accent(theme),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first thing on the page: an invitation, and nothing under it.
///
/// **It stopped explaining itself.** The line used to be a question followed by
/// two sentences describing what the screen does and which buttons it has —
/// which is an instruction manual at the top of a page whose whole point is
/// that nothing on it is a task.
///
/// **And it stopped shouting.** What was left was still set as a heavy black
/// heading, the largest and darkest thing on the page, which is the wrong
/// voice for an invitation: this is somebody being told their friends would be
/// glad of a thought, not a section title. Set in the page's warm accent at a
/// size down, with a small mark in front of it, it reads the way it is meant.
class _ThinkWelcome extends StatelessWidget {
  const _ThinkWelcome();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color ink = ProfilePalette.accent(theme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.favorite_rounded, size: 16, color: ink),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'חברים שלך שישמחו שתחשוב בשבילם!',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: ink,
              ),
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
