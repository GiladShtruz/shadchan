import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/app_update_prompt.dart';
import 'package:upgrader/upgrader.dart';

void main() {
  test('Every message the update dialog can show is written in Hebrew', () {
    final HebrewUpgraderMessages messages = HebrewUpgraderMessages();

    for (final UpgraderMessage key in UpgraderMessage.values) {
      final String? text = messages.message(key);
      expect(text, isNotNull, reason: key.name);
      expect(text, isNotEmpty, reason: key.name);
      // The package falls back to English for any key a subclass forgets, and
      // English is the one thing this app never shows. 0x0590-0x05FF is the
      // Hebrew Unicode block.
      expect(
        text!.runes.any((int rune) => rune >= 0x0590 && rune <= 0x05FF),
        isTrue,
        reason: '${key.name}: "$text"',
      );
    }
  });

  test('The dialog body still carries both version placeholders', () {
    // `Upgrader.body` substitutes these. Dropping one would silently turn the
    // dialog into "there is a new version" with no way to see which.
    final String body = HebrewUpgraderMessages().body;

    expect(body, contains('{{currentAppStoreVersion}}'));
    expect(body, contains('{{currentInstalledVersion}}'));
  });

  testWidgets('Disabled, the prompt is its child and nothing else', (
    WidgetTester tester,
  ) async {
    // This is the seam every widget test that pumps `App` relies on: enabled,
    // the upgrader reaches SharedPreferences and an http client, neither of
    // which exists under `flutter test`.
    await tester.pumpWidget(
      const MaterialApp(
        home: AppUpdatePrompt(enabled: false, child: Text('תוכן האפליקציה')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('תוכן האפליקציה'), findsOneWidget);
    expect(find.byType(UpgradeAlert), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
