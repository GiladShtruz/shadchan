import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/screens/whatsapp_import_options_screen.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';

void main() {
  testWidgets('defaults to 90 days and offers all history', (tester) async {
    final chat = WhatsAppImportService.parseText(<String>[
      '1.1.2026, 10:00 - רחל: מועמד 1 בחור בן 27 מבני ברק רווק ומחפש שידוך',
      '21.10.2026, 10:00 - רחל: מועמד 2 בחור בן 28 מירושלים רווק ומחפש שידוך',
    ].join('\n'));

    await tester.pumpWidget(MaterialApp(
      home: WhatsAppImportOptionsScreen(
        chat: chat,
        alreadyImported: const <String>{},
        now: DateTime(2026, 10, 22),
      ),
    ));
    expect(find.text('הודעות לניתוח עכשיו: 1'), findsOneWidget);
    await tester.tap(find.text('כל ההיסטוריה'));
    await tester.pumpAndSettle();
    expect(find.text('הודעות לניתוח עכשיו: 2'), findsOneWidget);
    expect(find.text('נתחו 2 הודעות'), findsOneWidget);
  });
}
