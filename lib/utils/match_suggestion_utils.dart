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

    final String city = (preferences.city ?? '').trim().toLowerCase();
    if (city.isNotEmpty &&
        (candidate.city ?? '').trim().toLowerCase() != city) {
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

  static bool isSuggestedCandidate({
    required Person source,
    required Person candidate,
  }) {
    if (!isEligibleCandidate(source: source, candidate: candidate)) {
      return false;
    }

    final List<ReligiousLevel> allowedLevels = religiousLevelsFor(
      source.religiousLevel,
    );
    if (allowedLevels.isNotEmpty &&
        !allowedLevels.contains(candidate.religiousLevel)) {
      return false;
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
