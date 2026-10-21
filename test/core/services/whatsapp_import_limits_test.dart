import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/ai_import_runner.dart';
import 'package:shadchan/services/ai_import_memory.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';
import 'package:shadchan/utils/ai_config.dart';

String _card(int index) =>
    'מועמד $index בחור רציני בן 27 מבני ברק רווק לומד בישיבה '
    'ומחפש התאמה רצינית לטווח ארוך';

WhatsAppChat _chat(int count) {
  final lines = <String>[
    for (int i = 0; i < count; i++)
      '${1 + (i ~/ 24)}.10.2026, '
      '${(i % 24).toString().padLeft(2, '0')}:00 - רחל: ${_card(i)}',
  ];
  return WhatsAppImportService.parseText(lines.join('\n'));
}

void main() {
  test('a 230-candidate export is limited to the newest 200', () {
    final plan = AiImportRunner.planChat(
      _chat(230),
      since: DateTime(2026, 10),
    );
    expect(plan.messageCount, AiConfig.maxWhatsappImportMessages);
    expect(plan.remaining, 30);
    expect(plan.batchCount, lessThanOrEqualTo(AiConfig.maxWhatsappRequests));
    expect(plan.batches.first.first.message.text, contains('מועמד 30 '));
    expect(plan.batches.last.last.message.text, contains('מועמד 229 '));
  });

  test('attempts to raise the message limit are clamped', () {
    final plan = AiImportRunner.planChat(_chat(230), maxMessages: 10000);
    expect(plan.messageCount, 200);
    expect(plan.remaining, 30);
  });

  test('date range filters before applying the 200-message limit', () {
    final chat = WhatsAppImportService.parseText(<String>[
      '1.1.2026, 10:00 - רחל: ${_card(1)}',
      '21.10.2026, 10:00 - רחל: ${_card(2)}',
    ].join('\n'));
    final plan = AiImportRunner.planChat(
      chat,
      since: DateTime(2026, 7, 22),
    );
    expect(plan.outsidePeriod, 1);
    expect(plan.messageCount, 1);
    expect(plan.batches.single.single.message.text, contains('מועמד 2 '));
  });

  test('unknown dates are counted, not silently called recent', () {
    final chat = WhatsAppChat(
      messages: <WhatsAppMessage>[
        WhatsAppMessage(sender: 'רחל', text: _card(3)),
      ],
      mediaPaths: const <String, String>{},
    );
    final recent = AiImportRunner.planChat(
      chat,
      since: DateTime(2026, 7, 22),
    );
    expect(recent.undated, 1);
    expect(recent.messageCount, 0);
    expect(AiImportRunner.planChat(chat).messageCount, 1);
  });

  test('processed messages are skipped before selecting the newest 200', () {
    final chat = _chat(230);
    final latest = chat.candidateMessages.last.message;
    final key = AiImportMemory.fingerprint(
      sender: latest.sender,
      text: latest.text,
      attachmentName: latest.attachmentName,
    );
    final plan = AiImportRunner.planChat(
      chat,
      alreadyImported: <String>{key},
    );
    expect(plan.skipped, 1);
    expect(plan.messageCount, 200);
    expect(plan.remaining, 29);
    expect(plan.batches.last.last.message.text, contains('מועמד 228 '));
  });
}
