import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// What a candidate is looking for, resolved for use.
///
/// A candidate's card may say nothing about who they want; that is the normal
/// state of a friend who was just added from the address book. Rather than
/// showing them no matches at all, the app answers the question on their behalf
/// from what it does know — chiefly their own religious style — and lets the
/// matchmaker overwrite any of it, for that one candidate, whenever they like.
class MatchPreferences {
  const MatchPreferences({
    this.minAge,
    this.maxAge,
    this.minHeightCm,
    this.maxHeightCm,
    this.city,
    this.regions = const <Region>[],
    this.maritalStatuses = const <MaritalStatus>[],
    this.religiousLevels = const <ReligiousLevel>[],
    this.religiousLevelOtherLabels = const <String>[],
  });

  final int? minAge;
  final int? maxAge;
  final int? minHeightCm;
  final int? maxHeightCm;
  final String? city;
  final List<Region> regions;
  final List<MaritalStatus> maritalStatuses;
  final List<ReligiousLevel> religiousLevels;
  final List<String> religiousLevelOtherLabels;

  /// The preferences saved on [person], with the religious styles falling back
  /// to the default for their own style when nothing was chosen.
  factory MatchPreferences.forPerson(Person person) {
    final List<ReligiousLevel> levels = person.preferredReligiousLevels;
    final List<String> otherLabels = person.preferredReligiousLevelOtherLabels;
    final bool hasChosenStyles = levels.isNotEmpty || otherLabels.isNotEmpty;

    return MatchPreferences(
      minAge: person.preferredMinAge,
      maxAge: person.preferredMaxAge,
      minHeightCm: person.preferredMinHeightCm,
      maxHeightCm: person.preferredMaxHeightCm,
      city: person.preferredCity,
      regions: person.preferredRegions,
      maritalStatuses: person.preferredMaritalStatuses,
      religiousLevels: hasChosenStyles
          ? levels
          : defaultReligiousLevelsFor(person.religiousLevel),
      religiousLevelOtherLabels: hasChosenStyles
          ? otherLabels
          : defaultOtherLabelsFor(person),
    );
  }

  bool get hasAnyFilter =>
      minAge != null ||
      maxAge != null ||
      minHeightCm != null ||
      maxHeightCm != null ||
      (city ?? '').trim().isNotEmpty ||
      regions.isNotEmpty ||
      maritalStatuses.isNotEmpty ||
      religiousLevels.isNotEmpty ||
      religiousLevelOtherLabels.isNotEmpty;

  /// The styles a candidate of [level] is shown by default.
  ///
  /// The rule is the matchmaker's, written out rather than derived: the styles
  /// sit on a spectrum, but which neighbours actually get proposed to whom is a
  /// judgement about people, not a distance on a line. Anything not listed —
  /// including a style the matchmaker invented — defaults to itself alone,
  /// which is the only safe answer when the app does not know what the label
  /// means.
  static List<ReligiousLevel> defaultReligiousLevelsFor(ReligiousLevel? level) {
    switch (level) {
      case null:
        return const <ReligiousLevel>[];
      case ReligiousLevel.datiLeumi:
        return const <ReligiousLevel>[
          ReligiousLevel.datiLeumi,
          ReligiousLevel.datiOpen,
          ReligiousLevel.datiLeumiTorani,
        ];
      case ReligiousLevel.datiLeumiTorani:
        return const <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
          ReligiousLevel.chardal,
        ];
      case ReligiousLevel.datiOpen:
        return const <ReligiousLevel>[
          ReligiousLevel.datiOpen,
          ReligiousLevel.datiLeumi,
        ];
      case ReligiousLevel.hiloni:
        return const <ReligiousLevel>[
          ReligiousLevel.hiloni,
          ReligiousLevel.masorti,
          ReligiousLevel.datlashi,
        ];
      case ReligiousLevel.masorti:
        return const <ReligiousLevel>[
          ReligiousLevel.masorti,
          ReligiousLevel.hiloni,
          ReligiousLevel.datlashi,
        ];
      case ReligiousLevel.datlashi:
        return const <ReligiousLevel>[
          ReligiousLevel.datlashi,
          ReligiousLevel.hiloni,
          ReligiousLevel.masorti,
        ];
      case ReligiousLevel.other:
        // A style the app does not name: only that same style, resolved through
        // the custom label in [defaultOtherLabelsFor].
        return const <ReligiousLevel>[ReligiousLevel.other];
      case ReligiousLevel.chardal:
      case ReligiousLevel.datiLite:
      case ReligiousLevel.chabad:
      case ReligiousLevel.harediModern:
      case ReligiousLevel.hasid:
      case ReligiousLevel.haredi:
        return <ReligiousLevel>[level];
    }
  }

  /// The custom label a candidate defaults to when their own style is one the
  /// matchmaker invented — matches are then kept to that same label.
  static List<String> defaultOtherLabelsFor(Person person) {
    if (person.religiousLevel != ReligiousLevel.other) {
      return const <String>[];
    }
    final String label = (person.religiousLevelOther ?? '').trim();
    return label.isEmpty ? const <String>[] : <String>[label];
  }
}
