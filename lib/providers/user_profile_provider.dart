import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';

/// Stores the profile of the matchmaker (the app's owner) collected during the
/// first-launch onboarding flow.
class UserProfileProvider extends ChangeNotifier {
  UserProfileProvider(this._box);

  static const String _nameKey = 'userName';
  static const String _genderKey = 'userGender';
  static const String _photoPathKey = 'userPhotoPath';

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
}
