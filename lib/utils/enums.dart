import 'package:hive/hive.dart';

part 'enums.g.dart';

@HiveType(typeId: 3)
enum Gender {
  @HiveField(0)
  male,

  @HiveField(1)
  female,

  @HiveField(2)
  unknown;

  String get displayName {
    switch (this) {
      case Gender.male:
        return 'בחור';
      case Gender.female:
        return 'בחורה';
      case Gender.unknown:
        return 'לא מוגדר';
    }
  }
}

@HiveType(typeId: 4)
enum ReligiousLevel {
  @HiveField(0)
  datlashi,

  @HiveField(1)
  masorti,

  @HiveField(2)
  datiOpen,

  @HiveField(3)
  datiLeumi,

  @HiveField(4)
  datiLeumiTorani,

  @HiveField(5)
  haredi,

  @HiveField(6)
  hiloni;

  String get displayName {
    switch (this) {
      case ReligiousLevel.datlashi:
        return 'דתלש';
      case ReligiousLevel.masorti:
        return 'מסורתי';
      case ReligiousLevel.datiOpen:
        return 'דתי פתוח';
      case ReligiousLevel.datiLeumi:
        return 'דתי לאומי';
      case ReligiousLevel.datiLeumiTorani:
        return 'דתי לאומי תורני';
      case ReligiousLevel.haredi:
        return 'חרדי';
      case ReligiousLevel.hiloni:
        return 'חילוני';
    }
  }
}

@HiveType(typeId: 5)
enum MatchStatus {
  @HiveField(0)
  idea,

  @HiveField(1)
  checking,

  @HiveField(2)
  unavailable,

  @HiveField(3)
  rejected,

  @HiveField(4)
  dating,

  @HiveField(5)
  dated,

  @HiveField(6)
  married;

  String get displayName {
    switch (this) {
      case MatchStatus.idea:
        return 'רעיון';
      case MatchStatus.checking:
        return 'בבדיקה';
      case MatchStatus.unavailable:
        return 'צד לא פנוי';
      case MatchStatus.rejected:
        return 'נדחה';
      case MatchStatus.dating:
        return 'יוצאים!';
      case MatchStatus.dated:
        return 'יצאו';
      case MatchStatus.married:
        return 'חתונה';
    }
  }

  String get icon {
    switch (this) {
      case MatchStatus.idea:
        return '💡';
      case MatchStatus.checking:
        return '🔍';
      case MatchStatus.unavailable:
        return '⏸';
      case MatchStatus.rejected:
        return '✖';
      case MatchStatus.dating:
        return '💚';
      case MatchStatus.dated:
        return '💔';
      case MatchStatus.married:
        return '💍';
    }
  }

  bool get isArchived {
    switch (this) {
      case MatchStatus.unavailable:
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return true;
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.dating:
        return false;
    }
  }
}

@HiveType(typeId: 7)
enum ProfileStatus {
  @HiveField(0)
  available,

  @HiveField(1)
  busy,

  @HiveField(2)
  onBreak,

  @HiveField(3)
  mazelTov;

  String get displayName {
    switch (this) {
      case ProfileStatus.available:
        return 'פנוי';
      case ProfileStatus.busy:
        return 'תפוס';
      case ProfileStatus.onBreak:
        return 'הפסקה';
      case ProfileStatus.mazelTov:
        return 'מזל טוב';
    }
  }

  String get emoji {
    switch (this) {
      case ProfileStatus.available:
        return '🟢';
      case ProfileStatus.busy:
        return '🔴';
      case ProfileStatus.onBreak:
        return '🟡';
      case ProfileStatus.mazelTov:
        return '🎉';
    }
  }

  bool get isArchived => this == ProfileStatus.mazelTov;
}

@HiveType(typeId: 6)
enum CurrentHandler {
  @HiveField(0)
  me,

  @HiveField(1)
  personA,

  @HiveField(2)
  personB,

  @HiveField(3)
  thirdParty;

  String get displayName {
    switch (this) {
      case CurrentHandler.me:
        return 'אצלי';
      case CurrentHandler.personA:
        return 'אצל הבחור';
      case CurrentHandler.personB:
        return 'אצל הבחורה';
      case CurrentHandler.thirdParty:
        return 'אצל גורם שלישי';
    }
  }
}
