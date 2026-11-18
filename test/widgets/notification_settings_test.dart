import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/screens/settings_notifications_screen.dart';
import 'package:shadchan/services/notification_preferences.dart';
import 'package:shadchan/widgets/photo_share_switch.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('notif_settings');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Widget wrap(Widget child) => ChangeNotifierProvider<PersonalCardProvider>(
    create: (_) => PersonalCardProvider(Hive.box<dynamic>('settings')),
    child: MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );

  testWidgets('one switch per kind of notification, all on to begin with', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const SettingsNotificationsScreen()));
    for (final NotificationCategory c in NotificationCategory.values) {
      await tester.scrollUntilVisible(find.text(c.label), 100);
      expect(find.text(c.label), findsOneWidget);
    }
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((SwitchListTile t) => t.value),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text(NotificationCategory.newMatchmakers.label),
      -100,
    );
    await tester.tap(find.text(NotificationCategory.newMatchmakers.label));
    await tester.pump();
    expect(
      NotificationPreferences.instance.wants(
        NotificationCategory.newMatchmakers,
      ),
      isFalse,
    );
    NotificationPreferences.instance.set(
      NotificationCategory.newMatchmakers,
      enabled: true,
    );
  });

  testWidgets('"my photo may not be shared" explains itself before it is set', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(const Scaffold(body: Material(child: PhotoShareSwitch()))),
    );
    await tester.tap(find.text(PhotoShareSwitch.title));
    await tester.pumpAndSettle();
    // The explanation, and nothing saved yet.
    expect(find.textContaining('לא יצורפו'), findsOneWidget);
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
    final PersonalCardProvider cards = Provider.of<PersonalCardProvider>(
      tester.element(find.byType(PhotoShareSwitch)),
      listen: false,
    );
    expect(cards.photosShareable, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
