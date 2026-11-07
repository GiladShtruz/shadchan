import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/share_utils.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('card_share_test_');
  });

  tearDownAll(() async {
    await dir.delete(recursive: true);
  });

  test('every photo goes once, in order, and only photos that exist', () {
    final File a = File('${dir.path}/a.jpg')..writeAsBytesSync(<int>[1]);
    final File b = File('${dir.path}/b.jpg')..writeAsBytesSync(<int>[2]);
    final File empty = File('${dir.path}/empty.jpg')..writeAsBytesSync(<int>[]);
    expect(
      ShareUtils.existingPhotos(<String>[
        b.path,
        a.path,
        b.path,
        '${dir.path}/missing.jpg',
        empty.path,
        '',
      ]),
      <String>[b.path, a.path],
    );
  });

  test('a card with neither text nor photos is not shared at all', () async {
    expect(
      await ShareUtils.shareCard(text: '  ', photoPaths: const <String>[]),
      isFalse,
    );
  });
}
