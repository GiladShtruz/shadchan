import 'package:shadchan/utils/enums.dart';

/// The fixed bundled fallbacks for people who do not have a photo.
///
/// There is intentionally exactly one avatar per gender. [avatarIndex] remains
/// in the persisted model only for backwards compatibility with older data.
abstract final class PersonAvatarAssets {
  static const List<String> male = <String>[
    'assets/male_pic/default_male_avatar.png',
  ];

  static const List<String> female = <String>[
    'assets/female_pic/default_female_avatar.png',
  ];

  static List<String> forGender(Gender gender) {
    return switch (gender) {
      Gender.male => male,
      Gender.female => female,
      Gender.unknown => const <String>[],
    };
  }

  /// Kept as an API for existing constructors; there is no longer a choice.
  static int defaultIndex(String _, Gender _) => 0;

  static int normalizedIndex(int index, Gender gender) {
    final int count = forGender(gender).length;
    if (count == 0) {
      return 0;
    }
    return index % count;
  }

  static String? pathFor(Gender gender, int index) {
    final List<String> assets = forGender(gender);
    if (assets.isEmpty) {
      return null;
    }
    return assets[normalizedIndex(index, gender)];
  }
}
