import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/auto_match_rules.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_preferences.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// "סינון אוטומטי בהתאמות": the automatic filter's age rule and style table,
/// the matchmaker's own to change — and exactly the old rules until they do.
void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('auto_match_rules_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(PersonAdapter().typeId)) {
      Hive.registerAdapter(PersonAdapter());
      Hive.registerAdapter(GenderAdapter());
      Hive.registerAdapter(ReligiousLevelAdapter());
      Hive.registerAdapter(ProfileStatusAdapter());
      Hive.registerAdapter(MaritalStatusAdapter());
      Hive.registerAdapter(MatchContactAdapter());
      Hive.registerAdapter(RegionAdapter());
    }
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await Future<void>.delayed(Duration.zero);
    await Hive.box<dynamic>('settings').clear();
    AutoMatchRules.forgetCache();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Person person(String id, Gender gender, int age, ReligiousLevel level) =>
      Person(
        id: id,
        firstName: id,
        lastName: 'x',
        gender: gender,
        manualAge: age,
        religiousLevel: level,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('the defaults are the rules the app always had', () {
    expect(AutoMatchRules.current.isDefault, isTrue);
    expect(MatchSuggestionUtils.femaleAgeRangeForMale(25), (
      minAge: 20,
      maxAge: 26,
    ));
    expect(MatchSuggestionUtils.femaleAgeRangeForMale(35), (
      minAge: 28,
      maxAge: 37,
    ));
    expect(MatchSuggestionUtils.femaleAgeRangeForMale(45), (
      minAge: 33,
      maxAge: 50,
    ));
    expect(
      MatchPreferences.defaultReligiousLevelsFor(ReligiousLevel.datiOpen),
      <ReligiousLevel>[ReligiousLevel.datiOpen, ReligiousLevel.datiLeumi],
    );
  });

  test('a changed rule is what the automatic filter uses', () {
    final Person man = person('m', Gender.male, 28, ReligiousLevel.haredi);
    final Person woman = person('w', Gender.female, 30, ReligiousLevel.chardal);
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(
        source: man,
        candidate: woman,
      ),
      isFalse,
    );

    AutoMatchRules.save(
      AutoMatchRules.current
          .withBand(AgeBandKind.upTo30, const AgeBand(younger: 5, older: 3))
          .withStyles(ReligiousLevel.haredi, <ReligiousLevel>[
            ReligiousLevel.chardal,
          ])
          .withStyles(ReligiousLevel.chardal, <ReligiousLevel>[
            ReligiousLevel.haredi,
          ]),
    );
    expect(MatchSuggestionUtils.femaleAgeRangeForMale(28), (
      minAge: 23,
      maxAge: 31,
    ));
    // The style itself is always included.
    expect(
      MatchPreferences.defaultReligiousLevelsFor(ReligiousLevel.haredi),
      <ReligiousLevel>[ReligiousLevel.haredi, ReligiousLevel.chardal],
    );
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(
        source: man,
        candidate: woman,
      ),
      isTrue,
    );
    // And the woman's side follows the same age rule (and its own row of the
    // style table).
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(
        source: woman,
        candidate: man,
      ),
      isTrue,
    );

    AutoMatchRules.reset();
    expect(AutoMatchRules.current.isDefault, isTrue);
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(
        source: man,
        candidate: woman,
      ),
      isFalse,
    );
  });

  test('a stored copy round-trips, and a broken one is the default', () {
    final AutoMatchRules changed = AutoMatchRules.defaults.withBand(
      AgeBandKind.over40,
      const AgeBand(younger: 15, older: 8),
    );
    expect(AutoMatchRules.fromJson(changed.toJson()), changed);
    expect(AutoMatchRules.fromJson('nonsense'), AutoMatchRules.defaults);
    expect(
      AutoMatchRules.fromJson(<String, Object?>{
        'ages': <String, Object?>{'over40': 'x'},
      }),
      AutoMatchRules.defaults,
    );
  });
}
