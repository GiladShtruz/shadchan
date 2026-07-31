import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/reminder_alerts.dart';

/// The home screen's alert badge: raised when a reminder comes due, answered by
/// opening the card, and armed again by a new reminder date.
void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('reminder_alerts_');
    Hive.init(hiveDirectory.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  setUp(() async {
    await Hive.box<dynamic>('settings').clear();
  });

  final DateTime today = DateTime.now();
  final DateTime yesterday = today.subtract(const Duration(days: 1));
  final DateTime tomorrow = today.add(const Duration(days: 1));

  test('a reminder that has not come due raises nothing', () {
    expect(ReminderAlerts.isAlerting('m1', tomorrow), isFalse);
    expect(ReminderAlerts.isAlerting('m1', null), isFalse);
  });

  test('a due reminder alerts until the card is opened', () async {
    expect(ReminderAlerts.isAlerting('m1', yesterday), isTrue);

    await ReminderAlerts.markSeen('m1', yesterday);
    expect(ReminderAlerts.isAlerting('m1', yesterday), isFalse);
  });

  test('a new reminder date arms the alert again', () async {
    await ReminderAlerts.markSeen('m1', yesterday);

    final DateTime newDate = today.subtract(const Duration(days: 3));
    expect(ReminderAlerts.isAlerting('m1', newDate), isTrue);
  });

  test('opening a card before its reminder is due changes nothing', () async {
    await ReminderAlerts.markSeen('m1', tomorrow);

    // Once tomorrow's reminder comes due it must still raise the badge.
    expect(ReminderAlerts.isAlerting('m1', yesterday), isTrue);
  });

  test('a deleted card leaves no key behind', () async {
    await ReminderAlerts.markSeen('m1', yesterday);
    await ReminderAlerts.forget('m1');

    expect(ReminderAlerts.isAlerting('m1', yesterday), isTrue);
  });

  test('a reminder is due from the start of its own day', () {
    expect(ReminderAlerts.isDue(today), isTrue);
    expect(ReminderAlerts.isDue(yesterday), isTrue);
    expect(ReminderAlerts.isDue(tomorrow), isFalse);
    expect(ReminderAlerts.isDue(null), isFalse);
  });
}
