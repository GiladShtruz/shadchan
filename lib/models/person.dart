import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/date_utils.dart';

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
    this.birthDate,
    this.manualAge,
    this.religiousLevel,
    this.city,
    this.phone,
    this.source,
    this.notes,
    this.description,
    this.inquiryContactName,
    this.inquiryContactPhone,
    this.profileStatus = ProfileStatus.available,
    this.hebrewBirthYear,
    this.hebrewBirthMonth,
    this.hebrewBirthDay,
    List<String> photosPaths = const [],
    this.isFavorite = false,
    this.needsReview = false,
  }) : photosPaths = List<String>.from(photosPaths);

  @HiveField(0)
  final String id;

  @HiveField(1)
  String firstName;

  @HiveField(2)
  String lastName;

  @HiveField(3)
  Gender gender;

  @HiveField(4)
  DateTime? birthDate;

  @HiveField(5)
  int? manualAge;

  @HiveField(6)
  ReligiousLevel? religiousLevel;

  @HiveField(7)
  String? city;

  @HiveField(8)
  String? phone;

  @HiveField(9)
  String? source;

  @HiveField(10)
  String? notes;

  @HiveField(11)
  List<String> photosPaths;

  @HiveField(12)
  bool isFavorite;

  @HiveField(13)
  DateTime createdAt;

  @HiveField(14)
  DateTime updatedAt;

  @HiveField(15)
  String? description;

  @HiveField(16)
  ProfileStatus profileStatus;

  @HiveField(17)
  int? hebrewBirthYear;

  @HiveField(18)
  int? hebrewBirthMonth;

  @HiveField(19)
  int? hebrewBirthDay;

  @HiveField(20)
  bool needsReview;

  @HiveField(21)
  String? inquiryContactName;

  @HiveField(22)
  String? inquiryContactPhone;

  String get fullName => '${firstName.trim()} ${lastName.trim()}'.trim();

  int? get age {
    if (birthDate != null) {
      return AppDateUtils.calculateAge(birthDate!);
    }

    return manualAge;
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
    Object? birthDate = _sentinel,
    Object? manualAge = _sentinel,
    Object? religiousLevel = _sentinel,
    Object? city = _sentinel,
    Object? phone = _sentinel,
    Object? source = _sentinel,
    Object? notes = _sentinel,
    Object? description = _sentinel,
    Object? inquiryContactName = _sentinel,
    Object? inquiryContactPhone = _sentinel,
    ProfileStatus? profileStatus,
    Object? hebrewBirthYear = _sentinel,
    Object? hebrewBirthMonth = _sentinel,
    Object? hebrewBirthDay = _sentinel,
    List<String>? photosPaths,
    bool? isFavorite,
    bool? needsReview,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Person(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      gender: gender ?? this.gender,
      birthDate: identical(birthDate, _sentinel)
          ? this.birthDate
          : birthDate as DateTime?,
      manualAge: identical(manualAge, _sentinel)
          ? this.manualAge
          : manualAge as int?,
      religiousLevel: identical(religiousLevel, _sentinel)
          ? this.religiousLevel
          : religiousLevel as ReligiousLevel?,
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
      profileStatus: profileStatus ?? this.profileStatus,
      hebrewBirthYear: identical(hebrewBirthYear, _sentinel)
          ? this.hebrewBirthYear
          : hebrewBirthYear as int?,
      hebrewBirthMonth: identical(hebrewBirthMonth, _sentinel)
          ? this.hebrewBirthMonth
          : hebrewBirthMonth as int?,
      hebrewBirthDay: identical(hebrewBirthDay, _sentinel)
          ? this.hebrewBirthDay
          : hebrewBirthDay as int?,
      photosPaths: photosPaths ?? this.photosPaths,
      isFavorite: isFavorite ?? this.isFavorite,
      needsReview: needsReview ?? this.needsReview,
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
