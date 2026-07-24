// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_contact.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MatchContactAdapter extends TypeAdapter<MatchContact> {
  @override
  final int typeId = 11;

  @override
  MatchContact read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchContact(
      name: fields[0] as String,
      phone: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, MatchContact obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.phone);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchContactAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
