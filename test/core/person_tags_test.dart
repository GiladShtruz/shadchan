import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/community_tags_service.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_tags.dart';

Person _person(String id, List<String> tags, {String? city}) {
  final DateTime now = DateTime(2026, 9, 25);
  return Person(
    id: id,
    firstName: 'שם',
    lastName: id,
    gender: Gender.female,
    city: city,
    tags: tags,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('which tags may inspire other matchmakers', () {
    test('general words pass', () {
      for (final String tag in <String>[
        'חו״ל',
        'טבע',
        'עירוניסט/ית',
        'רוחני/ת',
        'חברתית',
      ]) {
        expect(PersonTags.isCommunityShareable(tag), isTrue, reason: tag);
      }
    });

    test('a personal circle stays private', () {
      for (final String tag in <String>[
        'חברים מהישיבה',
        'חברה מהעבודה',
        'ישיבת הר עציון',
        'מדרשת לינדנבאום',
        'בית אל',
        'מבית אל',
        'גרעין צפת',
        'מחזור 12',
        'קהילת הדר',
      ]) {
        expect(PersonTags.isCommunityShareable(tag), isFalse, reason: tag);
      }
    });

    test('a city from the matchmaker\'s own database is a place too', () {
      expect(
        PersonTags.isCommunityShareable('נווה צוף', knownPlaces: <String>[
          'נווה צוף',
        ]),
        isFalse,
      );
    });

    test('two spellings are one tag', () {
      expect(PersonTags.sameTag('חו"ל', 'חו״ל'), isTrue);
      expect(PersonTags.normalize('  טבע   ואהבה '), 'טבע ואהבה');
    });
  });

  test('what is published is the words, deduplicated, never the people', () {
    final List<String> words = CommunityTagsService.shareableTagsOf(<Person>[
      _person('a', <String>['טבע', 'חו"ל', 'חברים מהישיבה'], city: 'עפרה'),
      _person('b', <String>['חו״ל', 'עפרה']),
    ]);
    expect(words, <String>['חו״ל', 'טבע']);
  });

  test('tags and voice notes survive a backup', () {
    final Person person = _person('c', <String>['טבע', 'אמנות']);
    final Person? restored = BackupService.personFromJson(
      BackupService.personToJson(person),
    );
    expect(restored?.tags, <String>['טבע', 'אמנות']);

    final PersonNote note = PersonNote(
      id: 'n1',
      personId: 'c',
      text: '',
      createdAt: DateTime(2026, 9, 25),
      isAutomatic: false,
      audioFile: 'rec_1.m4a',
      audioDurationMs: 4200,
    );
    final PersonNote? back = BackupService.personNoteFromJson(
      BackupService.personNoteToJson(note),
    );
    expect(back?.isVoice, isTrue);
    expect(back?.audioFile, 'rec_1.m4a');
    expect(back?.audioDurationMs, 4200);
  });

  test('WhatsApp voice notes are recognised as audio', () {
    expect(VoiceNoteStore.isAudioPath('/x/PTT-20260925-WA0003.opus'), isTrue);
    expect(VoiceNoteStore.isAudioPath('/x/photo.jpg'), isFalse);
  });
}
