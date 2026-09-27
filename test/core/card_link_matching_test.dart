import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/card_sync_engine.dart';
import 'package:shadchan/services/database_hash_upload.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

Person _p(
  String id, {
  String first = 'דניאל',
  String last = 'לוי',
  String? phone,
  bool hidden = false,
  String? owner,
  DateTime? updated,
}) {
  final DateTime at = updated ?? DateTime(2026, 1, 1);
  return Person(
    id: id,
    firstName: first,
    lastName: last,
    gender: Gender.male,
    phone: phone,
    hidden: hidden,
    cardOwnerUid: owner,
    createdAt: at,
    updatedAt: at,
  );
}

Person? _find(List<Person> people, {String? phone}) =>
    CardSyncEngine.findExisting(
      people,
      ownerUid: 'owner',
      ownerPhoneHash: PhoneIdentity.hash(phone),
      firstName: 'דניאל',
      lastName: 'לוי',
    );

void main() {
  group('CardSyncEngine.findExisting — no second record for one friend', () {
    test('the record already linked to the card wins', () {
      final List<Person> people = <Person>[
        _p('a', phone: '0501234567'),
        _p('b', owner: 'owner'),
      ];
      expect(_find(people, phone: '0501234567')!.id, 'b');
    });

    test('a saved number finds the friend, in any spelling', () {
      final List<Person> people = <Person>[
        _p('a', first: 'דני', phone: '+972-50-123-4567'),
      ];
      expect(_find(people, phone: '0501234567')!.id, 'a');
    });

    test('a visible record is preferred over a hidden one', () {
      final List<Person> people = <Person>[
        _p('hidden', phone: '0501234567', hidden: true),
        _p('visible', phone: '0501234567'),
      ];
      expect(_find(people, phone: '0501234567')!.id, 'visible');
    });

    test('a record linked to another card is never taken', () {
      final List<Person> people = <Person>[
        _p('a', phone: '0501234567', owner: 'somebody-else'),
      ];
      expect(_find(people, phone: '0501234567'), isNull);
    });

    test('the name alone matches only a record with no number', () {
      expect(_find(<Person>[_p('a')])!.id, 'a');
      expect(_find(<Person>[_p('a', phone: '0529999999')]), isNull);
    });

    test('two records with the name are ambiguous, so neither is taken', () {
      expect(_find(<Person>[_p('a'), _p('b')]), isNull);
    });

    test('nothing found means a new record', () {
      expect(_find(<Person>[_p('a', first: 'יוסי')]), isNull);
    });
  });

  group('DatabaseHashUpload.hashesOf', () {
    test('one hash per number, hidden records and bad numbers left out', () {
      final List<String> hashes = DatabaseHashUpload.hashesOf(<Person>[
        _p('a', phone: '050-1234567'),
        _p('b', phone: '+972501234567'),
        _p('c', phone: '0529999999', hidden: true),
        _p('d', phone: '12'),
        _p('e'),
      ]);
      expect(hashes, <String>[PhoneIdentity.hash('0501234567')!]);
    });
  });
}
