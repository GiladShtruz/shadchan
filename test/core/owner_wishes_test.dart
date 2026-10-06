import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// A single who manages their own card says, under "מה אני מחפש/ת", who they
/// are looking for. Their automatic matches follow it; a card written by the
/// matchmaker keeps the basic default, and "סינון מורחב" stays the strict one.
void main() {
  Person person({
    required String id,
    Gender gender = Gender.male,
    int? age = 27,
    int? heightCm,
    ReligiousLevel? level = ReligiousLevel.datiLeumi,
    Region? region,
    MaritalStatus? maritalStatus,
    String? cardOwnerUid,
    int? prefMinAge,
    int? prefMaxAge,
    int? prefMinHeight,
    List<Region> prefRegions = const <Region>[],
    List<MaritalStatus> prefMarital = const <MaritalStatus>[],
    List<ReligiousLevel> prefLevels = const <ReligiousLevel>[],
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
      region: region,
      maritalStatus: maritalStatus,
      cardOwnerUid: cardOwnerUid,
      preferredMinAge: prefMinAge,
      preferredMaxAge: prefMaxAge,
      preferredMinHeightCm: prefMinHeight,
      preferredRegions: prefRegions,
      preferredMaritalStatuses: prefMarital,
      preferredReligiousLevels: prefLevels,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool basic(Person source, Person candidate) =>
      MatchSuggestionUtils.matchesBasicPreferences(
        source: source,
        candidate: candidate,
      );

  final Person divorced = person(
    id: 'divorced',
    gender: Gender.female,
    age: 25,
    maritalStatus: MaritalStatus.divorced,
  );
  final Person single = person(
    id: 'single',
    gender: Gender.female,
    age: 25,
    maritalStatus: MaritalStatus.single,
  );
  final Person unknownStatus = person(
    id: 'unknown',
    gender: Gender.female,
    age: 25,
  );

  test('a single\'s own marital-status wish narrows the automatic list', () {
    final Person owner = person(
      id: 'owner',
      cardOwnerUid: 'uid-1',
      prefMarital: const <MaritalStatus>[MaritalStatus.single],
    );

    expect(basic(owner, single), isTrue);
    expect(basic(owner, divorced), isFalse);
    // Nothing recorded contradicts nothing: still offered by default...
    expect(basic(owner, unknownStatus), isTrue);
    // ...and left out only by the strict, extended filter.
    expect(
      MatchSuggestionUtils.matchesOwnPreferences(
        source: owner,
        candidate: unknownStatus,
      ),
      isFalse,
    );
  });

  test('the same fields on a card the matchmaker wrote stay out of the '
      'default', () {
    final Person handWritten = person(
      id: 'hand',
      prefMarital: const <MaritalStatus>[MaritalStatus.single],
    );
    expect(basic(handWritten, divorced), isTrue);
  });

  test('a card the matchmaker detached is the matchmaker\'s again', () {
    final Person detached = person(
      id: 'detached',
      cardOwnerUid: 'uid-1',
      prefMarital: const <MaritalStatus>[MaritalStatus.single],
    )..cardSyncDetached = true;
    expect(basic(detached, divorced), isTrue);
  });

  test('region and height wishes rule out only a recorded contradiction', () {
    final Person owner = person(
      id: 'owner',
      cardOwnerUid: 'uid-1',
      prefRegions: const <Region>[Region.south],
      prefMinHeight: 165,
    );
    expect(
      basic(
        owner,
        person(id: 'n', gender: Gender.female, age: 25, region: Region.north),
      ),
      isFalse,
    );
    expect(
      basic(
        owner,
        person(
          id: 's',
          gender: Gender.female,
          age: 25,
          region: Region.south,
          heightCm: 160,
        ),
      ),
      isFalse,
    );
    expect(
      basic(
        owner,
        person(
          id: 'ok',
          gender: Gender.female,
          age: 25,
          region: Region.south,
          heightCm: 168,
        ),
      ),
      isTrue,
    );
    expect(basic(owner, unknownStatus), isTrue);
  });

  test('chosen styles replace the default table', () {
    final Person owner = person(
      id: 'owner',
      cardOwnerUid: 'uid-1',
      prefLevels: const <ReligiousLevel>[ReligiousLevel.chardal],
    );
    final Person chardal = person(
      id: 'c',
      gender: Gender.female,
      age: 25,
      level: ReligiousLevel.chardal,
    );
    final Person datiLeumi = person(
      id: 'd',
      gender: Gender.female,
      age: 25,
      level: ReligiousLevel.datiLeumi,
    );
    expect(basic(owner, chardal), isTrue);
    expect(basic(owner, datiLeumi), isFalse);
  });

  test('a wished age range replaces the app\'s age rule', () {
    final Person owner = person(
      id: 'owner',
      age: 27,
      cardOwnerUid: 'uid-1',
      prefMinAge: 27,
      prefMaxAge: 32,
    );
    // The app's rule alone would have a man of 27 meet women of 22–28.
    final Person thirty = person(id: 't', gender: Gender.female, age: 30);
    final Person twentyThree = person(id: 'y', gender: Gender.female, age: 23);
    expect(basic(owner, thirty), isTrue);
    expect(basic(owner, twentyThree), isFalse);
  });

  test('the database\'s own pairs respect a wish on either side', () {
    final Person owner = person(
      id: 'owner',
      gender: Gender.female,
      age: 25,
      cardOwnerUid: 'uid-1',
      prefMarital: const <MaritalStatus>[MaritalStatus.single],
    );
    final Person divorcedMan = person(
      id: 'm',
      age: 27,
      maritalStatus: MaritalStatus.divorced,
    );
    final Person singleMan = person(
      id: 's',
      age: 27,
      maritalStatus: MaritalStatus.single,
    );
    // The scan starts from the man; the woman's wish still counts.
    expect(
      MatchSuggestionUtils.isSuggestedCandidate(
        source: divorcedMan,
        candidate: owner,
      ),
      isFalse,
    );
    expect(
      MatchSuggestionUtils.isSuggestedCandidate(
        source: singleMan,
        candidate: owner,
      ),
      isTrue,
    );
  });

  test('ranking a single\'s matches drops whoever contradicts the wish', () {
    final Person owner = person(
      id: 'owner',
      cardOwnerUid: 'uid-1',
      prefMarital: const <MaritalStatus>[MaritalStatus.single],
    );
    final List<Person> ranked = MatchSuggestionUtils.ranked(
      source: owner,
      people: <Person>[divorced, unknownStatus, single],
    );
    expect(ranked.map((Person p) => p.id), <String>['single', 'unknown']);
  });
}
