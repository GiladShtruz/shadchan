import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';

part 'person.g.dart';

@HiveType(typeId: 0)
class Person extends HiveObject {
  Person({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.createdAt,
    required this.updatedAt,
    this.legacyBirthDate,
    this.manualAge,
    this.manualAgeUpdatedAt,
    this.religiousLevel,
    this.religiousLevelOther,
    this.city,
    this.phone,
    this.source,
    this.notes,
    this.description,
    this.inquiryContactName,
    this.inquiryContactPhone,
    this.heightCm,
    this.maritalStatus,
    this.profileStatus = ProfileStatus.available,
    this.legacyHebrewBirthYear,
    this.legacyHebrewBirthMonth,
    this.legacyHebrewBirthDay,
    List<String> photosPaths = const [],
    this.isFavorite = false,
    this.needsReview = false,
    this.hidden = false,
    int? avatarIndex,
  }) : photosPaths = List<String>.from(photosPaths),
       avatarIndex = avatarIndex ?? PersonAvatarAssets.defaultIndex(id, gender);

  @HiveField(0)
  final String id;

  @HiveField(1)
  String firstName;

  @HiveField(2)
  String lastName;

  @HiveField(3)
  Gender gender;

  /// Birth dates were removed from the app; a person's age is now just
  /// [manualAge] plus [manualAgeUpdatedAt]. These four slots only still exist
  /// so `PersonMigrations.convertBirthDatesToAges` can read what older versions
  /// stored and turn it into an age. After that one-time pass they are null on
  /// every record and nothing in the app reads or writes them again. Do not
  /// reuse the Hive field indices.
  @HiveField(4)
  DateTime? legacyBirthDate;

  @HiveField(5)
  int? manualAge;

  @HiveField(6)
  ReligiousLevel? religiousLevel;

  /// The free-text label used when [religiousLevel] is [ReligiousLevel.other],
  /// so a matchmaker can work with a style the app does not name itself.
  @HiveField(27)
  String? religiousLevelOther;

  @HiveField(7)
  String? city;

  @HiveField(8)
  String? phone;

  @HiveField(9)
  String? source;

  @HiveField(10)
  String? notes;

  // defaultValue on the non-nullable fields below: records written by older app
  // versions predate some of these fields, so Hive reads them back as null. The
  // default is used instead of crashing the read (`Null is not a subtype of
  // bool`) when the field is absent — old data keeps opening.
  @HiveField(11, defaultValue: <String>[])
  List<String> photosPaths;

  @HiveField(12, defaultValue: false)
  bool isFavorite;

  @HiveField(13)
  DateTime createdAt;

  @HiveField(14)
  DateTime updatedAt;

  @HiveField(15)
  String? description;

  @HiveField(16, defaultValue: ProfileStatus.available)
  ProfileStatus profileStatus;

  @HiveField(17)
  int? legacyHebrewBirthYear;

  @HiveField(18)
  int? legacyHebrewBirthMonth;

  @HiveField(19)
  int? legacyHebrewBirthDay;

  @HiveField(20, defaultValue: false)
  bool needsReview;

  @HiveField(21)
  String? inquiryContactName;

  @HiveField(22)
  String? inquiryContactPhone;

  /// Soft-deleted / hidden from the regular lists and swipes, but still kept in
  /// the database so it can be found via search and restored.
  @HiveField(23, defaultValue: false)
  bool hidden;

  /// When the manual age was last set. Used to advance the age by a year every
  /// 365 days so a manually-entered age doesn't go stale. Null when the age
  /// comes from a birth date instead.
  @HiveField(24)
  DateTime? manualAgeUpdatedAt;

  /// Height in whole centimeters (e.g. 170 for 1.70m).
  @HiveField(25)
  int? heightCm;

  @HiveField(26)
  MaritalStatus? maritalStatus;

  /// Which bundled illustration is shown when there is no profile photo.
  /// Older records get a stable pseudo-random choice from their id.
  @HiveField(28)
  int avatarIndex;

  /// Height formatted for display, e.g. `170 ס״מ`. Empty when unknown.
  String get displayHeight => heightCm == null ? '' : '$heightCm ס״מ';

  /// The religious style as it should be shown: the custom label when one was
  /// typed, otherwise the built-in name. Empty when nothing is set.
  String get religiousLevelLabel {
    final ReligiousLevel? level = religiousLevel;
    if (level == null) {
      return '';
    }
    final String custom = (religiousLevelOther ?? '').trim();
    if (level == ReligiousLevel.other) {
      return custom.isEmpty ? ReligiousLevel.other.displayName : custom;
    }
    return level.displayName;
  }

  String get fullName => '${firstName.trim()} ${lastName.trim()}'.trim();

  int? get age => _effectiveManualAge;

  /// The manually-entered age advanced by one year for every 365 days elapsed
  /// since it was last set. Falls back to the raw value when no anchor exists
  /// (legacy records, until the next time the age is saved).
  int? get _effectiveManualAge {
    final int? base = manualAge;
    if (base == null) {
      return null;
    }
    final DateTime? anchor = manualAgeUpdatedAt;
    if (anchor == null) {
      return base;
    }
    final int elapsedYears = DateTime.now().difference(anchor).inDays ~/ 365;
    return elapsedYears > 0 ? base + elapsedYears : base;
  }

  /// Sets a manually-entered age and stamps [manualAgeUpdatedAt] so it can age
  /// forward over time. Editing other fields leaves the anchor untouched (the
  /// effective age is unchanged), so the 365-day clock isn't reset. Pass null
  /// to clear the age (e.g. when a birth date is used instead).
  void setManualAge(int? value) {
    if (value == null) {
      manualAge = null;
      manualAgeUpdatedAt = null;
      return;
    }
    // Unchanged from the current effective age (and already anchored) — keep
    // the original base value and anchor so aging continues uninterrupted.
    if (manualAgeUpdatedAt != null && value == _effectiveManualAge) {
      return;
    }
    manualAge = value;
    manualAgeUpdatedAt = DateTime.now();
  }

  String get displayAge => age?.toString() ?? '';

  String get initials {
    final String firstInitial = _initialFrom(firstName);
    final String lastInitial = _initialFrom(lastName);
    return '$firstInitial$lastInitial';
  }

  Person copyWith({
    String? id,
    String? firstName,
    String? lastName,
    Gender? gender,
    Object? manualAge = _sentinel,
    Object? manualAgeUpdatedAt = _sentinel,
    Object? religiousLevel = _sentinel,
    Object? religiousLevelOther = _sentinel,
    Object? city = _sentinel,
    Object? phone = _sentinel,
    Object? source = _sentinel,
    Object? notes = _sentinel,
    Object? description = _sentinel,
    Object? inquiryContactName = _sentinel,
    Object? inquiryContactPhone = _sentinel,
    Object? heightCm = _sentinel,
    Object? maritalStatus = _sentinel,
    ProfileStatus? profileStatus,
    List<String>? photosPaths,
    bool? isFavorite,
    bool? needsReview,
    bool? hidden,
    int? avatarIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Person(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      gender: gender ?? this.gender,
      manualAge: identical(manualAge, _sentinel)
          ? this.manualAge
          : manualAge as int?,
      manualAgeUpdatedAt: identical(manualAgeUpdatedAt, _sentinel)
          ? this.manualAgeUpdatedAt
          : manualAgeUpdatedAt as DateTime?,
      religiousLevel: identical(religiousLevel, _sentinel)
          ? this.religiousLevel
          : religiousLevel as ReligiousLevel?,
      religiousLevelOther: identical(religiousLevelOther, _sentinel)
          ? this.religiousLevelOther
          : religiousLevelOther as String?,
      city: identical(city, _sentinel) ? this.city : city as String?,
      phone: identical(phone, _sentinel) ? this.phone : phone as String?,
      source: identical(source, _sentinel) ? this.source : source as String?,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
      inquiryContactName: identical(inquiryContactName, _sentinel)
          ? this.inquiryContactName
          : inquiryContactName as String?,
      inquiryContactPhone: identical(inquiryContactPhone, _sentinel)
          ? this.inquiryContactPhone
          : inquiryContactPhone as String?,
      heightCm: identical(heightCm, _sentinel)
          ? this.heightCm
          : heightCm as int?,
      maritalStatus: identical(maritalStatus, _sentinel)
          ? this.maritalStatus
          : maritalStatus as MaritalStatus?,
      profileStatus: profileStatus ?? this.profileStatus,
      photosPaths: photosPaths ?? this.photosPaths,
      isFavorite: isFavorite ?? this.isFavorite,
      needsReview: needsReview ?? this.needsReview,
      hidden: hidden ?? this.hidden,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _sentinel = Object();

  String _initialFrom(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    return trimmed[0];
  }
}
