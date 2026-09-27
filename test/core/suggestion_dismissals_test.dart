import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';

/// "לא מתאים" in a friend's matches: the candidate goes to the very end of the
/// list, so the stored order has to be the order things were turned down in.
void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('dismissals_');
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

  test('dismissals are kept in the order they were made', () async {
    await SuggestionDismissals.dismiss('p', 'a');
    await SuggestionDismissals.dismiss('p', 'b');
    await SuggestionDismissals.dismiss('p', 'c');

    expect(SuggestionDismissals.dismissedInOrder('p'), <String>['a', 'b', 'c']);
  });

  test('dismissing again moves a candidate to the end', () async {
    await SuggestionDismissals.dismiss('p', 'a');
    await SuggestionDismissals.dismiss('p', 'b');
    await SuggestionDismissals.dismiss('p', 'a');

    expect(SuggestionDismissals.dismissedInOrder('p'), <String>['b', 'a']);
  });

  test('restoring takes one candidate out and keeps the rest', () async {
    await SuggestionDismissals.dismiss('p', 'a');
    await SuggestionDismissals.dismiss('p', 'b');
    await SuggestionDismissals.restore('p', 'a');

    expect(SuggestionDismissals.dismissedInOrder('p'), <String>['b']);
    expect(SuggestionDismissals.isDismissed('p', 'a'), isFalse);
  });
}
