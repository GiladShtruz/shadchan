import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/ai_import_memory.dart';
import 'package:shadchan/services/ai_import_runner.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';

/// One card, long enough to survive the substantive-message filter.
String _card(String name) =>
    '$name, בחור רציני בן 27 מבני ברק, רווק, לומד בישיבה, מחפש רצינית';

WhatsAppChat _chatOf(List<String> lines, {Map<String, String>? media}) =>
    WhatsAppImportService.parseText(
      lines.join('\n'),
      mediaPaths: media ?? const <String, String>{},
    );

void main() {
  group('a card the file repeats is paid for once', () {
    test('the same message forwarded twice survives only once', () {
      // The shape of a real matchmakers' group: one card passed along and
      // posted again by somebody else, word for word.
      final WhatsAppChat chat = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:30 - מירי: ${_card('יוסי כהן')}',
        '17.2.2024, 16:00 - רחל: ${_card('דוד לוי')}',
      ]);

      // Two of these are the same sender-and-text pair; the third is not.
      expect(chat.messages, hasLength(3));
      expect(chat.candidateMessages, hasLength(3));

      final WhatsAppChat repeated = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:30 - רחל: ${_card('יוסי כהן')}',
      ]);
      expect(repeated.candidateMessages, hasLength(1));
    });

    test('whitespace does not make two copies of a card into two cards', () {
      final WhatsAppChat chat = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:30 - רחל:  ${_card('יוסי כהן')}  ',
      ]);

      expect(chat.candidateMessages, hasLength(1));
    });

    test('the same words with a different photo stay two messages', () {
      // The failure this guards: a template card reused for two people, each
      // posted with their own picture. Collapsing them loses a person.
      final WhatsAppChat chat = _chatOf(
        <String>[
          '17.2.2024, 15:00 - רחל: IMG-1.jpg (קובץ מצורף)',
          '17.2.2024, 15:01 - רחל: IMG-2.jpg (קובץ מצורף)',
        ],
        media: const <String, String>{
          'IMG-1.jpg': '/tmp/IMG-1.jpg',
          'IMG-2.jpg': '/tmp/IMG-2.jpg',
        },
      );

      expect(chat.candidateMessages, hasLength(2));
    });

    test('a repeat by a different sender is kept — it is another broker', () {
      final WhatsAppChat chat = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:30 - מירי: ${_card('יוסי כהן')}',
      ]);

      expect(chat.candidateMessages, hasLength(2));
    });
  });

  group('the plan says what an import will cost before it runs', () {
    test('an untouched file plans every candidate into batches', () {
      final WhatsAppChat chat = _chatOf(<String>[
        for (int i = 0; i < 10; i++) '17.2.2024, 15:0$i - רחל: ${_card('א$i')}',
      ]);

      final AiImportPlan plan = AiImportRunner.planChat(chat);

      expect(plan.messageCount, 10);
      expect(plan.skipped, 0);
      expect(plan.isEmpty, isFalse);
      // Ten messages is well inside one batch, and the whole point of the
      // batch size is that a small file is one request.
      expect(plan.batchCount, 1);
    });

    test('messages already imported are dropped from the plan', () {
      final WhatsAppChat chat = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:01 - רחל: ${_card('דוד לוי')}',
      ]);

      final String seen = AiImportMemory.fingerprint(
        sender: 'רחל',
        text: _card('יוסי כהן'),
      );

      final AiImportPlan plan = AiImportRunner.planChat(
        chat,
        alreadyImported: <String>{seen},
      );

      expect(plan.skipped, 1);
      expect(plan.messageCount, 1);
      expect(
        plan.batches.single.single.message.text,
        contains('דוד לוי'),
      );
    });

    test('a re-export with nothing new in it plans no requests at all', () {
      // The ordinary case this whole mechanism exists for: the group exported
      // again a month later, with no new cards in it yet. It must cost zero
      // requests, and it must be distinguishable from "found nobody".
      final WhatsAppChat chat = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:01 - רחל: ${_card('דוד לוי')}',
      ]);

      final Set<String> everything = <String>{
        for (final ({int index, WhatsAppMessage message}) entry
            in chat.candidateMessages)
          AiImportMemory.fingerprint(
            sender: entry.message.sender,
            text: entry.message.text,
            attachmentName: entry.message.attachmentName,
          ),
      };

      final AiImportPlan plan = AiImportRunner.planChat(
        chat,
        alreadyImported: everything,
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.batchCount, 0);
      expect(plan.skipped, 2);
    });

    test('the text index still covers messages that were skipped', () {
      // A photo posted last month can belong to a card posted today, so the
      // model must still be able to quote a message the plan did not resend.
      final WhatsAppChat chat = _chatOf(<String>[
        '17.2.2024, 15:00 - רחל: ${_card('יוסי כהן')}',
        '17.2.2024, 15:01 - רחל: ${_card('דוד לוי')}',
      ]);

      final AiImportPlan plan = AiImportRunner.planChat(
        chat,
        alreadyImported: <String>{
          AiImportMemory.fingerprint(sender: 'רחל', text: _card('יוסי כהן')),
        },
      );

      expect(plan.messageTexts.values.join(), contains('יוסי כהן'));
    });
  });

  group('fingerprints identify a card across two exports', () {
    test('re-wrapped whitespace fingerprints the same', () {
      expect(
        AiImportMemory.fingerprint(sender: 'רחל', text: 'שורה  אחת\nושתיים'),
        AiImportMemory.fingerprint(sender: 'רחל', text: ' שורה אחת ושתיים '),
      );
    });

    test('the sender is part of the identity', () {
      expect(
        AiImportMemory.fingerprint(sender: 'רחל', text: 'אותו כרטיס'),
        isNot(AiImportMemory.fingerprint(sender: 'מירי', text: 'אותו כרטיס')),
      );
    });

    test('the attachment is part of the identity', () {
      expect(
        AiImportMemory.fingerprint(
          sender: 'רחל',
          text: '',
          attachmentName: 'IMG-1.jpg',
        ),
        isNot(
          AiImportMemory.fingerprint(
            sender: 'רחל',
            text: '',
            attachmentName: 'IMG-2.jpg',
          ),
        ),
      );
    });

    test('with no Hive box open, nothing is remembered and nothing throws', () {
      // The guard every store in this app carries: a test that wanted a parser
      // has not opened a box, and the app must simply pay full price rather
      // than fail.
      expect(AiImportMemory.seen(), isEmpty);
      expect(AiImportMemory.remember(<String>{'abc'}), completes);
    });
  });
}
