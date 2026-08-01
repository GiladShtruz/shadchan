import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// Hebrew has no gender-neutral second person, so every sentence the app says
/// to the matchmaker — and every sentence it says *about* a candidate — has to
/// pick a form. Rather than duplicating whole strings, the app writes them once
/// with inline alternatives and resolves them here:
///
/// ```dart
/// GenderText.resolve('{ברוך|ברוכה} {הבא|הבאה}!', Gender.female); // ברוכה הבאה!
/// ```
///
/// A `{masculine|feminine}` group may appear anywhere in the string, as many
/// times as needed. Text outside the braces is left untouched, so a sentence
/// with no group at all is already gender-neutral and costs nothing.
abstract final class GenderText {
  /// Resolves every `{masculine|feminine}` group in [template] for [gender].
  ///
  /// [Gender.unknown] (and a null gender) reads as masculine, which is the
  /// Hebrew default the rest of the app already falls back to.
  static String resolve(String template, Gender? gender) {
    if (!template.contains('{')) {
      return template;
    }

    final bool female = gender == Gender.female;
    final StringBuffer out = StringBuffer();
    int index = 0;

    while (index < template.length) {
      final int open = template.indexOf('{', index);
      if (open < 0) {
        out.write(template.substring(index));
        break;
      }
      final int close = template.indexOf('}', open + 1);
      if (close < 0) {
        out.write(template.substring(index));
        break;
      }

      out.write(template.substring(index, open));
      final String group = template.substring(open + 1, close);
      final int separator = group.indexOf('|');
      if (separator < 0) {
        // Not an alternation — leave the braces as the author wrote them.
        out.write(template.substring(open, close + 1));
      } else {
        out.write(
          female
              ? group.substring(separator + 1)
              : group.substring(0, separator),
        );
      }
      index = close + 1;
    }

    return out.toString();
  }

  /// The short form used where only one word changes.
  static String pick(Gender? gender, String masculine, String feminine) {
    return gender == Gender.female ? feminine : masculine;
  }
}

/// Sugar so a template can be resolved where it is written.
extension GenderTextTemplate on String {
  /// Resolves this string's `{masculine|feminine}` groups for [gender].
  String forGender(Gender? gender) => GenderText.resolve(this, gender);

  /// Resolves this string for [person]'s gender.
  String forPerson(Person? person) => GenderText.resolve(this, person?.gender);
}
