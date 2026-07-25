import 'package:shadchan/utils/enums.dart';

/// Bundled illustrated fallbacks for people who do not have a photo.
///
/// The saved value is an index rather than an asset path, so asset filenames
/// can be cleaned up later without invalidating existing cards.
abstract final class PersonAvatarAssets {
  static const List<String> male = <String>[
    'assets/male_pic/ChatGPT Image Jul 23, 2026, 11_03_20 PM (1).png',
    'assets/male_pic/ChatGPT Image Jul 23, 2026, 11_12_08 PM (1).png',
    'assets/male_pic/ChatGPT Image Jul 23, 2026, 11_12_08 PM (2).png',
    'assets/male_pic/ChatGPT Image Jul 23, 2026, 11_12_09 PM (4).png',
    'assets/male_pic/ChatGPT Image Jul 23, 2026, 11_12_10 PM (6).png',
  ];

  static const List<String> female = <String>[
    'assets/female_pic/ChatGPT Image Jul 23, 2026, 11_03_20 PM (2).png',
    'assets/female_pic/ChatGPT Image Jul 23, 2026, 11_12_09 PM (3).png',
    'assets/female_pic/ChatGPT Image Jul 23, 2026, 11_12_09 PM (5).png',
    'assets/female_pic/ChatGPT Image Jul 23, 2026, 11_12_10 PM (7).png',
  ];

  static List<String> forGender(Gender gender) {
    return switch (gender) {
      Gender.male => male,
      Gender.female => female,
      Gender.unknown => const <String>[],
    };
  }

  /// A stable pseudo-random initial choice. It feels random across contacts,
  /// but remains unchanged across launches and after backup restore.
  static int defaultIndex(String personId, Gender gender) {
    final List<String> assets = forGender(gender);
    if (assets.isEmpty) {
      return 0;
    }

    int hash = 0x811c9dc5;
    for (final int unit in '$personId:${gender.name}'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash % assets.length;
  }

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
