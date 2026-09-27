import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_tags.dart';

/// Cards already in the database that are probably the person being added.
///
/// **By name, and loosely.** The same friend arrives as "אליהו כהן" from the
/// address book and as "אליהוא כהן" from a WhatsApp card, or with a typo, or
/// with a stray geresh — so names are compared after normalising the spelling
/// differences Hebrew allows (niqqud, final letters, punctuation, spacing, the
/// vowel letters ו and י) and then allowed one slip, two in a long name. Only
/// the full name counts: two different people called "שרה" are the ordinary
/// case, not a duplicate.
///
/// A candidate of the other known gender is never offered.
abstract final class PersonDuplicates {
  static List<Person> similarTo(
    Iterable<Person> people, {
    required String firstName,
    required String lastName,
    required Gender gender,
    String? excludingId,
  }) {
    final String target = normalize('$firstName $lastName');
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      return const <Person>[];
    }
    return <Person>[
      for (final Person person in people)
        if (person.id != excludingId &&
            !_genderConflict(person.gender, gender) &&
            person.lastName.trim().isNotEmpty &&
            isSimilarName(target, normalize(person.fullName)))
          person,
    ];
  }

  static bool _genderConflict(Gender a, Gender b) =>
      a != Gender.unknown && b != Gender.unknown && a != b;

  /// Two already-[normalize]d names.
  static bool isSimilarName(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    if (a == b || _withoutVowelLetters(a) == _withoutVowelLetters(b)) {
      return true;
    }
    final int shorter = a.length < b.length ? a.length : b.length;
    if (shorter < 5) {
      return false;
    }
    return _distance(a, b, limit: shorter >= 10 ? 2 : 1) <=
        (shorter >= 10 ? 2 : 1);
  }

  /// Punctuation that differs between two spellings of one name. The maqaf is
  /// already inside the niqqud range [normalize] skips.
  static const Set<String> _ignored = <String>{
    '-',
    '_',
    "'",
    '"',
    '׳',
    '״',
    '.',
    ',',
    '(',
    ')',
  };

  static const Map<String, String> _finals = <String, String>{
    'ך': 'כ',
    'ם': 'מ',
    'ן': 'נ',
    'ף': 'פ',
    'ץ': 'צ',
  };

  /// Lower-cased, niqqud and punctuation stripped, final letters folded and
  /// all whitespace removed.
  static String normalize(String name) {
    final StringBuffer out = StringBuffer();
    for (final int rune in name.toLowerCase().runes) {
      final String char = String.fromCharCode(rune);
      // Niqqud and cantillation marks.
      if (rune >= 0x0591 && rune <= 0x05C7) {
        continue;
      }
      if (char.trim().isEmpty || _ignored.contains(char)) {
        continue;
      }
      out.write(_finals[char] ?? char);
    }
    return out.toString();
  }

  /// ו and י come and go in Hebrew spelling ("אליהו"/"אליהוא", "שרה"/"שרה׳"),
  /// so they are ignored except as a name's first letter.
  static String _withoutVowelLetters(String name) {
    if (name.length < 2) {
      return name;
    }
    return name[0] + name.substring(1).replaceAll(RegExp('[וי]'), '');
  }

  /// Levenshtein distance, giving up once every path exceeds [limit].
  static int _distance(String a, String b, {required int limit}) {
    if ((a.length - b.length).abs() > limit) {
      return limit + 1;
    }
    List<int> previous = List<int>.generate(b.length + 1, (int i) => i);
    for (int i = 1; i <= a.length; i++) {
      final List<int> current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      int rowMin = current[0];
      for (int j = 1; j <= b.length; j++) {
        final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final int value = <int>[
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((int x, int y) => x < y ? x : y);
        current[j] = value;
        if (value < rowMin) {
          rowMin = value;
        }
      }
      if (rowMin > limit) {
        return limit + 1;
      }
      previous = current;
    }
    return previous[b.length];
  }
}

/// Folds a new card into one that already exists, **without overwriting
/// anything**: a field the existing card already has stays as it is, and only
/// the gaps are filled from the new one. The card text is the exception — two
/// different texts are both kept, the new one under the old.
abstract final class PersonMerge {
  static void fillGaps(Person existing, Person incoming) {
    String? pick(String? current, String? next) =>
        (current ?? '').trim().isEmpty && (next ?? '').trim().isNotEmpty
        ? next
        : current;

    if (existing.lastName.trim().isEmpty) {
      existing.lastName = incoming.lastName;
    }
    if (existing.gender == Gender.unknown) {
      existing.gender = incoming.gender;
    }
    if (existing.age == null && incoming.manualAge != null) {
      existing.setManualAge(incoming.manualAge);
    }
    if (existing.religiousLevel == null && incoming.religiousLevel != null) {
      existing
        ..religiousLevel = incoming.religiousLevel
        ..religiousLevelOther = incoming.religiousLevelOther;
    }
    existing
      ..city = pick(existing.city, incoming.city)
      ..phone = pick(existing.phone, incoming.phone)
      ..source = pick(existing.source, incoming.source)
      ..notes = pick(existing.notes, incoming.notes)
      ..inquiryContactName = pick(
        existing.inquiryContactName,
        incoming.inquiryContactName,
      )
      ..inquiryContactPhone = pick(
        existing.inquiryContactPhone,
        incoming.inquiryContactPhone,
      )
      ..heightCm = existing.heightCm ?? incoming.heightCm
      ..maritalStatus = existing.maritalStatus ?? incoming.maritalStatus;

    final String oldText = (existing.description ?? '').trim();
    final String newText = (incoming.description ?? '').trim();
    if (newText.isNotEmpty && !oldText.contains(newText)) {
      existing.description = oldText.isEmpty ? newText : '$oldText\n\n$newText';
    }

    existing.photosPaths = <String>[
      ...existing.photosPaths,
      for (final String path in incoming.photosPaths)
        if (!existing.photosPaths.contains(path)) path,
    ];

    existing.tags = <String>[
      ...existing.tags,
      for (final String tag in incoming.tags)
        if (!existing.tags.any((String t) => PersonTags.sameTag(t, tag))) tag,
    ];
  }
}
