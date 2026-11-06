import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';

void main() {
  test('light unless dark was chosen, whatever the device says', () {
    expect(ThemeModeProvider.themeModeFromName(null), ThemeMode.light);
    // The old "אוטומטי" choice no longer follows the device.
    expect(ThemeModeProvider.themeModeFromName('system'), ThemeMode.light);
    expect(ThemeModeProvider.themeModeFromName('light'), ThemeMode.light);
    expect(ThemeModeProvider.themeModeFromName('dark'), ThemeMode.dark);
  });
}
