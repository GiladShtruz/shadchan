// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PersonAdapter extends TypeAdapter<Person> {
  @override
  final int typeId = 0;

  @override
  Person read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Person(
      id: fields[0] as String,
      firstName: fields[1] as String,
      lastName: fields[2] as String,
      gender: fields[3] as Gender,
      createdAt: fields[13] as DateTime,
      updatedAt: fields[14] as DateTime,
      legacyBirthDate: fields[4] as DateTime?,
      manualAge: fields[5] as int?,
      manualAgeUpdatedAt: fields[24] as DateTime?,
      religiousLevel: fields[6] as ReligiousLevel?,
      religiousLevelOther: fields[27] as String?,
      city: fields[7] as String?,
      phone: fields[8] as String?,
      source: fields[9] as String?,
      notes: fields[10] as String?,
      description: fields[15] as String?,
      inquiryContactName: fields[21] as String?,
      inquiryContactPhone: fields[22] as String?,
      heightCm: fields[25] as int?,
      maritalStatus: fields[26] as MaritalStatus?,
      region: fields[29] as Region?,
      preferredMinAge: fields[30] as int?,
      preferredMaxAge: fields[31] as int?,
      preferredMinHeightCm: fields[32] as int?,
      preferredMaxHeightCm: fields[33] as int?,
      preferredCity: fields[34] as String?,
      preferredRegions: fields[35] == null
          ? []
          : (fields[35] as List).cast<Region>(),
      preferredMaritalStatuses: fields[36] == null
          ? []
          : (fields[36] as List).cast<MaritalStatus>(),
      preferredReligiousLevels: fields[37] == null
          ? []
          : (fields[37] as List).cast<ReligiousLevel>(),
      preferredReligiousLevelOtherLabels: fields[38] == null
          ? []
          : (fields[38] as List).cast<String>(),
      additionalContacts: fields[39] == null
          ? []
          : (fields[39] as List).cast<MatchContact>(),
      profileStatus: fields[16] == null
          ? ProfileStatus.available
          : fields[16] as ProfileStatus,
      legacyHebrewBirthYear: fields[17] as int?,
      legacyHebrewBirthMonth: fields[18] as int?,
      legacyHebrewBirthDay: fields[19] as int?,
      photosPaths: fields[11] == null
          ? []
          : (fields[11] as List).cast<String>(),
      isFavorite: fields[12] == null ? false : fields[12] as bool,
      needsReview: fields[20] == null ? false : fields[20] as bool,
      hidden: fields[23] == null ? false : fields[23] as bool,
      avatarIndex: fields[28] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Person obj) {
    writer
      ..writeByte(40)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.firstName)
      ..writeByte(2)
      ..write(obj.lastName)
      ..writeByte(3)
      ..write(obj.gender)
      ..writeByte(4)
      ..write(obj.legacyBirthDate)
      ..writeByte(5)
      ..write(obj.manualAge)
      ..writeByte(6)
      ..write(obj.religiousLevel)
      ..writeByte(27)
      ..write(obj.religiousLevelOther)
      ..writeByte(7)
      ..write(obj.city)
      ..writeByte(8)
      ..write(obj.phone)
      ..writeByte(9)
      ..write(obj.source)
      ..writeByte(10)
      ..write(obj.notes)
      ..writeByte(11)
      ..write(obj.photosPaths)
      ..writeByte(12)
      ..write(obj.isFavorite)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.updatedAt)
      ..writeByte(15)
      ..write(obj.description)
      ..writeByte(16)
      ..write(obj.profileStatus)
      ..writeByte(17)
      ..write(obj.legacyHebrewBirthYear)
      ..writeByte(18)
      ..write(obj.legacyHebrewBirthMonth)
      ..writeByte(19)
      ..write(obj.legacyHebrewBirthDay)
      ..writeByte(20)
      ..write(obj.needsReview)
      ..writeByte(21)
      ..write(obj.inquiryContactName)
      ..writeByte(22)
      ..write(obj.inquiryContactPhone)
      ..writeByte(23)
      ..write(obj.hidden)
      ..writeByte(24)
      ..write(obj.manualAgeUpdatedAt)
      ..writeByte(25)
      ..write(obj.heightCm)
      ..writeByte(26)
      ..write(obj.maritalStatus)
      ..writeByte(29)
      ..write(obj.region)
      ..writeByte(30)
      ..write(obj.preferredMinAge)
      ..writeByte(31)
      ..write(obj.preferredMaxAge)
      ..writeByte(32)
      ..write(obj.preferredMinHeightCm)
      ..writeByte(33)
      ..write(obj.preferredMaxHeightCm)
      ..writeByte(34)
      ..write(obj.preferredCity)
      ..writeByte(35)
      ..write(obj.preferredRegions)
      ..writeByte(36)
      ..write(obj.preferredMaritalStatuses)
      ..writeByte(37)
      ..write(obj.preferredReligiousLevels)
      ..writeByte(38)
      ..write(obj.preferredReligiousLevelOtherLabels)
      ..writeByte(39)
      ..write(obj.additionalContacts)
      ..writeByte(28)
      ..write(obj.avatarIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
