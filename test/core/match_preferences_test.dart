import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_preferences.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// What a candidate is looking for, and what the app answers on their behalf
/// until they say.
///
/// The defaults are a judgement about people written down as a table, so they
/// are asserted rather than derived — a change to who gets proposed to whom
/// should have to be made on purpose, not fall out of a refactor.
void main() {
  Person person({
    String id = 'a',
    Gender gender = Gender.male,
    int? age = 27,
    int? heightCm,
    ReligiousLevel? level,
    String? levelOther,
    Region? region,
    String? city,
    MaritalStatus? maritalStatus,
    int? prefMinAge,
    int? prefMaxAge,
    int? prefMinHeight,
    int? prefMaxHeight,
    String? prefCity,
    List<Region> prefRegions = const <Region>[],
    List<MaritalStatus> prefMarital = const <MaritalStatus>[],
    List<ReligiousLevel> prefLevels = const <ReligiousLevel>[],
    List<String> prefOther = const <String>[],
  }) {
    final DateTime now = DateTime(2026, 1, 1);
    return Person(
      id: id,
      firstName: 'שם',
      lastName: 'משפחה',
      gender: gender,
      manualAge: age,
      heightCm: heightCm,
      religiousLevel: level,
      religiousLevelOther: levelOther,
      region: region,
      city: city,
      maritalStatus: maritalStatus,
      preferredMinAge: prefMinAge,
      preferredMaxAge: prefMaxAge,
      preferredMinHeightCm: prefMinHeight,
      preferredMaxHeightCm: prefMaxHeight,
      preferredCity: prefCity,
      preferredRegions: prefRegions,
      preferredMaritalStatuses: prefMarital,
      preferredReligiousLevels: prefLevels,
      preferredReligiousLevelOtherLabels: prefOther,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('default religious styles', () {
    test('דתי לאומי opens onto its two neighbours', () {
      expect(
        MatchPreferences.defaultReligiousLevelsFor(ReligiousLevel.datiLeumi),
        const <ReligiousLevel>[
          ReligiousLevel.datiLeumi,
          ReligiousLevel.datiOpen,
          ReligiousLevel.datiLeumiTorani,
        ],
      );
    });

    test('דתי לאומי תורני reaches up to חרד״ל rather than down to פתוח', () {
      expect(
        MatchPreferences.defaultReligiousLevelsFor(
          ReligiousLevel.datiLeumiTorani,
        ),
        const <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
          ReligiousLevel.chardal,
        ],
      );
    });

    test('the secular trio all open onto each other', () {
      const List<ReligiousLevel> trio = <ReligiousLevel>[
        ReligiousLevel.hiloni,
        ReligiousLevel.masorti,
        ReligiousLevel.datlashi,
      ];
      for (final ReligiousLevel level in trio) {
        expect(
          MatchPreferences.defaultReligiousLevelsFor(level).toSet(),
          trio.toSet(),
          reason: '${level.displayName} should open onto the other two',
        );
      }
    });

    test('every other style defaults to itself alone', () {
      for (final ReligiousLevel level in <ReligiousLevel>[
        ReligiousLevel.chardal,
        ReligiousLevel.haredi,
        ReligiousLevel.hasid,
        ReligiousLevel.chabad,
        ReligiousLevel.harediModern,
        ReligiousLevel.datiLite,
      ]) {
        expect(
          MatchPreferences.defaultReligiousLevelsFor(level),
          <ReligiousLevel>[level],
        );
      }
    });

    test('a style the matchmaker invented keeps to its own label', () {
      final Person candidate = person(
        level: ReligiousLevel.other,
        levelOther: 'ליטאי מודרני',
      );
      final MatchPreferences preferences = MatchPreferences.forPerson(
        candidate,
      );
      expect(preferences.religiousLevels, <ReligiousLevel>[
        ReligiousLevel.other,
      ]);
      expect(preferences.religiousLevelOtherLabels, <String>['ליטאי מודרני']);
    });

    test('a saved choice wins over the default', () {
      final Person candidate = person(
        level: ReligiousLevel.datiLeumi,
        prefLevels: const <ReligiousLevel>[ReligiousLevel.haredi],
      );
      expect(
        MatchPreferences.forPerson(candidate).religiousLevels,
        <ReligiousLevel>[ReligiousLevel.haredi],
      );
    });
  });

  group('matching against a candidate\'s own preferences', () {
    test('a saved age range replaces the app-wide age rule', () {
      final Person source = person(
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
        prefMinAge: 30,
        prefMaxAge: 34,
      );
      final Person tooYoung = person(
        id: 'b',
        gender: Gender.female,
        age: 25,
        level: ReligiousLevel.datiLeumi,
      );
      final Person inRange = person(
        id: 'c',
        gender: Gender.female,
        age: 31,
        level: ReligiousLevel.datiLeumi,
      );

      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: tooYoung,
        ),
        isFalse,
      );
      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: inRange,
        ),
        isTrue,
      );
    });

    test('a region filter never reaches someone with no region set', () {
      final Person source = person(
        gender: Gender.female,
        age: 26,
        level: ReligiousLevel.datiLeumi,
        prefRegions: const <Region>[Region.south],
      );
      final Person noRegion = person(
        id: 'b',
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
      );
      final Person inSouth = person(
        id: 'c',
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
        region: Region.south,
      );

      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: noRegion,
        ),
        isFalse,
      );
      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: inSouth,
        ),
        isTrue,
      );
    });

    test('the style default is applied when nothing was chosen', () {
      final Person source = person(
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
      );
      final Person open = person(
        id: 'b',
        gender: Gender.female,
        age: 25,
        level: ReligiousLevel.datiOpen,
      );
      final Person haredi = person(
        id: 'c',
        gender: Gender.female,
        age: 25,
        level: ReligiousLevel.haredi,
      );

      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: open,
        ),
        isTrue,
      );
      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: haredi,
        ),
        isFalse,
      );
    });

    test('a height range excludes a candidate with no height recorded', () {
      final Person source = person(
        gender: Gender.female,
        age: 25,
        level: ReligiousLevel.datiLeumi,
        prefMinHeight: 175,
      );
      final Person noHeight = person(
        id: 'b',
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
      );
      final Person tall = person(
        id: 'c',
        gender: Gender.male,
        age: 27,
        heightCm: 182,
        level: ReligiousLevel.datiLeumi,
      );

      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: noHeight,
        ),
        isFalse,
      );
      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: source,
          candidate: tall,
        ),
        isTrue,
      );
    });

    test('preferences on one candidate do not change another', () {
      final Person picky = person(
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
        prefMinAge: 30,
      );
      final Person relaxed = person(
        id: 'other-source',
        gender: Gender.male,
        age: 27,
        level: ReligiousLevel.datiLeumi,
      );
      final Person young = person(
        id: 'b',
        gender: Gender.female,
        age: 25,
        level: ReligiousLevel.datiLeumi,
      );

      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: picky,
          candidate: young,
        ),
        isFalse,
      );
      expect(
        MatchSuggestionUtils.matchesOwnPreferences(
          source: relaxed,
          candidate: young,
        ),
        isTrue,
      );
    });
  });

  group('required details', () {
    test('a friend needs a full name, an age, a gender and a style', () {
      expect(
        person(level: ReligiousLevel.datiLeumi).hasRequiredDetails,
        isTrue,
      );
      expect(person(level: null).hasRequiredDetails, isFalse);
      expect(
        person(age: null, level: ReligiousLevel.datiLeumi).hasRequiredDetails,
        isFalse,
      );
      expect(
        person(
          gender: Gender.unknown,
          level: ReligiousLevel.datiLeumi,
        ).hasRequiredDetails,
        isFalse,
      );
    });
  });
}
