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
  static const String _personalCardPhotosKey = 'userPersonalCardPhotos';

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

  /// Whether onboarding (or a later profile edit) recorded the user's personal
  /// status. Kept separate from [isSingle] so an existing installation is asked
  /// once after upgrading instead of silently being treated as married.
  bool get hasMaritalStatus => _box.containsKey(_isSingleKey);

  /// Whether the matchmaker is looking for a match themselves. This is an
  /// explicit onboarding answer, not a default inferred from a missing value.
  bool get isSingle => _box.get(_isSingleKey) as bool? ?? false;

  /// The matchmaker's own shidduch card, kept so they can share it in one tap
  /// the way they share a candidate's.
  String? get personalCard {
    final String? value = (_box.get(_personalCardKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Ordered photos attached to the matchmaker's own card. Hive returns a
  /// dynamic list, so tolerate old/corrupt values rather than failing profile
  /// rendering. The first path is the primary photo used in previews.
  List<String> get personalCardPhotos {
    final dynamic stored = _box.get(_personalCardPhotosKey);
    if (stored is! Iterable) {
      return const <String>[];
    }
    return <String>[
      for (final dynamic value in stored)
        if (value is String && value.trim().isNotEmpty) value.trim(),
    ];
  }

  /// Onboarding is complete once name, gender and personal status have all been
  /// answered. The profile photo stays optional.
  bool get isOnboarded => name != null && gender != null && hasMaritalStatus;

  Future<void> saveProfile({
    required String name,
    required Gender gender,
    required bool isSingle,
    String? photoPath,
  }) async {
    await _box.put(_nameKey, name.trim());
    await _box.put(_genderKey, gender.name);
    if (photoPath == null || photoPath.trim().isEmpty) {
      await _box.delete(_photoPathKey);
    } else {
      await _box.put(_photoPathKey, photoPath.trim());
    }
    await _box.put(_isSingleKey, isSingle);
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

  Future<void> setPersonalCardPhotos(Iterable<String> paths) async {
    final List<String> cleaned = paths
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) {
      await _box.delete(_personalCardPhotosKey);
    } else {
      await _box.put(_personalCardPhotosKey, cleaned);
    }
    notifyListeners();
  }

  Future<void> setPersonalCardContent({
    required String text,
    required Iterable<String> photoPaths,
  }) async {
    final String trimmed = text.trim();
    final List<String> cleaned = photoPaths
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .toList();
    if (trimmed.isEmpty) {
      await _box.delete(_personalCardKey);
    } else {
      await _box.put(_personalCardKey, trimmed);
    }
    if (cleaned.isEmpty) {
      await _box.delete(_personalCardPhotosKey);
    } else {
      await _box.put(_personalCardPhotosKey, cleaned);
    }
    notifyListeners();
  }
}
