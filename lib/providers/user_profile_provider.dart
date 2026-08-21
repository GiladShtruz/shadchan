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
  static const String _firstNameKey = 'userFirstName';
  static const String _lastNameKey = 'userLastName';
  static const String _genderKey = 'userGender';
  static const String _photoPathKey = 'userPhotoPath';
  static const String _isSingleKey = 'userIsSingle';
  static const String _aboutKey = 'userAbout';
  static const String _personalCardKey = 'userPersonalCard';
  static const String _personalCardPhotosKey = 'userPersonalCardPhotos';
  static const String _tipAuthorNameKey = 'userTipAuthorName';
  static const String _introSeenKey = 'userSeenIntro';

  final Box<dynamic> _box;

  /// The matchmaker's full name, as it has always been stored.
  ///
  /// Kept as the single joined key rather than being derived from the two parts
  /// so that everything already reading it — the profile header, the tip
  /// author default, the cloud backup — keeps working untouched, and so an
  /// install from before the name was split still answers.
  String? get name {
    final String? value = (_box.get(_nameKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The first name alone, which is all the home screen's greeting uses.
  ///
  /// "בוקר טוב, רבקה כהן־שטרן" is not how anybody greets anybody. Falls back to
  /// the first word of [name] for a profile saved before the two were asked for
  /// separately, so no existing install has to be re-onboarded to be greeted
  /// properly.
  String? get firstName {
    final String? stored = (_box.get(_firstNameKey) as String?)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final String? full = name;
    if (full == null) {
      return null;
    }
    final String first = full.split(RegExp(r'\s+')).first.trim();
    return first.isEmpty ? null : first;
  }

  /// The surname alone. Null when it was never given — a one-word [name] from
  /// an older install is a first name, not a surname.
  String? get lastName {
    final String? stored = (_box.get(_lastNameKey) as String?)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final String? full = name;
    if (full == null) {
      return null;
    }
    final List<String> parts = full.split(RegExp(r'\s+'))
      ..removeWhere((String part) => part.trim().isEmpty);
    if (parts.length < 2) {
      return null;
    }
    return parts.sublist(1).join(' ');
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

  /// One short line the matchmaker wrote about themselves — "אוהב לחבר בין
  /// אנשים", "עוסקת בשידוכים בעיקר במגזר הדתי־לאומי בגילאי 25–30".
  ///
  /// **Optional, and it stays optional.** It is asked once during sign-up, with
  /// examples rather than an explanation, and skipping it costs nothing: null
  /// here simply means the profile shows a name and a photograph, which is what
  /// it showed before this existed. Nothing in the app is gated on it and it is
  /// never published to the community — it is on the matchmaker's own page, for
  /// the matchmaker.
  String? get about {
    final String? value = (_box.get(_aboutKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> setAbout(String? value) async {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      await _box.delete(_aboutKey);
    } else {
      await _box.put(_aboutKey, trimmed);
    }
    notifyListeners();
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

  /// The name a contributed tip is signed with — first name and surname.
  ///
  /// Kept apart from [name], which onboarding fills with whatever the
  /// matchmaker wants to be greeted by and is usually a first name alone. A tip
  /// is read by strangers, so it is signed in full; the value is asked for once
  /// and remembered here.
  String? get tipAuthorName {
    final String? value = (_box.get(_tipAuthorNameKey) as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> setTipAuthorName(String? value) async {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      await _box.delete(_tipAuthorNameKey);
    } else {
      await _box.put(_tipAuthorNameKey, trimmed);
    }
    notifyListeners();
  }

  /// Whether the first-launch introduction has been read.
  ///
  /// Kept apart from [isOnboarded] because they answer different questions: the
  /// introduction explains what this app is and that the database is private,
  /// and it is worth showing *before* asking anybody to type their name. Once
  /// seen it never returns — it is a welcome, not a help screen.
  bool get hasSeenIntro => _box.get(_introSeenKey) as bool? ?? false;

  Future<void> markIntroSeen() async {
    await _box.put(_introSeenKey, true);
    notifyListeners();
  }

  /// Onboarding is complete once name, gender and personal status have all been
  /// answered. The profile photo stays optional.
  bool get isOnboarded => name != null && gender != null && hasMaritalStatus;

  /// Writes the whole onboarding answer.
  ///
  /// [lastName] is optional because a surname is not something the app can
  /// insist on — plenty of people would give one word and mean it — but when it
  /// is given it is stored on its own as well as inside the joined [name], so
  /// the greeting can use the first name without having to guess where one
  /// name ends and the other begins.
  Future<void> saveProfile({
    required String name,
    required Gender gender,
    required bool isSingle,
    String? lastName,
    String? photoPath,
    String? about,
  }) async {
    final String trimmedFirst = name.trim();
    final String trimmedLast = (lastName ?? '').trim();
    final String fullName = <String>[
      trimmedFirst,
      trimmedLast,
    ].where((String part) => part.isNotEmpty).join(' ');

    await _box.put(_nameKey, fullName);
    await _box.put(_firstNameKey, trimmedFirst);
    if (trimmedLast.isEmpty) {
      await _box.delete(_lastNameKey);
    } else {
      await _box.put(_lastNameKey, trimmedLast);
    }
    await _box.put(_genderKey, gender.name);
    if (photoPath == null || photoPath.trim().isEmpty) {
      await _box.delete(_photoPathKey);
    } else {
      await _box.put(_photoPathKey, photoPath.trim());
    }
    await _box.put(_isSingleKey, isSingle);
    // Omitted rather than cleared when the caller has nothing to say about it:
    // a restore path that only knows name and gender must not wipe a line the
    // matchmaker wrote.
    if (about != null) {
      final String trimmedAbout = about.trim();
      if (trimmedAbout.isEmpty) {
        await _box.delete(_aboutKey);
      } else {
        await _box.put(_aboutKey, trimmedAbout);
      }
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
