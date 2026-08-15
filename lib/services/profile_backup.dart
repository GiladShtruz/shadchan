import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';

/// The matchmaker's own profile, on its way to and from the cloud backup.
///
/// Kept apart from `BackupService` on purpose. Everything else in the backup
/// is a *record* — an identified row in a box, merged by id — while this is a
/// handful of loose keys in the `settings` box with exactly one of each. The
/// merge rule has to be different too, and hiding that difference inside the
/// record path would have made both harder to read.
abstract final class ProfileBackup {
  /// The single Firestore document this lives in: `users/{uid}/profile/main`.
  static const String documentPath = 'profile/main';

  /// Photos are written as basenames, matching how a candidate's photos are
  /// stored, so the same Cloud Storage objects and the same download step
  /// serve both.
  static Map<String, Object?> toJson(UserProfileProvider profile) {
    final String? photoPath = profile.photoPath;
    return <String, Object?>{
      'name': profile.name,
      'gender': profile.gender?.name,
      'isSingle': profile.isSingle,
      'hasMaritalStatus': profile.hasMaritalStatus,
      'photo': photoPath == null
          ? null
          : PhotoPickerService.basenameOf(photoPath),
      'personalCard': profile.personalCard,
      'personalCardPhotos': <String>[
        for (final String path in profile.personalCardPhotos)
          PhotoPickerService.basenameOf(path),
      ],
    };
  }

  /// Every photo basename the profile refers to, for the uploader to find.
  static List<String> photoNames(Map<String, Object?> json) {
    return <String>[
      if (json['photo'] is String) json['photo']! as String,
      if (json['personalCardPhotos'] is List)
        ...(json['personalCardPhotos']! as List).whereType<String>(),
    ];
  }

  /// Merges a restored profile into the local one, **filling gaps only**.
  ///
  /// Field-level rather than all-or-nothing, and never overwriting, for the
  /// same reason the record merge never overwrites an existing id: the person
  /// running a restore has already been through onboarding on this phone, so
  /// name, gender and marital status are always set locally and answering them
  /// again from a backup would silently undo what they just typed. What is
  /// actually worth restoring — the personal card, its photos, the profile
  /// picture — is exactly what onboarding does not ask for and is therefore
  /// still empty.
  ///
  /// [resolvePhoto] turns a basename into a local path, or returns null when
  /// the file could not be fetched; a photo that is not on this device is left
  /// out rather than restored as a path to nothing.
  ///
  /// Returns the number of fields that were filled, so a restore can say
  /// whether it did anything at all.
  static Future<int> applyMissing(
    UserProfileProvider profile,
    Map<String, Object?> json, {
    required Future<String?> Function(String basename) resolvePhoto,
  }) async {
    int filled = 0;

    // Name and gender move together or not at all — `saveProfile` is the only
    // way to set them and it takes both. In practice this branch is dead on a
    // phone that has been through onboarding, and exists for the case of a
    // restore into a half-initialised install.
    final String? name = _string(json['name']);
    final Gender? gender = _gender(json['gender']);
    if (profile.name == null &&
        profile.gender == null &&
        name != null &&
        gender != null) {
      await profile.saveProfile(
        name: name,
        gender: gender,
        isSingle: _bool(json['isSingle']) ?? false,
      );
      filled++;
    } else if (!profile.hasMaritalStatus && _bool(json['isSingle']) != null) {
      await profile.setIsSingle(_bool(json['isSingle'])!);
      filled++;
    }

    if (profile.photoPath == null && _string(json['photo']) != null) {
      final String? path = await resolvePhoto(_string(json['photo'])!);
      if (path != null) {
        await profile.setPhotoPath(path);
        filled++;
      }
    }

    // The card and its photos are one thing to the person who wrote it, so
    // they are restored together and only when there is no card here at all.
    final String? card = _string(json['personalCard']);
    final List<String> cardPhotoNames = <String>[
      if (json['personalCardPhotos'] is List)
        ...(json['personalCardPhotos']! as List).whereType<String>(),
    ];
    final bool hasLocalCard =
        profile.personalCard != null || profile.personalCardPhotos.isNotEmpty;
    if (!hasLocalCard && (card != null || cardPhotoNames.isNotEmpty)) {
      final List<String> paths = <String>[];
      for (final String basename in cardPhotoNames) {
        final String? path = await resolvePhoto(basename);
        if (path != null) {
          paths.add(path);
        }
      }
      await profile.setPersonalCardContent(text: card ?? '', photoPaths: paths);
      filled++;
    }

    return filled;
  }

  static String? _string(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _bool(Object? value) => value is bool ? value : null;

  static Gender? _gender(Object? value) {
    return switch (value) {
      'male' => Gender.male,
      'female' => Gender.female,
      _ => null,
    };
  }
}
