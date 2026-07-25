import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';

/// Which religious styles this matchmaker actually works with. Only the chosen
/// ones are offered when editing a person or filtering the database, so the
/// chip lists stay short and relevant.
///
/// Alongside the built-in styles the matchmaker can add their own labels
/// ("אחר"); a person tagged with one is stored as [ReligiousLevel.other] plus
/// the label itself.
class ReligiousLevelsProvider extends ChangeNotifier {
  ReligiousLevelsProvider(this._box);

  static const String _enabledKey = 'religiousLevels.enabled';
  static const String _customKey = 'religiousLevels.custom';

  /// What a new matchmaker starts with; everything else is opt-in.
  static const List<ReligiousLevel> defaultLevels = <ReligiousLevel>[
    ReligiousLevel.haredi,
    ReligiousLevel.datiLeumiTorani,
    ReligiousLevel.datiLeumi,
    ReligiousLevel.datiOpen,
    ReligiousLevel.hiloni,
  ];

  /// The styles that can be switched on, in display order. [ReligiousLevel.other]
  /// is not one of them — it stands for the custom labels below.
  static final List<ReligiousLevel> selectableLevels = ReligiousLevel.values
      .where((ReligiousLevel level) => level != ReligiousLevel.other)
      .toList();

  final Box<dynamic> _box;

  List<ReligiousLevel> get enabledLevels {
    final Object? raw = _box.get(_enabledKey);
    if (raw is! Iterable) {
      return defaultLevels;
    }

    final Set<String> names = raw.whereType<String>().toSet();
    return selectableLevels
        .where((ReligiousLevel level) => names.contains(level.name))
        .toList();
  }

  List<String> get customLabels {
    final Object? raw = _box.get(_customKey);
    if (raw is! Iterable) {
      return const <String>[];
    }
    return raw
        .whereType<String>()
        .map((String label) => label.trim())
        .where((String label) => label.isNotEmpty)
        .toList();
  }

  bool isEnabled(ReligiousLevel level) => enabledLevels.contains(level);

  Future<void> setEnabled(ReligiousLevel level, bool enabled) async {
    final Set<ReligiousLevel> next = enabledLevels.toSet();
    if (enabled) {
      next.add(level);
    } else {
      next.remove(level);
    }
    await _saveEnabled(next);
  }

  Future<void> addCustomLabel(String label) async {
    final String trimmed = label.trim();
    if (trimmed.isEmpty || customLabels.contains(trimmed)) {
      return;
    }
    await _box.put(_customKey, <String>[...customLabels, trimmed]);
    notifyListeners();
  }

  Future<void> removeCustomLabel(String label) async {
    final List<String> next = customLabels
        .where((String item) => item != label)
        .toList();
    await _box.put(_customKey, next);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await _saveEnabled(defaultLevels.toSet());
  }

  Future<void> _saveEnabled(Set<ReligiousLevel> levels) async {
    await _box.put(
      _enabledKey,
      selectableLevels
          .where(levels.contains)
          .map((ReligiousLevel level) => level.name)
          .toList(),
    );
    notifyListeners();
  }
}
