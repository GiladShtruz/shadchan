import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/hidden_helpers_store.dart';

void main() {
  late Directory dir;
  late Box<dynamic> settings;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('hidden_helpers_test_');
    Hive.init(dir.path);
    settings = await Hive.openBox<dynamic>('settings');
  });

  setUp(() async => settings.clear());

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('missing, malformed, and non-array values are harmless', () async {
    expect(HiddenHelpersStore.read(settings), isEmpty);
    await settings.put(HiddenHelpersStore.key, 'broken');
    expect(HiddenHelpersStore.read(settings), isEmpty);
    await settings.put(HiddenHelpersStore.key, '{}');
    expect(HiddenHelpersStore.read(settings), isEmpty);
  });

  test('IDs are deduplicated and blank / malformed entries ignored', () async {
    await settings.put(
      HiddenHelpersStore.key,
      '["matchmaker-1", "matchmaker-1", "", 42, null, "matchmaker-2"]',
    );
    expect(HiddenHelpersStore.read(settings), <String>{
      'matchmaker-1',
      'matchmaker-2',
    });
  });
}
