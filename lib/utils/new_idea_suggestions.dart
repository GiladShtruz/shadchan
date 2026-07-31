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
  });

  final Person male;
  final Person female;

  /// How strongly the database argues for this pair. Only used for ordering.
  final int score;

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
  /// How many pairs the screen offers at a time.
  static const int defaultLimit = 40;

  /// The same person is not allowed to fill the whole screen.
  static const int maxPairsPerPerson = 3;

  static List<NewIdeaSuggestion> build({
    required List<Person> people,
    required List<MatchIdea> matches,
    Set<String> Function(String personId)? dismissedFor,
    int limit = defaultLimit,
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

    pairs.sort((NewIdeaSuggestion a, NewIdeaSuggestion b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return b.female.updatedAt.compareTo(a.female.updatedAt);
    });

    // Spread the screen over as many people as possible instead of showing one
    // popular candidate against everyone.
    final Map<String, int> appearances = <String, int>{};
    final List<NewIdeaSuggestion> result = <NewIdeaSuggestion>[];
    for (final NewIdeaSuggestion pair in pairs) {
      final int maleCount = appearances[pair.male.id] ?? 0;
      final int femaleCount = appearances[pair.female.id] ?? 0;
      if (maleCount >= maxPairsPerPerson || femaleCount >= maxPairsPerPerson) {
        continue;
      }
      appearances[pair.male.id] = maleCount + 1;
      appearances[pair.female.id] = femaleCount + 1;
      result.add(pair);
      if (result.length >= limit) {
        break;
      }
    }
    return result;
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
      score += 5;
      reasons.add('לשניהם אין רעיון פתוח');
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

    if (_cardIsComplete(male) && _cardIsComplete(female)) {
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
