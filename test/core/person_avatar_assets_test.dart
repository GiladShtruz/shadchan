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

  test('a no-photo avatar is stable and belongs to the person gender', () {
    final DateTime now = DateTime(2026, 7, 26);
    final Person person = Person(
      id: 'stable-person',
      firstName: 'דוד',
      lastName: 'כהן',
      gender: Gender.male,
      createdAt: now,
      updatedAt: now,
    );

    expect(
      person.avatarIndex,
      inInclusiveRange(0, PersonAvatarAssets.male.length - 1),
    );
    expect(
      PersonAvatarAssets.pathFor(person.gender, person.avatarIndex),
      PersonAvatarAssets.male[person.avatarIndex],
    );

    final Person samePerson = Person(
      id: 'stable-person',
      firstName: 'דוד',
      lastName: 'כהן',
      gender: Gender.male,
      createdAt: now,
      updatedAt: now,
    );
    expect(samePerson.avatarIndex, person.avatarIndex);
  });
}
