import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

/// The app's light/dark choice.
///
/// **Light unless the matchmaker chose dark, whatever the phone says.** The
/// app used to follow the device by default, so a phone left on dark mode
/// opened a cream-and-copper app in a palette nobody had chosen for it. Now
/// nothing is read from the device: a missing value, and the old "אוטומטי"
/// (`system`) that earlier builds could store, both mean light, and dark is a
/// deliberate choice in "התאמה אישית".
///
/// The key is a synced setting (see `AccountSyncCodec.isSyncedSetting`), so
/// the choice belongs to the account and follows it to every phone.
class ThemeModeProvider extends ChangeNotifier {
  ThemeModeProvider(this._box);

  static const String _themeModeKey = 'themeMode';

  final Box<dynamic> _box;

  /// The choice changed on another phone signed in to the same account.
  void notifySyncChange() => notifyListeners();

  ThemeMode get themeMode {
    final String? value = _box.get(_themeModeKey) as String?;
    return themeModeFromName(value);
  }

  bool get isDark => themeMode == ThemeMode.dark;

  Future<void> setThemeMode(ThemeMode mode) async {
    // Only two answers exist now; "system" would bring the device back in.
    final ThemeMode chosen = mode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    if (chosen == themeMode && _box.get(_themeModeKey) != null) {
      return;
    }

    await _box.put(_themeModeKey, chosen.name);
    notifyListeners();
  }

  @visibleForTesting
  static ThemeMode themeModeFromName(String? value) {
    return value == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }
}
