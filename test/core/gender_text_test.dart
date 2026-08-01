import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';

/// Every sentence the app addresses to the matchmaker is written once, with the
/// two Hebrew forms inline. These lock down the resolver and the one place that
/// stores a whole list of such sentences.
void main() {
  group('GenderText.resolve', () {
    test(
      'picks the masculine form by default and the feminine for a woman',
      () {
        const String template = '{ברוך הבא|ברוכה הבאה} שדכן!';
        expect(template.forGender(Gender.male), 'ברוך הבא שדכן!');
        expect(template.forGender(Gender.female), 'ברוכה הבאה שדכן!');
      },
    );

    test('an unknown or missing gender reads as masculine', () {
      const String template = '{נסה|נסי} שוב';
      expect(template.forGender(null), 'נסה שוב');
      expect(template.forGender(Gender.unknown), 'נסה שוב');
    });

    test('resolves every group in a sentence and leaves the rest alone', () {
      const String template =
          '{שמור|שמרי} על דיסקרטיות — אמון הוא כלי {של שדכן|של שדכנית}.';
      expect(
        template.forGender(Gender.female),
        'שמרי על דיסקרטיות — אמון הוא כלי של שדכנית.',
      );
    });

    test('a sentence with no groups comes back untouched', () {
      const String plain =
          'אנשים משתנים. מה שלא התאים לפני שנה יכול להתאים היום.';
      expect(plain.forGender(Gender.female), plain);
      expect(plain.forGender(Gender.male), plain);
    });

    test('an unclosed or separator-less brace is left as written', () {
      expect('עלות {50'.forGender(Gender.female), 'עלות {50');
      expect('{שלום}'.forGender(Gender.female), '{שלום}');
    });
  });

  test('every tip resolves cleanly for both genders', () {
    for (final String tip in MatchmakerTips.tips) {
      for (final Gender gender in <Gender>[Gender.male, Gender.female]) {
        final String resolved = tip.forGender(gender);
        expect(
          resolved,
          isNot(contains('{')),
          reason: 'tip left an unresolved group: $tip',
        );
        expect(resolved, isNot(contains('|')));
        expect(resolved.trim(), isNotEmpty);
      }
    }
  });
}
