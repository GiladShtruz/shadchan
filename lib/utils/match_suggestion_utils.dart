import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_preferences.dart';

abstract final class MatchSuggestionUtils {
  /// Whether [candidate] fits what [source] themselves are looking for.
  ///
  /// This is the default the matches view opens on: the filters recorded on the
  /// candidate's own card, not the matchmaker's global preferences. A candidate
  /// who has said nothing falls back to the app's age rule and their own
  /// religious style, which is what [isSuggestedCandidate] has always done.
  static bool matchesOwnPreferences({
    required Person source,
    required Person candidate,
  }) {
    if (!isEligibleCandidate(source: source, candidate: candidate)) {
      return false;
    }

    final MatchPreferences preferences = MatchPreferences.forPerson(source);

    final int? age = candidate.age;
    if (preferences.minAge != null || preferences.maxAge != null) {
      if (age == null) {
        return false;
      }
      if (preferences.minAge != null && age < preferences.minAge!) {
        return false;
      }
      if (preferences.maxAge != null && age > preferences.maxAge!) {
        return false;
      }
    } else if (!areAgesCompatible(source: source, candidate: candidate)) {
      return false;
    }

    final int? height = candidate.heightCm;
    if (preferences.minHeightCm != null || preferences.maxHeightCm != null) {
      if (height == null) {
        return false;
      }
      if (preferences.minHeightCm != null &&
          height < preferences.minHeightCm!) {
        return false;
      }
      if (preferences.maxHeightCm != null &&
          height > preferences.maxHeightCm!) {
        return false;
      }
    }

    // A candidate with no region set is simply absent from a region search.
    // Guessing one from their city would put people in front of a matchmaker
    // who asked for a specific part of the country and did not get it.
    if (preferences.regions.isNotEmpty &&
        (candidate.region == null ||
            !preferences.regions.contains(candidate.region))) {
      return false;
    }

    if (preferences.maritalStatuses.isNotEmpty &&
        (candidate.maritalStatus == null ||
            !preferences.maritalStatuses.contains(candidate.maritalStatus))) {
      return false;
    }

    final bool hasStyleFilter =
        preferences.religiousLevels.isNotEmpty ||
        preferences.religiousLevelOtherLabels.isNotEmpty;
    if (hasStyleFilter &&
        !preferences.religiousLevels.contains(candidate.religiousLevel) &&
        !(candidate.religiousLevel == ReligiousLevel.other &&
            preferences.religiousLevelOtherLabels.contains(
              candidate.religiousLevelOther?.trim(),
            ))) {
      return false;
    }

    return true;
  }

  /// Whether [candidate] passes the **basic** filter for [source]: the right
  /// gender, a compatible age, and a religious style [source]'s own style is
  /// ordinarily matched with.
  ///
  /// **This is the default a list of candidates opens on**, and the reason
  /// there are two filters rather than one. A card that has been through
  /// "עריכה מורחבת" can carry a height range, a city, a region and a marital
  /// status, and applying all of it by default turned a database of six
  /// hundred into a list of four — most of them missing not because they are
  /// wrong for anybody but because nobody ever recorded their height. The
  /// extended answer is still one tap away; see [matchesOwnPreferences] and
  /// [hasExtendedPreferences].
  ///
  /// With nothing extended recorded the two are the same list, which is what
  /// makes the toggle honest: it only ever appears where it changes something.
  ///
  /// **A friend whose card is their own personal card is the exception**
  /// ([followsOwnerWishes]): what they wrote under "מה אני מחפש/ת" is their
  /// wish, not a matchmaker's guess, so the basic list honours it — their
  /// chosen styles replace the default ones, their age range replaces the
  /// app's rule, and a candidate whose recorded height, region or marital
  /// status contradicts it is left out (see [fitsOwnerWishes]).
  static bool matchesBasicPreferences({
    required Person source,
    required Person candidate,
  }) {
    if (!isEligibleCandidate(source: source, candidate: candidate)) {
      return false;
    }

    final bool ownerWishes = followsOwnerWishes(source);
    if (!(ownerWishes && _choseStyles(source))) {
      final List<ReligiousLevel> levels =
          MatchPreferences.defaultReligiousLevelsFor(source.religiousLevel);
      final List<String> otherLabels = MatchPreferences.defaultOtherLabelsFor(
        source,
      );
      if ((levels.isNotEmpty || otherLabels.isNotEmpty) &&
          !_styleIn(candidate, levels, otherLabels)) {
        return false;
      }
    }

    if (ownerWishes) {
      if (!fitsOwnerWishes(source: source, candidate: candidate)) {
        return false;
      }
      if (_statesAgeRange(source)) {
        return true;
      }
    }
    return areAgesCompatible(source: source, candidate: candidate);
  }

  /// Whether [source]'s automatic matches follow what they themselves asked
  /// for: their card is a personal card they manage (synced from their own
  /// account), and they filled in something under "מה אני מחפש/ת".
  ///
  /// A card the matchmaker wrote by hand keeps the old behaviour — there the
  /// same fields are the matchmaker's notes, and applying them by default is
  /// what emptied the lists (see [matchesBasicPreferences]).
  static bool followsOwnerWishes(Person source) {
    return source.isCardSynced && hasExtendedPreferences(source);
  }

  /// Whether [candidate] respects what [source] wrote under "מה אני מחפש/ת":
  /// the religious styles and age range they chose, and the height, regions
  /// and marital statuses they asked for.
  ///
  /// **Only a recorded fact can contradict a wish.** A candidate whose age,
  /// height, region or marital status was never written down is not ruled out
  /// by it: the wish says who is not wanted, and nobody knows yet whether this
  /// candidate is that. The strict reading — unknown is out — is still one tap
  /// away as "סינון מורחב" ([matchesOwnPreferences]).
  ///
  /// The app's own age rule is not part of this; callers apply it where the
  /// wish names no age range.
  static bool fitsOwnerWishes({
    required Person source,
    required Person candidate,
  }) {
    if (_choseStyles(source) &&
        !_styleIn(
          candidate,
          source.preferredReligiousLevels,
          source.preferredReligiousLevelOtherLabels,
        )) {
      return false;
    }

    final int? age = candidate.age;
    if (age != null) {
      final int? minAge = source.preferredMinAge;
      final int? maxAge = source.preferredMaxAge;
      if (minAge != null && age < minAge) {
        return false;
      }
      if (maxAge != null && age > maxAge) {
        return false;
      }
    }

    final int? height = candidate.heightCm;
    if (height != null) {
      final int? minHeight = source.preferredMinHeightCm;
      final int? maxHeight = source.preferredMaxHeightCm;
      if (minHeight != null && height < minHeight) {
        return false;
      }
      if (maxHeight != null && height > maxHeight) {
        return false;
      }
    }

    final Region? region = candidate.region;
    if (region != null &&
        source.preferredRegions.isNotEmpty &&
        !source.preferredRegions.contains(region)) {
      return false;
    }

    final MaritalStatus? marital = candidate.maritalStatus;
    if (marital != null &&
        source.preferredMaritalStatuses.isNotEmpty &&
        !source.preferredMaritalStatuses.contains(marital)) {
      return false;
    }

    return true;
  }

  static bool _choseStyles(Person person) =>
      person.preferredReligiousLevels.isNotEmpty ||
      person.preferredReligiousLevelOtherLabels.isNotEmpty;

  static bool _statesAgeRange(Person person) =>
      person.preferredMinAge != null || person.preferredMaxAge != null;

  static bool _styleIn(
    Person candidate,
    List<ReligiousLevel> levels,
    List<String> otherLabels,
  ) {
    return levels.contains(candidate.religiousLevel) ||
        (candidate.religiousLevel == ReligiousLevel.other &&
            otherLabels.contains(candidate.religiousLevelOther?.trim()));
  }

  /// Every candidate in [people] for [source], best first: those who pass
  /// everything [source]'s card asks for ([matchesOwnPreferences]), then those
  /// who pass only the basic match ([matchesBasicPreferences]) — each group
  /// with the most recently edited card first.
  ///
  /// **This is what lets a short list stay full.** "עוצרים רגע לחשוב" shows
  /// three matches a friend; with the full card alone, anybody whose height
  /// or region was never written down was dropped, and a friend with plenty
  /// of sensible matches showed one face, or two. The full card still leads,
  /// and nobody who fails the basic match is ever offered.
  static List<Person> ranked({
    required Person source,
    required Iterable<Person> people,
  }) {
    final List<Person> sorted = people.toList()
      ..sort((Person a, Person b) => b.updatedAt.compareTo(a.updatedAt));
    final List<Person> preferred = <Person>[];
    final List<Person> basic = <Person>[];
    for (final Person candidate in sorted) {
      if (matchesOwnPreferences(source: source, candidate: candidate)) {
        preferred.add(candidate);
      } else if (matchesBasicPreferences(
        source: source,
        candidate: candidate,
      )) {
        basic.add(candidate);
      }
    }
    return <Person>[...preferred, ...basic];
  }

  /// Whether [source] has anything recorded beyond the basics — the fields
  /// "עריכה מורחבת" collects. Only then is a "סינון מורחב" toggle worth
  /// drawing: without one of these, narrowing would drop nobody.
  static bool hasExtendedPreferences(Person source) {
    return source.preferredMinAge != null ||
        source.preferredMaxAge != null ||
        source.preferredMinHeightCm != null ||
        source.preferredMaxHeightCm != null ||
        source.preferredRegions.isNotEmpty ||
        source.preferredMaritalStatuses.isNotEmpty ||
        source.preferredReligiousLevels.isNotEmpty ||
        source.preferredReligiousLevelOtherLabels.isNotEmpty;
  }

  /// The religious levels shown by default (before the matchmaker sets a
  /// personal filter). The default is now the candidate's *own* level only —
  /// a "דתי לאומי" sees only "דתי לאומי", a "דתי פתוח" sees only "דתי פתוח",
  /// and so on. The matchmaker can widen this from the filter sheet. A custom
  /// ("אחר") style has no built-in level to match on, so no religious filter is
  /// applied to its suggestions.
  static List<ReligiousLevel> religiousLevelsFor(ReligiousLevel? sourceLevel) {
    if (sourceLevel == null || sourceLevel == ReligiousLevel.other) {
      return const <ReligiousLevel>[];
    }
    return <ReligiousLevel>[sourceLevel];
  }

  static ({int minAge, int maxAge})? femaleAgeRangeForMale(int? maleAge) {
    if (maleAge == null) {
      return null;
    }

    if (maleAge > 40) {
      return (minAge: maleAge - 12, maxAge: maleAge + 5);
    }

    if (maleAge > 30) {
      return (minAge: maleAge - 7, maxAge: maleAge + 2);
    }

    return (minAge: maleAge - 5, maxAge: maleAge + 1);
  }

  /// The ages of men a woman of [femaleAge] is shown by default.
  ///
  /// Worked out from [femaleAgeRangeForMale] rather than written as a second
  /// rule, so the filter a woman's matches open on can never disagree with the
  /// one a man's do: it runs from the youngest to the oldest man whose own
  /// default range includes her. That is an envelope — at the 30 and 40 tier
  /// boundaries the men's rule leaves a one-year seam (a woman of 24 fits men
  /// of 23–29 and 31, not 30) — which is right for a slider, which cannot have
  /// a hole in it.
  static ({int minAge, int maxAge})? maleAgeRangeForFemale(int? femaleAge) {
    if (femaleAge == null) {
      return null;
    }
    int? low;
    int? high;
    for (int male = femaleAge - 20; male <= femaleAge + 20; male++) {
      if (male < 16) {
        continue;
      }
      final ({int minAge, int maxAge})? range = femaleAgeRangeForMale(male);
      if (range != null &&
          femaleAge >= range.minAge &&
          femaleAge <= range.maxAge) {
        low ??= male;
        high = male;
      }
    }
    if (low == null || high == null) {
      return null;
    }
    return (minAge: low, maxAge: high);
  }

  /// Also honours a personal card's "מה אני מחפש/ת" ([fitsOwnerWishes]) — on
  /// **both** sides, because this is the check that decides whether the app
  /// offers a pair at all (the database's own ideas, the home screen's counts),
  /// and a pair one of whom asked for somebody else is not an idea worth
  /// offering. A wished-for age range on either side stands in for the app's
  /// age rule.
  static bool isSuggestedCandidate({
    required Person source,
    required Person candidate,
  }) {
    if (!isEligibleCandidate(source: source, candidate: candidate)) {
      return false;
    }

    final bool sourceWishes = followsOwnerWishes(source);
    final bool candidateWishes = followsOwnerWishes(candidate);

    if (!(sourceWishes && _choseStyles(source))) {
      final List<ReligiousLevel> allowedLevels = religiousLevelsFor(
        source.religiousLevel,
      );
      if (allowedLevels.isNotEmpty &&
          !allowedLevels.contains(candidate.religiousLevel)) {
        return false;
      }
    }

    if (sourceWishes &&
        !fitsOwnerWishes(source: source, candidate: candidate)) {
      return false;
    }
    if (candidateWishes &&
        !fitsOwnerWishes(source: candidate, candidate: source)) {
      return false;
    }
    if ((sourceWishes && _statesAgeRange(source)) ||
        (candidateWishes && _statesAgeRange(candidate))) {
      return true;
    }

    return areAgesCompatible(source: source, candidate: candidate);
  }

  static bool isEligibleCandidate({
    required Person source,
    required Person candidate,
  }) {
    return source.id != candidate.id &&
        source.gender != Gender.unknown &&
        candidate.gender != Gender.unknown &&
        source.gender != candidate.gender &&
        !candidate.needsReview &&
        !candidate.profileStatus.isArchived;
  }

  static bool areAgesCompatible({
    required Person source,
    required Person candidate,
  }) {
    final Person male;
    final Person female;
    if (source.gender == Gender.male && candidate.gender == Gender.female) {
      male = source;
      female = candidate;
    } else if (source.gender == Gender.female &&
        candidate.gender == Gender.male) {
      male = candidate;
      female = source;
    } else {
      return false;
    }

    final ({int minAge, int maxAge})? femaleRange = femaleAgeRangeForMale(
      male.age,
    );
    final int? femaleAge = female.age;
    if (femaleRange == null || femaleAge == null) {
      return true;
    }

    return femaleAge >= femaleRange.minAge && femaleAge <= femaleRange.maxAge;
  }
}
