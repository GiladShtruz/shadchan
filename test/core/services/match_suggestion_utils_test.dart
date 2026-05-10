import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

void main() {
  group('MatchSuggestionUtils', () {
    test('maps religious levels to the requested automatic filters', () {
      expect(
        MatchSuggestionUtils.religiousLevelsFor(ReligiousLevel.datiLeumiTorani),
        <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
        ],
      );
      expect(
        MatchSuggestionUtils.religiousLevelsFor(ReligiousLevel.datiLeumi),
        <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
          ReligiousLevel.datiOpen,
        ],
      );
      expect(
        MatchSuggestionUtils.religiousLevelsFor(ReligiousLevel.masorti),
        <ReligiousLevel>[
          ReligiousLevel.datiOpen,
          ReligiousLevel.masorti,
          ReligiousLevel.hiloni,
          ReligiousLevel.datlashi,
        ],
      );
      expect(
        MatchSuggestionUtils.religiousLevelsFor(ReligiousLevel.haredi),
        <ReligiousLevel>[ReligiousLevel.haredi],
      );
    });

    test('uses male age rules when the source person is male', () {
      final Person male30 = _person(id: 'm30', gender: Gender.male, age: 30);

      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: male30,
          candidate: _person(id: 'f31', gender: Gender.female, age: 31),
        ),
        isTrue,
      );
      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: male30,
          candidate: _person(id: 'f24', gender: Gender.female, age: 24),
        ),
        isFalse,
      );

      final Person male41 = _person(id: 'm41', gender: Gender.male, age: 41);
      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: male41,
          candidate: _person(id: 'f29', gender: Gender.female, age: 29),
        ),
        isTrue,
      );
      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: male41,
          candidate: _person(id: 'f28', gender: Gender.female, age: 28),
        ),
        isFalse,
      );
    });

    test('reverses the male age rules when the source person is female', () {
      final Person female35 = _person(
        id: 'f35',
        gender: Gender.female,
        age: 35,
      );

      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: female35,
          candidate: _person(id: 'm33', gender: Gender.male, age: 33),
        ),
        isTrue,
      );
      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: female35,
          candidate: _person(id: 'm30', gender: Gender.male, age: 30),
        ),
        isFalse,
      );
      expect(
        MatchSuggestionUtils.areAgesCompatible(
          source: female35,
          candidate: _person(id: 'm47', gender: Gender.male, age: 47),
        ),
        isTrue,
      );
    });

    test('combines gender, religious, age and archived checks', () {
      final Person source = _person(
        id: 'source',
        gender: Gender.male,
        age: 28,
        religiousLevel: ReligiousLevel.datiLeumi,
      );

      expect(
        MatchSuggestionUtils.isSuggestedCandidate(
          source: source,
          candidate: _person(
            id: 'ok',
            gender: Gender.female,
            age: 27,
            religiousLevel: ReligiousLevel.datiOpen,
          ),
        ),
        isTrue,
      );
      expect(
        MatchSuggestionUtils.isSuggestedCandidate(
          source: source,
          candidate: _person(
            id: 'wrong-style',
            gender: Gender.female,
            age: 27,
            religiousLevel: ReligiousLevel.hiloni,
          ),
        ),
        isFalse,
      );
      expect(
        MatchSuggestionUtils.isSuggestedCandidate(
          source: source,
          candidate: _person(
            id: 'archived',
            gender: Gender.female,
            age: 27,
            religiousLevel: ReligiousLevel.datiOpen,
            profileStatus: ProfileStatus.mazelTov,
          ),
        ),
        isFalse,
      );
    });
  });
}

Person _person({
  required String id,
  required Gender gender,
  required int age,
  ReligiousLevel? religiousLevel,
  ProfileStatus profileStatus = ProfileStatus.available,
}) {
  final DateTime now = DateTime(2026);
  return Person(
    id: id,
    firstName: id,
    lastName: '',
    gender: gender,
    manualAge: age,
    religiousLevel: religiousLevel,
    profileStatus: profileStatus,
    createdAt: now,
    updatedAt: now,
  );
}
