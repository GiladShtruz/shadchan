import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';

/// Turning an exported chat into messages.
///
/// Every failure this guards is silent. An export whose header format is not
/// recognised parses as one enormous message instead of none, so it looks like
/// it worked. Direction marks are invisible, so a pattern they break looks
/// correct in the editor. And a card written across eight lines becomes eight
/// unusable fragments if continuation is dropped.
void main() {
  const String he = 'היי, יש הצעה: יוסי כהן, בן 27, בני ברק';

  group('recognises both export formats', () {
    test('the Android shape', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:49 - רחל שדכנית: $he',
      );

      expect(chat.messages, hasLength(1));
      expect(chat.messages.single.sender, 'רחל שדכנית');
      expect(chat.messages.single.text, he);
      expect(chat.messages.single.sentAt, DateTime(2024, 2, 17, 15, 49));
    });

    test('the iOS shape, with its brackets and seconds', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '[17/2/2024, 15:49:30] רחל שדכנית: $he',
      );

      expect(chat.messages, hasLength(1));
      expect(chat.messages.single.sender, 'רחל שדכנית');
      expect(chat.messages.single.text, he);
    });

    test('a two-digit year is this century', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17/2/24, 15:49 - רחל: שלום',
      );

      expect(chat.messages.single.sentAt?.year, 2024);
    });
  });

  group('Hebrew exports survive', () {
    test('invisible direction marks do not stop a line being a message', () {
      // A real Hebrew export puts ‏ in front of the timestamp; leaving it
      // in makes the anchored pattern miss and the line reads as continuation.
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '‏17.2.2024, 15:49 - ‎רחל: $he',
      );

      expect(chat.messages, hasLength(1));
      expect(chat.messages.single.sender, 'רחל');
    });

    test('a byte order mark does not swallow the first message', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '﻿17.2.2024, 15:49 - רחל: $he',
      );

      expect(chat.messages, hasLength(1));
    });
  });

  group('cards written across many lines stay whole', () {
    test('continuation lines join the message above', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:49 - רחל: כרטיסייה\n'
        'שם: יוסי כהן\n'
        'גיל: 27\n'
        'עיר: בני ברק\n'
        '17.2.2024, 15:52 - רחל: עוד אחת',
      );

      expect(chat.messages, hasLength(2));
      expect(chat.messages.first.text, contains('גיל: 27'));
      expect(chat.messages.first.text, contains('עיר: בני ברק'));
      expect(chat.messages.last.text, 'עוד אחת');
    });

    test('lines before the first header are not invented into a message', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        'ההודעות מוצפנות מקצה לקצה\n'
        '17.2.2024, 15:49 - רחל: שלום',
      );

      expect(chat.messages, hasLength(1));
      expect(chat.messages.single.text, 'שלום');
    });
  });

  group('attachments are named, never sent', () {
    test('a message naming an extracted file carries that name', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:49 - רחל: IMG-20240217-WA0001.jpg (קובץ מצורף)\n'
        'התמונה של יוסי',
        mediaPaths: const <String, String>{
          'IMG-20240217-WA0001.jpg': '/tmp/IMG-20240217-WA0001.jpg',
        },
      );

      expect(chat.messages.single.attachmentName, 'IMG-20240217-WA0001.jpg');
      // The marker itself is noise to a reader; the words around it are not.
      expect(chat.messages.single.text, 'התמונה של יוסי');
    });

    test('a media placeholder leaves no empty message behind', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:49 - רחל: <המדיה לא נכללה>',
      );

      expect(chat.messages, isEmpty);
    });

    test('a file the export did not contain is not claimed as an attachment', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:49 - רחל: IMG-99999999-WA9999.jpg (קובץ מצורף) ראה תמונה',
      );

      expect(chat.messages.single.attachmentName, isNull);
    });
  });

  group('only messages worth paying for are sent', () {
    test('chatter and system lines are dropped, cards are kept', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:00 - רחל: ההודעות והשיחות מוצפנות מקצה לקצה, אף אחד לא יכול לקרוא\n'
        '17.2.2024, 15:01 - מירי: תודה\n'
        '17.2.2024, 15:02 - רחל: יוסי כהן, בחור רציני בן 27 מבני ברק, רווק\n'
        '17.2.2024, 15:03 - מירי: הודעה זו נמחקה\n'
        '17.2.2024, 15:04 - מירי: אשאל ואחזור אלייך בהקדם האפשרי מאוד תודה',
      );

      final List<String> kept = chat.candidateMessages
          .map((({int index, WhatsAppMessage message}) e) => e.message.text)
          .toList();

      expect(kept, hasLength(2));
      expect(kept.first, contains('יוסי כהן'));
      // Short chatter and the deletion tombstone are gone; a long, ordinary
      // reply survives, because the filter must never risk a real card.
      expect(kept.last, contains('אשאל ואחזור'));
    });

    test('a photo message is kept even though it has no text at all', () {
      // This is the one the length rule would throw away, and it is exactly
      // what the model needs in order to say whose photo it is.
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:02 - רחל: IMG-1.jpg (קובץ מצורף)',
        mediaPaths: const <String, String>{'IMG-1.jpg': '/tmp/IMG-1.jpg'},
      );

      expect(chat.candidateMessages, hasLength(1));
      expect(chat.candidateMessages.single.message.text, isEmpty);
    });
  });

  group('the transcript keeps position and file names', () {
    test('lines are numbered by their place in the whole chat, not the '
        'filtered list', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:00 - מירי: קצר\n'
        '17.2.2024, 15:02 - רחל: יוסי כהן, בחור רציני בן 27 מבני ברק, רווק',
      );

      final String transcript = WhatsAppChat.toTranscript(
        chat.candidateMessages,
      );

      // The dropped chatter still occupied index 0; renumbering would make
      // "the photo just before this card" point at the wrong message.
      expect(transcript, startsWith('#1 רחל:'));
    });

    test('an attachment is named in place so ordering carries meaning', () {
      final WhatsAppChat chat = WhatsAppImportService.parseText(
        '17.2.2024, 15:02 - רחל: IMG-1.jpg (קובץ מצורף)\n'
        '17.2.2024, 15:03 - רחל: יוסי כהן, בחור רציני בן 27 מבני ברק, רווק',
        mediaPaths: const <String, String>{'IMG-1.jpg': '/tmp/IMG-1.jpg'},
      );

      final String transcript = WhatsAppChat.toTranscript(
        chat.candidateMessages,
      );

      expect(transcript, contains('[קובץ מצורף: IMG-1.jpg]'));
      expect(
        transcript.indexOf('IMG-1.jpg'),
        lessThan(transcript.indexOf('יוסי כהן')),
      );
    });
  });

  group('a file name is found by its shape, not by the wording around it', () {
    const Map<String, String> media = <String, String>{
      'IMG-20240217-WA0001.jpg': '/tmp/IMG-20240217-WA0001.jpg',
    };

    for (final ({String label, String line}) shape
        in <({String label, String line})>[
          (
            label: 'the Android bare name',
            line: 'IMG-20240217-WA0001.jpg (קובץ מצורף)',
          ),
          (
            label: 'the iOS angle brackets',
            line: '<attached: IMG-20240217-WA0001.jpg>',
          ),
          (
            label: 'the Hebrew angle brackets',
            line: '<קובץ מצורף: IMG-20240217-WA0001.jpg>',
          ),
          (
            label: 'a name with words on both sides',
            line: 'הנה IMG-20240217-WA0001.jpg של יוסי',
          ),
        ]) {
      test(shape.label, () {
        final WhatsAppChat chat = WhatsAppImportService.parseText(
          '17.2.2024, 15:02 - רחל: ${shape.line}',
          mediaPaths: media,
        );

        expect(
          chat.messages.single.attachmentName,
          'IMG-20240217-WA0001.jpg',
          reason: shape.line,
        );
      });
    }
  });

  group('a chat longer than the ceiling', () {
    // Built once: 20,005 messages is a real parse, not a cheap one.
    late final WhatsAppChat chat = WhatsAppImportService.parseText(
      <String>[
        for (int i = 1; i <= WhatsAppImportService.maxMessages + 5; i++)
          '17.2.2024, 15:49 - רחל: הודעה מספר $i',
      ].join('\n'),
    );

    test('keeps the most recent messages, not the oldest', () {
      // An export is written oldest first, so keeping the *first* 20,000 — as
      // this did — threw away exactly the recent candidates somebody opened
      // the import for, and the review list looked like a complete success.
      expect(chat.messages, hasLength(WhatsAppImportService.maxMessages));
      expect(chat.messages.last.text, contains('מספר 20005'));
      expect(chat.messages.first.text, contains('מספר 6'));
    });

    test('says that it was cut', () {
      expect(chat.stats.truncatedMessages, isTrue);
    });
  });
}
