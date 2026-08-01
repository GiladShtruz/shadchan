import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/ai_people_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/parsed_person.dart';

/// What a batch answer becomes before anything reaches the database.
///
/// A bulk import is where records the user never opens can be written, so the
/// decisions here are the ones nobody is watching: how many people came back,
/// and which of them are allowed past review. Both are checked offline against
/// JSON, because the question is not whether the model reads a sheet well —
/// that is checked against the real API — but what this code concludes from
/// whatever it sends back.
String _people(List<Map<String, Object?>> entries) => jsonEncode(entries);

void main() {
  group('reads a batch', () {
    test('one object per person, in order', () {
      final List<ParsedPerson> people = AiPeopleParser.decodeResponse(
        _people(<Map<String, Object?>>[
          <String, Object?>{'firstName': 'יוסי', 'age': 27},
          <String, Object?>{'firstName': 'נועה', 'age': 24},
        ]),
      );

      expect(people, hasLength(2));
      expect(people.first.card.firstName, 'יוסי');
      expect(people.last.card.firstName, 'נועה');
    });

    test('an array wrapped in an object is still an array', () {
      final List<ParsedPerson> people = AiPeopleParser.decodeResponse(
        jsonEncode(<String, Object?>{
          'people': <Map<String, Object?>>[
            <String, Object?>{'firstName': 'שי'},
          ],
        }),
      );

      expect(people, hasLength(1));
      expect(people.single.card.firstName, 'שי');
    });

    test('rows that carry no person are dropped, not returned empty', () {
      // Headers, totals and blank separators come back as objects with nothing
      // in them; they must not become people.
      final List<ParsedPerson> people = AiPeopleParser.decodeResponse(
        _people(<Map<String, Object?>>[
          <String, Object?>{'firstName': 'יוסי'},
          <String, Object?>{},
          <String, Object?>{'firstName': null, 'age': null},
        ]),
      );

      expect(people, hasLength(1));
    });

    test('entries that are not objects are skipped without taking the rest '
        'down', () {
      final List<ParsedPerson> people = AiPeopleParser.decodeResponse(
        '[{"firstName":"יוסי"}, "nonsense", 42]',
      );

      expect(people, hasLength(1));
    });

    test('an unusable answer yields no people rather than an error', () {
      expect(AiPeopleParser.decodeResponse('not json'), isEmpty);
      expect(AiPeopleParser.decodeResponse(null), isEmpty);
      expect(AiPeopleParser.decodeResponse('   '), isEmpty);
      expect(AiPeopleParser.decodeResponse('{"unexpected": true}'), isEmpty);
    });

    test('the same range checks apply as for a single card', () {
      final ParsedPerson person = AiPeopleParser.decodeResponse(
        _people(<Map<String, Object?>>[
          <String, Object?>{'firstName': 'מירי', 'age': 300, 'heightCm': 1.63},
        ]),
      ).single;

      expect(person.card.age, isNull);
      expect(person.card.heightCm, 163);
    });
  });

  group('gender provenance decides who is reviewed', () {
    ParsedPerson decodeOne(Map<String, Object?> fields) =>
        AiPeopleParser.decodeResponse(
          _people(<Map<String, Object?>>[fields]),
        ).single;

    test('a stated gender on a complete record skips review', () {
      final ParsedPerson person = decodeOne(<String, Object?>{
        'firstName': 'יוסי',
        'age': 27,
        'gender': 'male',
        'genderSource': 'stated',
      });

      expect(person.inferredFields, isEmpty);
      expect(person.needsReview, isFalse);
    });

    test('a gender worked out from the name is reviewed', () {
      final ParsedPerson person = decodeOne(<String, Object?>{
        'firstName': 'נועה',
        'age': 24,
        'gender': 'female',
        'genderSource': 'inferred',
      });

      expect(person.card.gender, Gender.female);
      expect(person.inferredFields, contains(ParsedField.gender));
      expect(person.needsReview, isTrue);
    });

    test('a missing genderSource counts as inferred, not as stated', () {
      // The unsafe default would be the other way round: this flag is what
      // lets a record reach the database unseen, so silence must not grant it.
      final ParsedPerson person = decodeOne(<String, Object?>{
        'firstName': 'דוד',
        'age': 29,
        'gender': 'male',
      });

      expect(person.inferredFields, contains(ParsedField.gender));
      expect(person.needsReview, isTrue);
    });

    test('an unexpected genderSource value also counts as inferred', () {
      final ParsedPerson person = decodeOne(<String, Object?>{
        'firstName': 'דוד',
        'age': 29,
        'gender': 'male',
        'genderSource': 'probably',
      });

      expect(person.needsReview, isTrue);
    });

    test('no gender at all is reviewed, and claims nothing was inferred', () {
      final ParsedPerson person = decodeOne(<String, Object?>{
        'firstName': 'שי',
        'age': 26,
        'genderSource': 'stated',
      });

      expect(person.card.gender, isNull);
      expect(person.inferredFields, isEmpty);
      expect(person.needsReview, isTrue);
    });
  });
}
