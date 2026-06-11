import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

abstract final class MatchSuggestionUtils {
  static List<ReligiousLevel> religiousLevelsFor(ReligiousLevel? sourceLevel) {
    switch (sourceLevel) {
      case ReligiousLevel.datiLeumiTorani:
        return const <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
          ReligiousLevel.chardal,
        ];
      case ReligiousLevel.chardal:
        return const <ReligiousLevel>[
          ReligiousLevel.chardal,
          ReligiousLevel.datiLeumiTorani,
        ];
      case ReligiousLevel.datiLeumi:
        return const <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
          ReligiousLevel.datiOpen,
        ];
      case ReligiousLevel.datiOpen:
        return const <ReligiousLevel>[
          ReligiousLevel.datiLeumi,
          ReligiousLevel.datiOpen,
          ReligiousLevel.masorti,
        ];
      case ReligiousLevel.masorti:
        return const <ReligiousLevel>[
          ReligiousLevel.datiOpen,
          ReligiousLevel.masorti,
          ReligiousLevel.hiloni,
          ReligiousLevel.datlashi,
        ];
      case ReligiousLevel.hiloni:
      case ReligiousLevel.datlashi:
        return const <ReligiousLevel>[
          ReligiousLevel.hiloni,
          ReligiousLevel.masorti,
          ReligiousLevel.datlashi,
        ];
      case ReligiousLevel.haredi:
        return const <ReligiousLevel>[ReligiousLevel.haredi];
      case null:
        return const <ReligiousLevel>[];
    }
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
