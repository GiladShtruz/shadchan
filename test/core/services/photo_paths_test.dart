import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/photo_picker_service.dart';

/// The basename is the identity a photo carries between devices — it is the
/// Cloud Storage object name, the ledger key and what every backed-up record
/// points at. Getting it wrong does not crash; it silently uploads the same
/// photo under a second name, or fails to find it on restore.
void main() {
  test('A POSIX path reduces to its file name', () {
    expect(
      PhotoPickerService.basenameOf(
        '/data/user/0/com.gilad.shadchan/app_flutter/photos/p1_1700000000_0.jpg',
      ),
      'p1_1700000000_0.jpg',
    );
  });

  test('A Windows path reduces to its file name', () {
    // Not hypothetical: the whole project is developed on Windows, and a Hive
    // box written by a desktop run carries backslash paths.
    expect(
      PhotoPickerService.basenameOf(
        r'C:\Users\gilad\Documents\photos\p1_1700000000_0.jpg',
      ),
      'p1_1700000000_0.jpg',
    );
  });

  test('A bare file name is already its own basename', () {
    // Restore hands these straight back through, so this must be idempotent.
    expect(PhotoPickerService.basenameOf('me_1.jpg'), 'me_1.jpg');
  });
}
