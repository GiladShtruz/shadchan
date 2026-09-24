import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';

void main() {
  test('religious styles are one fixed global list', () {
    expect(ReligiousLevels.global, <ReligiousLevel>[
      ReligiousLevel.hiloni,
      ReligiousLevel.masorti,
      ReligiousLevel.datlashi,
      ReligiousLevel.datiOpen,
      ReligiousLevel.datiLeumi,
      ReligiousLevel.datiLeumiTorani,
      ReligiousLevel.chardal,
      ReligiousLevel.haredi,
    ]);
    expect(ReligiousLevels.isLegacy(ReligiousLevel.chabad), isTrue);
    expect(ReligiousLevels.isLegacy(ReligiousLevel.haredi), isFalse);
    expect(Regions.selectable, <Region>[
      Region.jerusalem,
      Region.center,
      Region.north,
      Region.south,
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
      'assets/male_pic/default_male_avatar.webp',
    ]);
    expect(PersonAvatarAssets.female, <String>[
      'assets/female_pic/default_female_avatar.webp',
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
