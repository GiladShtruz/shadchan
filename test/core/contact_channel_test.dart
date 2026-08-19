import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/contact_channel.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  group('ContactChannels.forPhone', () {
    test('Israeli mobile numbers get WhatsApp', () {
      for (final String number in <String>[
        '0501234567',
        '052-123-4567',
        '053 1234567',
        '054-1234567',
        '055 123 4567',
        '058-1234567',
        '+972501234567',
        '972-50-1234567',
        '00972501234567',
      ]) {
        expect(
          ContactChannels.forPhone(number),
          ContactChannel.whatsapp,
          reason: number,
        );
      }
    });

    test('Israeli landlines and VoIP lines get SMS, not WhatsApp', () {
      // This is the whole point of the split: the app used to draw a WhatsApp
      // button on all of these, and it could only ever fail.
      for (final String number in <String>[
        '021234567',
        '03-1234567',
        '04 1234567',
        '081234567',
        '09-1234567',
        '073-1234567',
        '077-1234567',
        '+97231234567',
      ]) {
        expect(
          ContactChannels.forPhone(number),
          ContactChannel.sms,
          reason: number,
        );
      }
    });

    test('a number too short to dial abroad falls back to SMS', () {
      expect(ContactChannels.forPhone('1234'), ContactChannel.sms);
      expect(ContactChannels.forPhone('*2020'), ContactChannel.sms);
    });

    test('a foreign number keeps WhatsApp — nothing about it is knowable', () {
      expect(
        ContactChannels.forPhone('+1 415 555 0123'),
        ContactChannel.whatsapp,
      );
      expect(
        ContactChannels.forPhone('+44 7700 900123'),
        ContactChannel.whatsapp,
      );
    });

    test('no digits at all means there is nothing to offer', () {
      expect(ContactChannels.forPhone(null), ContactChannel.none);
      expect(ContactChannels.forPhone(''), ContactChannel.none);
      expect(ContactChannels.forPhone('   '), ContactChannel.none);
      expect(ContactChannels.forPhone('לא ידוע'), ContactChannel.none);
    });
  });

  test('a person created outside the database has no messaging channel', () {
    // Exactly what "הוספת שם מחוץ למאגר" produces: a name and a gender.
    final Person person = Person(
      id: 'outside',
      firstName: 'הלל',
      lastName: '',
      gender: Gender.male,
      createdAt: DateTime(2026, 8, 18),
      updatedAt: DateTime(2026, 8, 18),
    );

    expect(ContactChannels.forPerson(person), ContactChannel.none);

    person.phone = '0501234567';
    expect(ContactChannels.forPerson(person), ContactChannel.whatsapp);
  });
}
