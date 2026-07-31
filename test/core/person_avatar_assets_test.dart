import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';

void main() {
  test('religious styles start with the configured product defaults', () {
    expect(ReligiousLevelsProvider.defaultLevels, <ReligiousLevel>[
      ReligiousLevel.haredi,
      ReligiousLevel.datiLeumiTorani,
      ReligiousLevel.datiLeumi,
      ReligiousLevel.datiOpen,
      ReligiousLevel.hiloni,
    ]);
  });

  test('there is exactly one fixed no-photo avatar per gender', () {
    final DateTime now = DateTime(2026, 7, 26);
    final Person person = Person(
      id: 'stable-person',
      firstName: 'דוד',
      lastName: 'כהן',
      gender: Gender.male,
      createdAt: now,
      updatedAt: now,
    );

    expect(PersonAvatarAssets.male, <String>[
      'assets/male_pic/default_male_avatar.png',
    ]);
    expect(PersonAvatarAssets.female, <String>[
      'assets/female_pic/default_female_avatar.png',
    ]);
    expect(person.avatarIndex, 0);
    expect(
      PersonAvatarAssets.pathFor(person.gender, person.avatarIndex),
      PersonAvatarAssets.male.single,
    );
    expect(
      PersonAvatarAssets.pathFor(Gender.male, 999),
      PersonAvatarAssets.male.single,
    );
    expect(
      PersonAvatarAssets.pathFor(Gender.female, 999),
      PersonAvatarAssets.female.single,
    );
  });
}
