import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_duplicates.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 15);

  Person person(
    String id,
    String first,
    String last, {
    Gender gender = Gender.male,
  }) {
    return Person(
      id: id,
      firstName: first,
      lastName: last,
      gender: gender,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<String> similar(
    List<Person> people,
    String first,
    String last, {
    Gender gender = Gender.male,
  }) {
    return PersonDuplicates.similarTo(
      people,
      firstName: first,
      lastName: last,
      gender: gender,
    ).map((Person p) => p.id).toList();
  }

  group('the same person under a different spelling is found', () {
    final List<Person> people = <Person>[
      person('eli', 'אליהו', 'כהן'),
      person('sara', 'שרה', 'לוי', gender: Gender.female),
      person('yosef', 'יוסף', 'בן־דוד'),
    ];

    test('an identical name', () {
      expect(similar(people, 'אליהו', 'כהן'), <String>['eli']);
    });

    test('an extra vowel letter, spacing and a final letter', () {
      expect(similar(people, 'אליהוא', 'כהן'), <String>['eli']);
      expect(similar(people, ' יוסף ', 'בן דוד'), <String>['yosef']);
    });

    test('one typo in the name', () {
      expect(similar(people, 'שרה', 'לויי', gender: Gender.female), <String>[
        'sara',
      ]);
      expect(similar(people, 'אליחו', 'כהן'), <String>['eli']);
    });
  });

  group('different people are left alone', () {
    final List<Person> people = <Person>[
      person('eli', 'אליהו', 'כהן'),
      person('sara', 'שרה', 'לוי', gender: Gender.female),
    ];

    test('the same first name with another surname', () {
      expect(similar(people, 'אליהו', 'פרידמן'), isEmpty);
    });

    test('the other gender', () {
      expect(similar(people, 'שרה', 'לוי', gender: Gender.male), isEmpty);
    });

    test('a first name alone is never enough', () {
      expect(similar(people, 'אליהו', ''), isEmpty);
    });
  });

  test('merging fills gaps and never overwrites', () {
    final Person existing = person('eli', 'אליהו', 'כהן')
      ..city = 'ירושלים'
      ..description = 'בחור מקסים';
    final Person incoming = person('new', 'אליהו', 'כהן')
      ..city = 'בני ברק'
      ..phone = '0501234567'
      ..description = 'לומד בישיבה'
      ..photosPaths = <String>['a.jpg'];

    PersonMerge.fillGaps(existing, incoming);

    expect(existing.city, 'ירושלים');
    expect(existing.phone, '0501234567');
    expect(existing.description, 'בחור מקסים\n\nלומד בישיבה');
    expect(existing.photosPaths, <String>['a.jpg']);
  });
}
