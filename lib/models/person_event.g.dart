// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PersonEventAdapter extends TypeAdapter<PersonEvent> {
  @override
  final int typeId = 12;

  @override
  PersonEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PersonEvent(
      id: fields[0] as String,
      personId: fields[1] as String,
      type: fields[2] as PersonEventType,
      text: fields[3] as String,
      createdAt: fields[4] as DateTime,
      relatedPersonId: fields[5] as String?,
      relatedMatchId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PersonEvent obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.personId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.relatedPersonId)
      ..writeByte(6)
      ..write(obj.relatedMatchId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PersonEventTypeAdapter extends TypeAdapter<PersonEventType> {
  @override
  final int typeId = 13;

  @override
  PersonEventType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PersonEventType.proposalOpened;
      case 1:
        return PersonEventType.dated;
      case 2:
        return PersonEventType.rejected;
      case 3:
        return PersonEventType.statusChanged;
      case 4:
        return PersonEventType.note;
      case 5:
        return PersonEventType.cardChanged;
      case 6:
        return PersonEventType.reminderSet;
      default:
        return PersonEventType.proposalOpened;
    }
  }

  @override
  void write(BinaryWriter writer, PersonEventType obj) {
    switch (obj) {
      case PersonEventType.proposalOpened:
        writer.writeByte(0);
        break;
      case PersonEventType.dated:
        writer.writeByte(1);
        break;
      case PersonEventType.rejected:
        writer.writeByte(2);
        break;
      case PersonEventType.statusChanged:
        writer.writeByte(3);
        break;
      case PersonEventType.note:
        writer.writeByte(4);
        break;
      case PersonEventType.cardChanged:
        writer.writeByte(5);
        break;
      case PersonEventType.reminderSet:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonEventTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
