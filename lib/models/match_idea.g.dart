// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_idea.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MatchIdeaAdapter extends TypeAdapter<MatchIdea> {
  @override
  final int typeId = 1;

  @override
  MatchIdea read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchIdea(
      id: fields[0] as String,
      personAId: fields[1] as String,
      personBId: fields[2] as String,
      status: fields[3] == null ? MatchStatus.idea : fields[3] as MatchStatus,
      currentHandler: fields[4] == null
          ? CurrentHandler.me
          : fields[4] as CurrentHandler,
      createdAt: fields[6] as DateTime,
      updatedAt: fields[7] as DateTime,
      handlerName: fields[5] as String?,
      reminderDate: fields[8] as DateTime?,
      reminderNote: fields[9] as String?,
      waitingReason: fields[10] as String?,
      progress: fields[11] as MatchProgress?,
      progressOther: fields[12] as String?,
      relatedContacts: fields[13] == null
          ? []
          : (fields[13] as List).cast<MatchContact>(),
    );
  }

  @override
  void write(BinaryWriter writer, MatchIdea obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.personAId)
      ..writeByte(2)
      ..write(obj.personBId)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.currentHandler)
      ..writeByte(5)
      ..write(obj.handlerName)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.reminderDate)
      ..writeByte(9)
      ..write(obj.reminderNote)
      ..writeByte(10)
      ..write(obj.waitingReason)
      ..writeByte(11)
      ..write(obj.progress)
      ..writeByte(12)
      ..write(obj.progressOther)
      ..writeByte(13)
      ..write(obj.relatedContacts);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchIdeaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
