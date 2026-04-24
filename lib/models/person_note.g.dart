// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person_note.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PersonNoteAdapter extends TypeAdapter<PersonNote> {
  @override
  final int typeId = 8;

  @override
  PersonNote read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PersonNote(
      id: fields[0] as String,
      personId: fields[1] as String,
      text: fields[2] as String,
      createdAt: fields[3] as DateTime,
      isAutomatic: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, PersonNote obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.personId)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.isAutomatic);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonNoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
