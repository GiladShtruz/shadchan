import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/utils/art_tint.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_search.dart';
import 'package:shadchan/widgets/card_invite.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 25);

  Person person(
    String id,
    String first, {
    String? city,
    String? description,
    Region? region,
    List<String> tags = const <String>[],
    bool hidden = false,
  }) {
    return Person(
      id: id,
      firstName: first,
      lastName: 'כהן',
      gender: Gender.female,
      city: city,
      description: description,
      region: region,
      tags: tags,
      hidden: hidden,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('HomeSearch', () {
    test(
      'finds a word in the card, the city and the notes, not only names',
      () {
        final List<Person> people = <Person>[
          person('a', 'רבקה', city: 'ירושלים'),
          person('b', 'שירה', description: 'בחורה שמחה, אוהבת טבע וטיולים'),
          person('c', 'נועה', region: Region.jerusalem),
          person('d', 'ירושלמית'),
          person('e', 'מוסתרת', city: 'ירושלים', hidden: true),
        ];
        final Map<String, List<PersonNote>> notes = <String, List<PersonNote>>{
          'b': <PersonNote>[
            PersonNote(
              id: 'n1',
              personId: 'b',
              text: 'אמרה שהיא גרה עכשיו בירושלים',
              createdAt: now,
              isAutomatic: false,
            ),
          ],
        };

        final HomeSearchResults results = HomeSearch.run(
          'ירושל',
          people,
          notesFor: (String id) => notes[id] ?? const <PersonNote>[],
        );

        // A name hit leads, on its own.
        expect(results.people.map((Person p) => p.id), <String>['d']);
        // And every other place the word appears is listed under it.
        expect(
          results.content.map(
            (ContentHit h) => '${h.person.id}:${h.field.name}',
          ),
          unorderedEquals(<String>['a:city', 'b:note', 'c:region']),
        );
        // A card outside the database is never searched.
        expect(
          results.content.any((ContentHit h) => h.person.id == 'e'),
          isFalse,
        );
        final ContentHit note = results.content.firstWhere(
          (ContentHit h) => h.field == HomeSearchField.note,
        );
        expect(note.noteId, 'n1');
        expect(note.field.focus, 'notes');
      },
    );

    test('an excerpt keeps the words around the match, and marks it', () {
      final SearchExcerpt excerpt = HomeSearch.excerptOf(
        'היא בחורה מקסימה מאוד, אוהבת מוזיקה, קריאה ובעיקר טבע וטיולים '
            'ארוכים בצפון עם חברות ומשפחה בכל סוף שבוע שיש לה',
        'טבע',
      )!;
      expect(excerpt.match, 'טבע');
      expect(excerpt.text.startsWith('…'), isTrue);
      expect(excerpt.text.endsWith('…'), isTrue);
      expect(excerpt.before.trim().isNotEmpty, isTrue);
      expect(excerpt.after.trim().isNotEmpty, isTrue);
    });

    test('niqqud and spacing do not hide a match', () {
      expect(HomeSearch.excerptOf('שָׂמֵחַ   ואופטימי', 'שמח'), isNotNull);
      expect(HomeSearch.excerptOf('אין כאן כלום', 'שמח'), isNull);
    });

    test('a short run of digits is not a phone search', () {
      final Person withPhone = Person(
        id: 'p',
        firstName: 'דנה',
        lastName: 'לוי',
        gender: Gender.female,
        phone: '0501234567',
        createdAt: now,
        updatedAt: now,
      );
      expect(
        HomeSearch.run('05', <Person>[
          withPhone,
        ], notesFor: (_) => const <PersonNote>[]).people,
        isEmpty,
      );
      expect(
        HomeSearch.run('1234', <Person>[
          withPhone,
        ], notesFor: (_) => const <PersonNote>[]).people,
        hasLength(1),
      );
    });
  });

  group('CardInviteFlow.inviteMessage', () {
    final Uri link = Uri.parse(
      'https://shadchan-gilad.web.app/join?from=abc&name=%D7%99',
    );

    test('addresses a man as a man', () {
      final String text = CardInviteFlow.inviteMessage(
        friendFirstName: 'יוסי',
        friendGender: Gender.male,
        myGender: Gender.male,
        link: link,
      );
      expect(text, startsWith('היי יוסי! אני משתמש ב״שדכן״'));
      expect(text, contains('שרק אתה מנהל ומעדכן'));
      expect(text, contains('לחברים שאתה בוחר'));
      expect(text, contains('$link'));
      expect(text.trim(), endsWith('יכול לעניין אותך?'));
    });

    test('addresses a woman as a woman, in the matchmaker\'s own voice', () {
      final String text = CardInviteFlow.inviteMessage(
        friendFirstName: 'שרה',
        friendGender: Gender.female,
        myGender: Gender.female,
        link: link,
      );
      expect(text, startsWith('היי שרה! אני משתמשת ב״שדכן״'));
      expect(text, contains('שרק את מנהלת ומעדכנת'));
      expect(text, contains('לחברים שאת בוחרת'));
    });
  });

  test('artTint turns a drawing\'s body colour into exactly the target', () {
    const Color target = Color(0xFFC1845B);
    const double body = 90;
    final ColorFilter filter = artTint(target, body);
    // A grey pixel exactly as light as the body lands on the target.
    final List<double> m = _matrixOf(filter);
    for (int channel = 0; channel < 3; channel++) {
      final List<double> row = m.sublist(channel * 5, channel * 5 + 5);
      final double out = row[0] * body + row[1] * body + row[2] * body + row[4];
      final double expected =
          <double>[target.r, target.g, target.b][channel] * 255;
      expect(out, closeTo(expected, 0.5));
    }
  });
}

List<double> _matrixOf(ColorFilter filter) {
  // `ColorFilter.matrix` keeps its values; read them back through toString,
  // which lists them, rather than reaching into private fields.
  final RegExpMatch? match = RegExp(r'\[(.*)\]').firstMatch(filter.toString());
  return match!
      .group(1)!
      .split(',')
      .map((String v) => double.parse(v.trim()))
      .toList();
}
