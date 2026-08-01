import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/parsed_person.dart';

/// Which imported records are allowed past the user without being looked at.
///
/// This is the rule that decides what enters the database unseen during a bulk
/// import, so it is written down as tests rather than left to the shape of a
/// screen. The two ways it can fail are opposites and both bad: too strict and
/// eighty records all demand review, defeating the import; too loose and a
/// guessed gender becomes a fact nobody ever checked.
void main() {
  ParsedPerson person({
    String? firstName = 'נועה',
    String? lastName = 'ברגר',
    int? age = 24,
    Gender? gender = Gender.female,
    Set<ParsedField> inferred = const <ParsedField>{},
  }) {
    return ParsedPerson(
      card: ParsedCard(
        firstName: firstName,
        lastName: lastName,
        age: age,
        gender: gender,
      ),
      inferredFields: inferred,
    );
  }

  group('a complete, fully stated record goes straight in', () {
    test('name, age and gender all read from the card', () {
      expect(person().needsReview, isFalse);
    });

    test('a missing last name does not hold it up', () {
      // Plenty of real cards give a first name only, and that is still a
      // usable person — the bar is what a proposal needs, not a full form.
      expect(person(lastName: null).needsReview, isFalse);
    });
  });

  group('anything derived is reviewed', () {
    test('a gender worked out from the first name', () {
      expect(
        person(inferred: <ParsedField>{ParsedField.gender}).needsReview,
        isTrue,
      );
    });

    test('an age worked out rather than stated', () {
      expect(
        person(inferred: <ParsedField>{ParsedField.age}).needsReview,
        isTrue,
      );
    });

    test('a field inferred outside the required three is not enough on its '
        'own to force review', () {
      expect(
        person(inferred: <ParsedField>{ParsedField.lastName}).needsReview,
        isFalse,
      );
    });
  });

  group('anything missing is reviewed', () {
    test('no gender', () {
      expect(person(gender: null).needsReview, isTrue);
    });

    test('no age', () {
      expect(person(age: null).needsReview, isTrue);
    });

    test('no first name', () {
      expect(person(firstName: null).needsReview, isTrue);
    });

    test('an empty first name counts as missing, not as present', () {
      expect(person(firstName: '').needsReview, isTrue);
    });

    test('an entirely empty record', () {
      expect(const ParsedPerson(card: ParsedCard()).needsReview, isTrue);
    });
  });
}
