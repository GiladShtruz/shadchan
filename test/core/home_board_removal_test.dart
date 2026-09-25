import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// "הסרה" on a board row: the row is off the board until whatever put it
/// there changes, or it is pinned again — and "ביטול" puts it straight back.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('board_removal_test');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() => HomeBoardStore.instance.reset());

  test('a removed row is remembered with when it was removed', () {
    final HomeBoardStore store = HomeBoardStore.instance;
    final String key = HomeBoardStore.itemKey(HomeItemKind.idea, 'm1');
    expect(store.hiddenAt(key), isNull);

    final DateTime before = DateTime.now();
    store.hide(key);
    final DateTime? at = store.hiddenAt(key);
    expect(at, isNotNull);
    expect(at!.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);

    store.unhide(key);
    expect(store.hiddenAt(key), isNull);
  });

  test('pinning a removed row brings it back', () {
    final HomeBoardStore store = HomeBoardStore.instance;
    final String key = HomeBoardStore.itemKey(HomeItemKind.person, 'p1');
    store.hide(key);
    store.add(HomeItemKind.person, 'p1');
    expect(store.hiddenAt(key), isNull);
    expect(store.contains(HomeItemKind.person, 'p1'), isTrue);
  });

  test('a suggested pair has a key of its own', () {
    expect(HomeBoardStore.pairKey('m', 'f'), 'pair:m|f');
    expect(
      HomeBoardStore.pairKey('m', 'f'),
      isNot(HomeBoardStore.itemKey(HomeItemKind.idea, 'm')),
    );
  });
}
