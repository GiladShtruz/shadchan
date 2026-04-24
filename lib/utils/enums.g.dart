// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enums.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GenderAdapter extends TypeAdapter<Gender> {
  @override
  final int typeId = 3;

  @override
  Gender read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Gender.male;
      case 1:
        return Gender.female;
      case 2:
        return Gender.unknown;
      default:
        return Gender.male;
    }
  }

  @override
  void write(BinaryWriter writer, Gender obj) {
    switch (obj) {
      case Gender.male:
        writer.writeByte(0);
        break;
      case Gender.female:
        writer.writeByte(1);
        break;
      case Gender.unknown:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ReligiousLevelAdapter extends TypeAdapter<ReligiousLevel> {
  @override
  final int typeId = 4;

  @override
  ReligiousLevel read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ReligiousLevel.datlashi;
      case 1:
        return ReligiousLevel.masorti;
      case 2:
        return ReligiousLevel.datiOpen;
      case 3:
        return ReligiousLevel.datiLeumi;
      case 4:
        return ReligiousLevel.datiLeumiTorani;
      case 5:
        return ReligiousLevel.haredi;
      case 6:
        return ReligiousLevel.hiloni;
      default:
        return ReligiousLevel.datlashi;
    }
  }

  @override
  void write(BinaryWriter writer, ReligiousLevel obj) {
    switch (obj) {
      case ReligiousLevel.datlashi:
        writer.writeByte(0);
        break;
      case ReligiousLevel.masorti:
        writer.writeByte(1);
        break;
      case ReligiousLevel.datiOpen:
        writer.writeByte(2);
        break;
      case ReligiousLevel.datiLeumi:
        writer.writeByte(3);
        break;
      case ReligiousLevel.datiLeumiTorani:
        writer.writeByte(4);
        break;
      case ReligiousLevel.haredi:
        writer.writeByte(5);
        break;
      case ReligiousLevel.hiloni:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReligiousLevelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MatchStatusAdapter extends TypeAdapter<MatchStatus> {
  @override
  final int typeId = 5;

  @override
  MatchStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MatchStatus.idea;
      case 1:
        return MatchStatus.checking;
      case 2:
        return MatchStatus.unavailable;
      case 3:
        return MatchStatus.rejected;
      case 4:
        return MatchStatus.dating;
      case 5:
        return MatchStatus.dated;
      case 6:
        return MatchStatus.married;
      default:
        return MatchStatus.idea;
    }
  }

  @override
  void write(BinaryWriter writer, MatchStatus obj) {
    switch (obj) {
      case MatchStatus.idea:
        writer.writeByte(0);
        break;
      case MatchStatus.checking:
        writer.writeByte(1);
        break;
      case MatchStatus.unavailable:
        writer.writeByte(2);
        break;
      case MatchStatus.rejected:
        writer.writeByte(3);
        break;
      case MatchStatus.dating:
        writer.writeByte(4);
        break;
      case MatchStatus.dated:
        writer.writeByte(5);
        break;
      case MatchStatus.married:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ProfileStatusAdapter extends TypeAdapter<ProfileStatus> {
  @override
  final int typeId = 7;

  @override
  ProfileStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ProfileStatus.available;
      case 1:
        return ProfileStatus.busy;
      case 2:
        return ProfileStatus.onBreak;
      case 3:
        return ProfileStatus.mazelTov;
      default:
        return ProfileStatus.available;
    }
  }

  @override
  void write(BinaryWriter writer, ProfileStatus obj) {
    switch (obj) {
      case ProfileStatus.available:
        writer.writeByte(0);
        break;
      case ProfileStatus.busy:
        writer.writeByte(1);
        break;
      case ProfileStatus.onBreak:
        writer.writeByte(2);
        break;
      case ProfileStatus.mazelTov:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CurrentHandlerAdapter extends TypeAdapter<CurrentHandler> {
  @override
  final int typeId = 6;

  @override
  CurrentHandler read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return CurrentHandler.me;
      case 1:
        return CurrentHandler.personA;
      case 2:
        return CurrentHandler.personB;
      case 3:
        return CurrentHandler.thirdParty;
      default:
        return CurrentHandler.me;
    }
  }

  @override
  void write(BinaryWriter writer, CurrentHandler obj) {
    switch (obj) {
      case CurrentHandler.me:
        writer.writeByte(0);
        break;
      case CurrentHandler.personA:
        writer.writeByte(1);
        break;
      case CurrentHandler.personB:
        writer.writeByte(2);
        break;
      case CurrentHandler.thirdParty:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrentHandlerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
