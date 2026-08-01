import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';

/// The matchmaker's own gender, wherever a sentence has to bend to it.
///
/// Hebrew makes the second person gendered, so any line the app addresses to
/// the matchmaker needs this. Written as an extension because the alternative
/// is threading a `Gender?` through every widget that happens to hold a
/// sentence.
extension UserGenderContext on BuildContext {
  /// Null when the gender is unknown *or* when the widget is being shown
  /// outside the app's provider tree — a shared widget carrying a sentence
  /// (an empty state, a dialog) must not fail to draw over a missing profile;
  /// [GenderText] already reads null as the masculine default.
  Gender? get userGender {
    try {
      return watch<UserProfileProvider>().gender;
    } on ProviderNotFoundException {
      return null;
    }
  }
}

/// Stores the profile of the matchmaker (the app's owner) collected during the
/// first-launch onboarding flow.
class UserProfileProvider extends ChangeNotifier {
  UserProfileProvider(this._box);

  static const String _nameKey = 'userName';
  static const String _genderKey = 'userGender';
  static const String _photoPathKey = 'userPhotoPath';
  static const String _isSingleKey = 'userIsSingle';
  static const String _personalCardKey = 'userPersonalCard';

  final Box<dynamic> _box;

  String? get name {
    final String? value = (_box.get(_nameKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Gender? get gender {
    final String? value = _box.get(_genderKey) as String?;
    return switch (value) {
      'male' => Gender.male,
      'female' => Gender.female,
      _ => null,
    };
  }

  String? get photoPath {
    final String? value = (_box.get(_photoPathKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Whether the matchmaker is looking for a match themselves. Off unless they
  /// say so, and the only thing that reveals the personal-card area on the
  /// profile screen.
  bool get isSingle => _box.get(_isSingleKey) as bool? ?? false;

  /// The matchmaker's own shidduch card, kept so they can share it in one tap
  /// the way they share a candidate's.
  String? get personalCard {
    final String? value = (_box.get(_personalCardKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Onboarding is complete once a name and gender have been provided. The photo
  /// is optional.
  bool get isOnboarded => name != null && gender != null;

  Future<void> saveProfile({
    required String name,
    required Gender gender,
    String? photoPath,
  }) async {
    await _box.put(_nameKey, name.trim());
    await _box.put(_genderKey, gender.name);
    if (photoPath == null || photoPath.trim().isEmpty) {
      await _box.delete(_photoPathKey);
    } else {
      await _box.put(_photoPathKey, photoPath.trim());
    }
    notifyListeners();
  }

  /// Adds, replaces or (with a null [path]) removes the profile photo shown in
  /// the home app bar.
  Future<void> setPhotoPath(String? path) async {
    final String trimmed = (path ?? '').trim();
    if (trimmed.isEmpty) {
      await _box.delete(_photoPathKey);
    } else {
      await _box.put(_photoPathKey, trimmed);
    }
    notifyListeners();
  }

  Future<void> setIsSingle(bool value) async {
    await _box.put(_isSingleKey, value);
    notifyListeners();
  }

  Future<void> setPersonalCard(String? text) async {
    final String trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) {
      await _box.delete(_personalCardKey);
    } else {
      await _box.put(_personalCardKey, trimmed);
    }
    notifyListeners();
  }
}
