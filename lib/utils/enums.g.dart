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
      case 7:
        return ReligiousLevel.chardal;
      case 11:
        return ReligiousLevel.datiLite;
      case 8:
        return ReligiousLevel.chabad;
      case 9:
        return ReligiousLevel.harediModern;
      case 10:
        return ReligiousLevel.hasid;
      case 5:
        return ReligiousLevel.haredi;
      case 6:
        return ReligiousLevel.hiloni;
      case 12:
        return ReligiousLevel.other;
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
      case ReligiousLevel.chardal:
        writer.writeByte(7);
        break;
      case ReligiousLevel.datiLite:
        writer.writeByte(11);
        break;
      case ReligiousLevel.chabad:
        writer.writeByte(8);
        break;
      case ReligiousLevel.harediModern:
        writer.writeByte(9);
        break;
      case ReligiousLevel.hasid:
        writer.writeByte(10);
        break;
      case ReligiousLevel.haredi:
        writer.writeByte(5);
        break;
      case ReligiousLevel.hiloni:
        writer.writeByte(6);
        break;
      case ReligiousLevel.other:
        writer.writeByte(12);
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

class MaritalStatusAdapter extends TypeAdapter<MaritalStatus> {
  @override
  final int typeId = 9;

  @override
  MaritalStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MaritalStatus.single;
      case 1:
        return MaritalStatus.divorced;
      case 2:
        return MaritalStatus.widowed;
      default:
        return MaritalStatus.single;
    }
  }

  @override
  void write(BinaryWriter writer, MaritalStatus obj) {
    switch (obj) {
      case MaritalStatus.single:
        writer.writeByte(0);
        break;
      case MaritalStatus.divorced:
        writer.writeByte(1);
        break;
      case MaritalStatus.widowed:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaritalStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MatchProgressAdapter extends TypeAdapter<MatchProgress> {
  @override
  final int typeId = 10;

  @override
  MatchProgress read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MatchProgress.notStarted;
      case 1:
        return MatchProgress.contactedHim;
      case 2:
        return MatchProgress.contactedHer;
      case 3:
        return MatchProgress.waitingHim;
      case 4:
        return MatchProgress.waitingHer;
      case 5:
        return MatchProgress.waitingBoth;
      case 6:
        return MatchProgress.bothInterested;
      case 7:
        return MatchProgress.other;
      default:
        return MatchProgress.notStarted;
    }
  }

  @override
  void write(BinaryWriter writer, MatchProgress obj) {
    switch (obj) {
      case MatchProgress.notStarted:
        writer.writeByte(0);
        break;
      case MatchProgress.contactedHim:
        writer.writeByte(1);
        break;
      case MatchProgress.contactedHer:
        writer.writeByte(2);
        break;
      case MatchProgress.waitingHim:
        writer.writeByte(3);
        break;
      case MatchProgress.waitingHer:
        writer.writeByte(4);
        break;
      case MatchProgress.waitingBoth:
        writer.writeByte(5);
        break;
      case MatchProgress.bothInterested:
        writer.writeByte(6);
        break;
      case MatchProgress.other:
        writer.writeByte(7);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchProgressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RegionAdapter extends TypeAdapter<Region> {
  @override
  final int typeId = 14;

  @override
  Region read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Region.north;
      case 1:
        return Region.haifa;
      case 2:
        return Region.sharon;
      case 3:
        return Region.center;
      case 4:
        return Region.jerusalem;
      case 5:
        return Region.shfela;
      case 6:
        return Region.judeaSamaria;
      case 7:
        return Region.south;
      case 8:
        return Region.abroad;
      default:
        return Region.north;
    }
  }

  @override
  void write(BinaryWriter writer, Region obj) {
    switch (obj) {
      case Region.north:
        writer.writeByte(0);
        break;
      case Region.haifa:
        writer.writeByte(1);
        break;
      case Region.sharon:
        writer.writeByte(2);
        break;
      case Region.center:
        writer.writeByte(3);
        break;
      case Region.jerusalem:
        writer.writeByte(4);
        break;
      case Region.shfela:
        writer.writeByte(5);
        break;
      case Region.judeaSamaria:
        writer.writeByte(6);
        break;
      case Region.south:
        writer.writeByte(7);
        break;
      case Region.abroad:
        writer.writeByte(8);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionAdapter &&
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
