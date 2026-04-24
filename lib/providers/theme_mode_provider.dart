import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeModeProvider extends ChangeNotifier {
  ThemeModeProvider(this._box);

  static const String _themeModeKey = 'themeMode';

  final Box<dynamic> _box;

  ThemeMode get themeMode {
    final String? value = _box.get(_themeModeKey) as String?;
    return _themeModeFromName(value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) {
      return;
    }

    await _box.put(_themeModeKey, mode.name);
    notifyListeners();
  }

  static ThemeMode _themeModeFromName(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
