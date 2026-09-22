import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// One proposed pair on the "רעיונות חדשים" screen.
class NewIdeaSuggestion {
  const NewIdeaSuggestion({
    required this.male,
    required this.female,
    required this.score,
    required this.reasons,
    this.completeCards = 0,
  });

  final Person male;
  final Person female;

  /// How strongly the database argues for this pair. Only used for ordering.
  final int score;

  /// How many of the two have a card worth reading -- 2, 1 or 0.
  ///
  /// **The first thing the list is sorted by, above every other signal.** A
  /// pair the matchmaker can actually judge is worth more than a
  /// better-scoring pair of two blank cards: the second one cannot be acted on
  /// without opening two profiles and finding there is nothing in them. Only
  /// inside a tier does [score] decide the order.
  final int completeCards;

  /// The short, factual notes behind the pair ("אותה השקפה · שניהם מירושלים").
  final List<String> reasons;
}

/// Builds fresh proposal ideas out of the database itself.
///
/// It only ever pairs people who already fit each other by the app's own
/// matching rules (gender, religious style, age), and it never re-offers a pair
/// that already has a proposal — open, closed or rejected — or one the
/// matchmaker has already pushed aside.
abstract final class NewIdeaSuggestions {
  /// How many pairs are shown at once.
  ///
  /// Ten, not forty. A list of forty pairs is not a list of forty decisions --
  /// it is a wall, and the honest thing a matchmaker does with a wall is close
  /// it. Ten is a sitting's worth, and the refresh button is there for whoever
  /// wants another ten.
  static const int batchSize = 10;

  /// At most one idea per friend inside a single batch.
  ///
  /// **Diversity is the whole point of batching.** The same popular candidate
  /// paired with three different people is one thought shown three times, at
  /// the cost of two other friends nobody has looked at this month. Across
  /// batches they may appear again -- that is what the next batch is for.
  static const int maxPairsPerPersonPerBatch = 1;

  static List<NewIdeaSuggestion> build({
    required List<Person> people,
    required List<MatchIdea> matches,
    Set<String> Function(String personId)? dismissedFor,
    int limit = 0,
  }) {
    final List<Person> pool = people.where(_isEligible).toList();
    final List<Person> males = pool
        .where((Person p) => p.gender == Gender.male)
        .toList();
    final List<Person> females = pool
        .where((Person p) => p.gender == Gender.female)
        .toList();
    if (males.isEmpty || females.isEmpty) {
      return const <NewIdeaSuggestion>[];
    }

    final Set<String> paired = <String>{
      for (final MatchIdea match in matches)
        _pairKey(match.personAId, match.personBId),
    };
    final Map<String, int> openIdeas = <String, int>{};
    for (final MatchIdea match in matches) {
      if (match.status.isArchived) {
        continue;
      }
      for (final String id in <String>[match.personAId, match.personBId]) {
        openIdeas[id] = (openIdeas[id] ?? 0) + 1;
      }
    }

    final List<NewIdeaSuggestion> pairs = <NewIdeaSuggestion>[];
    for (final Person male in males) {
      final Set<String> dismissed =
          dismissedFor?.call(male.id) ?? const <String>{};
      for (final Person female in females) {
        if (paired.contains(_pairKey(male.id, female.id))) {
          continue;
        }
        if (dismissed.contains(female.id) ||
            (dismissedFor?.call(female.id) ?? const <String>{}).contains(
              male.id,
            )) {
          continue;
        }
        if (!MatchSuggestionUtils.isSuggestedCandidate(
          source: male,
          candidate: female,
        )) {
          continue;
        }

        pairs.add(
          _describe(
            male: male,
            female: female,
            maleOpenIdeas: openIdeas[male.id] ?? 0,
            femaleOpenIdeas: openIdeas[female.id] ?? 0,
          ),
        );
      }
    }

    // Cards first, then everything else. See [NewIdeaSuggestion.completeCards].
    pairs.sort((NewIdeaSuggestion a, NewIdeaSuggestion b) {
      final int byCards = b.completeCards.compareTo(a.completeCards);
      if (byCards != 0) {
        return byCards;
      }
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return b.female.updatedAt.compareTo(a.female.updatedAt);
    });

    // The whole ranked list by default. The screen shows one batch of it at a
    // time -- see [batches] -- and a caller that genuinely wants a ceiling
    // asks for one.
    return limit > 0 && pairs.length > limit ? pairs.sublist(0, limit) : pairs;
  }

  /// Splits the ranked list into rounds of [size], each showing every friend at
  /// most [maxPairsPerPersonPerBatch] times.
  ///
  /// **Ranking order is preserved, and nothing is thrown away.** Each pair goes
  /// into the earliest round that has room for it and does not already carry
  /// one of its two people, so the best pairs are still first, the first round
  /// still shows ten different friends, and a pair that lost its place to the
  /// diversity rule turns up in the next round rather than vanishing.
  static List<List<NewIdeaSuggestion>> batches(
    List<NewIdeaSuggestion> ranked, {
    int size = batchSize,
  }) {
    final List<List<NewIdeaSuggestion>> rounds = <List<NewIdeaSuggestion>>[];
    final List<Map<String, int>> seen = <Map<String, int>>[];

    for (final NewIdeaSuggestion pair in ranked) {
      for (int index = 0; ; index++) {
        if (index == rounds.length) {
          rounds.add(<NewIdeaSuggestion>[]);
          seen.add(<String, int>{});
        }
        final Map<String, int> counts = seen[index];
        final bool crowded =
            (counts[pair.male.id] ?? 0) >= maxPairsPerPersonPerBatch ||
            (counts[pair.female.id] ?? 0) >= maxPairsPerPersonPerBatch;
        if (rounds[index].length >= size || crowded) {
          continue;
        }
        rounds[index].add(pair);
        counts[pair.male.id] = (counts[pair.male.id] ?? 0) + 1;
        counts[pair.female.id] = (counts[pair.female.id] ?? 0) + 1;
        break;
      }
    }
    return rounds;
  }

  /// A stable name for a pair on screen, male first.
  static String keyOf(NewIdeaSuggestion idea) =>
      '${idea.male.id}|${idea.female.id}';

  /// The next round to add under what is already on screen.
  ///
  /// **Added, not swapped.** "רעיונות נוספים" used to replace the ten on screen
  /// with the next ten, so a pair somebody meant to come back to was gone the
  /// moment they asked for more. The next round is built exactly like the
  /// first — the same ranking, one idea per friend — out of whatever has not
  /// been shown yet.
  static List<NewIdeaSuggestion> nextRound(
    List<NewIdeaSuggestion> ranked, {
    required Set<String> shownKeys,
    int size = batchSize,
  }) {
    final List<List<NewIdeaSuggestion>> rounds = batches(<NewIdeaSuggestion>[
      for (final NewIdeaSuggestion idea in ranked)
        if (!shownKeys.contains(keyOf(idea))) idea,
    ], size: size);
    return rounds.isEmpty ? const <NewIdeaSuggestion>[] : rounds.first;
  }

  /// The pair that takes the place of one just turned down.
  ///
  /// **It alternates which side stays.** With [keepMale] the next idea is for
  /// the same man with somebody else; without it, for the same woman. The
  /// caller flips the side on every "לא מתאים", so turning down pair after pair
  /// moves on through both halves of the database instead of offering one
  /// popular friend again and again until something sticks.
  ///
  /// A partner who is already on screen is avoided where possible, and when the
  /// kept side has nobody left the other side is tried, then any fresh pair.
  /// Null only when nothing unseen is left.
  static NewIdeaSuggestion? replacementFor(
    List<NewIdeaSuggestion> ranked, {
    required NewIdeaSuggestion dismissed,
    required bool keepMale,
    Set<String> shownKeys = const <String>{},
  }) {
    final String dismissedKey = keyOf(dismissed);
    final List<NewIdeaSuggestion> fresh = <NewIdeaSuggestion>[
      for (final NewIdeaSuggestion idea in ranked)
        if (keyOf(idea) != dismissedKey && !shownKeys.contains(keyOf(idea)))
          idea,
    ];
    if (fresh.isEmpty) {
      return null;
    }

    final Set<String> onScreen = <String>{
      for (final String key in shownKeys)
        if (key != dismissedKey) ...key.split('|'),
    };
    bool free(String id) => !onScreen.contains(id);
    bool involves(NewIdeaSuggestion idea, String id) =>
        idea.male.id == id || idea.female.id == id;
    String partnerOf(NewIdeaSuggestion idea, String id) =>
        idea.male.id == id ? idea.female.id : idea.male.id;
    NewIdeaSuggestion? firstWhere(bool Function(NewIdeaSuggestion) test) {
      for (final NewIdeaSuggestion idea in fresh) {
        if (test(idea)) {
          return idea;
        }
      }
      return null;
    }

    final String kept = keepMale ? dismissed.male.id : dismissed.female.id;
    final String other = keepMale ? dismissed.female.id : dismissed.male.id;
    return firstWhere(
          (NewIdeaSuggestion idea) =>
              involves(idea, kept) && free(partnerOf(idea, kept)),
        ) ??
        firstWhere(
          (NewIdeaSuggestion idea) =>
              involves(idea, other) && free(partnerOf(idea, other)),
        ) ??
        firstWhere(
          (NewIdeaSuggestion idea) =>
              free(idea.male.id) && free(idea.female.id),
        ) ??
        firstWhere((NewIdeaSuggestion idea) => involves(idea, kept)) ??
        fresh.first;
  }

  static NewIdeaSuggestion _describe({
    required Person male,
    required Person female,
    required int maleOpenIdeas,
    required int femaleOpenIdeas,
  }) {
    final List<String> reasons = <String>[];
    int score = 0;

    if (maleOpenIdeas == 0 && femaleOpenIdeas == 0) {
      // Worth points and not worth a word. The line that used to be written
      // here described the absence of something rather than a reason to put
      // two people together, and it appeared on nearly every card -- which is
      // the definition of a line that says nothing.
      score += 5;
    } else if (maleOpenIdeas == 0 || femaleOpenIdeas == 0) {
      score += 2;
    }

    final String maleLevel = male.religiousLevelLabel;
    if (maleLevel.isNotEmpty && maleLevel == female.religiousLevelLabel) {
      score += 3;
      reasons.add('אותה השקפה · $maleLevel');
    }

    final String city = (male.city ?? '').trim();
    if (city.isNotEmpty && city == (female.city ?? '').trim()) {
      score += 2;
      reasons.add('שניהם מ$city');
    }

    if (male.age != null && female.age != null) {
      score += 1;
      reasons.add('גילאים ${female.age} ו-${male.age}');
    }

    final int completeCards =
        (_cardIsComplete(male) ? 1 : 0) + (_cardIsComplete(female) ? 1 : 0);
    if (completeCards == 2) {
      score += 2;
      reasons.add('לשניהם כרטיס מלא');
    }

    if (maleOpenIdeas >= 3 || femaleOpenIdeas >= 3) {
      score -= 2;
    }

    return NewIdeaSuggestion(
      male: male,
      female: female,
      score: score,
      completeCards: completeCards,
      reasons: reasons.take(3).toList(),
    );
  }

  static bool _cardIsComplete(Person person) {
    return person.age != null &&
        person.religiousLevel != null &&
        (person.description ?? '').trim().isNotEmpty;
  }

  static bool _isEligible(Person person) {
    return !person.hidden &&
        !person.needsReview &&
        !person.profileStatus.isArchived &&
        !person.profileStatus.pausesMatches &&
        person.gender != Gender.unknown;
  }

  static String _pairKey(String a, String b) {
    return a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  }
}
