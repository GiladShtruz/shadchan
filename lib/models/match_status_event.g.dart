// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_status_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MatchStatusEventAdapter extends TypeAdapter<MatchStatusEvent> {
  @override
  final int typeId = 15;

  @override
  MatchStatusEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchStatusEvent(
      id: fields[0] as String,
      matchId: fields[1] as String,
      fromStatus: fields[2] as MatchStatus?,
      toStatus: fields[3] as MatchStatus,
      createdAt: fields[4] as DateTime,
      automatic: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, MatchStatusEvent obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.matchId)
      ..writeByte(2)
      ..write(obj.fromStatus)
      ..writeByte(3)
      ..write(obj.toStatus)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.automatic);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchStatusEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
