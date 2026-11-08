import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/contacts_health.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('contacts_health_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('keeps numbers, a permission word and an error type only', () {
    ContactsHealth.resetForTest();
    ContactsHealth.recordPermission('granted');
    ContactsHealth.recordRead(deviceCount: 812, suitable: 640);
    ContactsHealth.recordFailure('platformexception');
    final Map<String, Object?> report = ContactsHealth.snapshot();
    expect(report['permission'], 'granted');
    expect(report['deviceCount'], 812);
    expect(report['suitable'], 640);
    expect(report['failure'], 'platformexception');
    expect(report.keys.toSet(), <String>{
      'permission',
      'readAt',
      'deviceCount',
      'suitable',
      'failedAt',
      'failure',
    });
  });

  test('is about this phone, so it never travels with the account', () {
    expect(AccountSyncCodec.isSyncedSetting(ContactsHealth.key), isFalse);
  });
}
