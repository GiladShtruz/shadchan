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
      birthDate: fields[4] as DateTime?,
      manualAge: fields[5] as int?,
      religiousLevel: fields[6] as ReligiousLevel?,
      city: fields[7] as String?,
      phone: fields[8] as String?,
      source: fields[9] as String?,
      notes: fields[10] as String?,
      description: fields[15] as String?,
      profileStatus: fields[16] as ProfileStatus,
      hebrewBirthYear: fields[17] as int?,
      hebrewBirthMonth: fields[18] as int?,
      hebrewBirthDay: fields[19] as int?,
      photosPaths: (fields[11] as List).cast<String>(),
      isFavorite: fields[12] as bool,
      needsReview: fields[20] as bool? ?? false,
      inquiryContactName: fields[21] as String?,
      inquiryContactPhone: fields[22] as String?,
      hidden: fields[23] as bool? ?? false,
      manualAgeUpdatedAt: fields[24] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Person obj) {
    writer
      ..writeByte(25)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.firstName)
      ..writeByte(2)
      ..write(obj.lastName)
      ..writeByte(3)
      ..write(obj.gender)
      ..writeByte(4)
      ..write(obj.birthDate)
      ..writeByte(5)
      ..write(obj.manualAge)
      ..writeByte(6)
      ..write(obj.religiousLevel)
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
      ..write(obj.hebrewBirthYear)
      ..writeByte(18)
      ..write(obj.hebrewBirthMonth)
      ..writeByte(19)
      ..write(obj.hebrewBirthDay)
      ..writeByte(20)
      ..write(obj.needsReview)
      ..writeByte(21)
      ..write(obj.inquiryContactName)
      ..writeByte(22)
      ..write(obj.inquiryContactPhone)
      ..writeByte(23)
      ..write(obj.hidden)
      ..writeByte(24)
      ..write(obj.manualAgeUpdatedAt);
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
