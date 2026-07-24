import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  group('CardParser', () {
    test('reads a fully labelled card', () {
      const String card = '''
שם: יוסי כהן
גיל: 27
גובה: 1.78
מצב משפחתי: רווק
מגורים: ירושלים
לבירורים: אמא שרה 052-1234567
''';

      final ParsedCard parsed = CardParser.parse(card);

      expect(parsed.firstName, 'יוסי');
      expect(parsed.lastName, 'כהן');
      expect(parsed.age, 27);
      expect(parsed.heightCm, 178);
      expect(parsed.maritalStatus, MaritalStatus.single);
      expect(parsed.gender, Gender.male);
      expect(parsed.city, 'ירושלים');
      expect(parsed.inquiryContactName, 'אמא שרה');
      expect(parsed.inquiryContactPhone, '0521234567');
    });

    test('reads a decorated card with centimeter heights', () {
      const String card = '''
*מיכל לוי בן דוד*
📌 גיל: 24
📍 גובה: 165 ס"מ
✅ מצב משפחתי: גרושה
🔹 עיר: פתח תקווה
טלפון: +972-52-765-4321
''';

      final ParsedCard parsed = CardParser.parse(card);

      expect(parsed.firstName, 'מיכל');
      expect(parsed.lastName, 'לוי בן דוד');
      expect(parsed.age, 24);
      expect(parsed.heightCm, 165);
      expect(parsed.maritalStatus, MaritalStatus.divorced);
      expect(parsed.gender, Gender.female);
      expect(parsed.city, 'פתח תקווה');
      expect(parsed.inquiryContactPhone, '0527654321');
    });

    test('falls back to free text phrasing', () {
      const String card =
          'בחורה בת 23, גרה בחיפה, גובה 1.62, רווקה. לפרטים 054-9876543';

      final ParsedCard parsed = CardParser.parse(card);

      expect(parsed.age, 23);
      expect(parsed.gender, Gender.female);
      expect(parsed.city, 'חיפה');
      expect(parsed.heightCm, 162);
      expect(parsed.maritalStatus, MaritalStatus.single);
      expect(parsed.inquiryContactPhone, '0549876543');
    });

    test('drops values that fail their sanity check', () {
      const String card = 'שם: דני\nגיל: 300\nגובה: 40';

      final ParsedCard parsed = CardParser.parse(card);

      expect(parsed.firstName, 'דני');
      expect(parsed.age, isNull);
      expect(parsed.heightCm, isNull);
    });

    test('returns nothing for empty text', () {
      expect(CardParser.parse('   ').isEmpty, isTrue);
    });
  });
}
