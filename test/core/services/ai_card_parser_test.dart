import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';

/// The gates between Gemini's answer and a person in the database.
///
/// Everything here runs offline against a JSON string, because the part worth
/// protecting is not whether the model answers well — that is checked against
/// the real API — but what happens to the answer afterwards. A model that
/// invents an age of 300, replies in metres, or returns something that is not
/// JSON at all must never reach a field, and must never take the form down
/// with it. These are the failures nobody would notice breaking later.
String _json(Map<String, Object?> fields) => jsonEncode(fields);

void main() {
  group('decodeResponse maps a well-formed answer', () {
    test('reads every field the model filled in', () {
      final ParsedCard card = AiCardParser.decodeResponse(
        _json(<String, Object?>{
          'firstName': 'יוסי',
          'lastName': 'כהן',
          'age': 27,
          'gender': 'male',
          'city': 'בני ברק',
          'heightCm': 178,
          'maritalStatus': 'single',
          'inquiryContactName': 'רחל',
          'inquiryContactPhone': '052-1234567',
        }),
      );

      expect(card.firstName, 'יוסי');
      expect(card.lastName, 'כהן');
      expect(card.age, 27);
      expect(card.gender, Gender.male);
      expect(card.city, 'בני ברק');
      expect(card.heightCm, 178);
      expect(card.maritalStatus, MaritalStatus.single);
      expect(card.inquiryContactName, 'רחל');
      // Normalized on the way in, like a hand-typed number would be.
      expect(card.inquiryContactPhone, '0521234567');
    });

    test('a card with every field null comes back empty, not broken', () {
      final ParsedCard card = AiCardParser.decodeResponse(
        _json(<String, Object?>{
          'firstName': null,
          'lastName': null,
          'age': null,
          'gender': null,
          'city': null,
          'heightCm': null,
          'maritalStatus': null,
          'inquiryContactName': null,
          'inquiryContactPhone': null,
        }),
      );

      expect(card.isEmpty, isTrue);
    });

    test('an unrecognised enum value is dropped rather than guessed', () {
      final ParsedCard card = AiCardParser.decodeResponse(
        _json(<String, Object?>{
          'firstName': 'שי',
          'gender': 'other',
          'maritalStatus': 'engaged',
        }),
      );

      expect(card.firstName, 'שי');
      expect(card.gender, isNull);
      expect(card.maritalStatus, isNull);
    });

    test('numbers written as text still count', () {
      final ParsedCard card = AiCardParser.decodeResponse(
        _json(<String, Object?>{'age': '27', 'heightCm': '178'}),
      );

      expect(card.age, 27);
      expect(card.heightCm, 178);
    });
  });

  group('decodeResponse survives a bad answer', () {
    test('text that is not JSON yields an empty card instead of throwing', () {
      expect(
        AiCardParser.decodeResponse('sorry, I could not read that').isEmpty,
        isTrue,
      );
    });

    test('JSON that is not an object yields an empty card', () {
      expect(AiCardParser.decodeResponse('[1, 2, 3]').isEmpty, isTrue);
      expect(AiCardParser.decodeResponse('"just a string"').isEmpty, isTrue);
    });

    test('no answer at all yields an empty card', () {
      expect(AiCardParser.decodeResponse(null).isEmpty, isTrue);
      expect(AiCardParser.decodeResponse('   ').isEmpty, isTrue);
    });

    test('one unusable field does not cost the usable ones', () {
      final ParsedCard card = AiCardParser.decodeResponse(
        _json(<String, Object?>{
          'firstName': 'מירי',
          'city': 'אשדוד',
          'age': 300,
        }),
      );

      expect(card.firstName, 'מירי');
      expect(card.city, 'אשדוד');
      expect(card.age, isNull);
    });
  });

  group('heights arrive in whichever notation the model chose', () {
    test('metres are converted, not rounded into a giant', () {
      // The regression this guards: rounding 1.78 to an int first gives 2,
      // which then reads as two metres and produces a 200cm person.
      expect(
        AiCardParser.decodeResponse(
          _json(<String, Object?>{'heightCm': 1.78}),
        ).heightCm,
        178,
      );
      expect(
        AiCardParser.decodeResponse(
          _json(<String, Object?>{'heightCm': '1,78'}),
        ).heightCm,
        178,
      );
    });

    test('centimetres are left alone', () {
      expect(
        AiCardParser.decodeResponse(
          _json(<String, Object?>{'heightCm': 178}),
        ).heightCm,
        178,
      );
    });

    test('a height nobody has is dropped', () {
      expect(
        AiCardParser.decodeResponse(
          _json(<String, Object?>{'heightCm': 40}),
        ).heightCm,
        isNull,
      );
      expect(
        AiCardParser.decodeResponse(
          _json(<String, Object?>{'heightCm': 260}),
        ).heightCm,
        isNull,
      );
    });
  });

  group('CardParser.sanitize holds the same line for any parser', () {
    test('ages outside a plausible range are dropped', () {
      expect(CardParser.sanitize(const ParsedCard(age: 300)).age, isNull);
      expect(CardParser.sanitize(const ParsedCard(age: 3)).age, isNull);
      expect(CardParser.sanitize(const ParsedCard(age: 15)).age, 15);
      expect(CardParser.sanitize(const ParsedCard(age: 99)).age, 99);
    });

    test('blank and whitespace-only text becomes null', () {
      final ParsedCard card = CardParser.sanitize(
        const ParsedCard(firstName: '  ', lastName: '', city: '  חיפה  '),
      );

      expect(card.firstName, isNull);
      expect(card.lastName, isNull);
      expect(card.city, 'חיפה');
    });

    test('phone numbers are normalized, and unusable ones dropped', () {
      expect(
        CardParser.sanitize(
          const ParsedCard(inquiryContactPhone: '052-123-4567'),
        ).inquiryContactPhone,
        '0521234567',
      );
      expect(
        CardParser.sanitize(
          const ParsedCard(inquiryContactPhone: '+972521234567'),
        ).inquiryContactPhone,
        '0521234567',
      );
      expect(
        CardParser.sanitize(
          const ParsedCard(inquiryContactPhone: '12345'),
        ).inquiryContactPhone,
        isNull,
      );
    });

    test('choices the model is allowed to make are passed through', () {
      final ParsedCard card = CardParser.sanitize(
        const ParsedCard(
          gender: Gender.female,
          maritalStatus: MaritalStatus.divorced,
        ),
      );

      expect(card.gender, Gender.female);
      expect(card.maritalStatus, MaritalStatus.divorced);
    });
  });
}
