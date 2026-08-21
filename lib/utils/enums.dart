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
        return 'זכר';
      case Gender.female:
        return 'נקבה';
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

  // Declared between "דתי לאומי תורני" and "חרדי" for natural ordering, but
  // keeps a unique HiveField index so existing stored data stays valid.
  @HiveField(7)
  chardal,

  @HiveField(11)
  datiLite,

  @HiveField(8)
  chabad,

  @HiveField(9)
  harediModern,

  @HiveField(10)
  hasid,

  @HiveField(5)
  haredi,

  @HiveField(6)
  hiloni,

  /// A style the matchmaker defined themselves. The label lives on the person
  /// (`religiousLevelOther`) rather than in this enum.
  @HiveField(12)
  other;

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
      case ReligiousLevel.chardal:
        return 'חרד״ל';
      case ReligiousLevel.datiLite:
        return 'דתי לייט';
      case ReligiousLevel.chabad:
        return 'חב״דניק';
      case ReligiousLevel.harediModern:
        return 'חרדי מודרני';
      case ReligiousLevel.hasid:
        return 'חסיד';
      case ReligiousLevel.haredi:
        return 'חרדי';
      case ReligiousLevel.hiloni:
        return 'חילוני';
      case ReligiousLevel.other:
        return 'אחר';
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
        return 'בהמתנה';
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
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return true;
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.unavailable:
      case MatchStatus.dating:
        return false;
    }
  }

  /// Where the proposal stands, in the four words a matchmaker actually uses:
  /// פתוח / בהמתנה / יוצאים / נסגרה — and חתונה, which is the one ending
  /// nobody would want filed under "נסגרה".
  ///
  /// **Coarser than [displayName], on purpose.** The stored statuses draw
  /// distinctions the database needs and a person scanning a list does not:
  /// "רעיון" and "בבדיקה" are both a proposal that is open, and "נדחה" and
  /// "יצאו" are both one that is over. This is the label the card wears, so
  /// that the status is legible at a glance from across the list rather than
  /// being a word you have to stop and interpret.
  String get stateLabel {
    switch (this) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return 'פתוח';
      case MatchStatus.unavailable:
        return 'בהמתנה';
      case MatchStatus.dating:
        return 'יוצאים';
      case MatchStatus.rejected:
      case MatchStatus.dated:
        return 'נסגרה';
      case MatchStatus.married:
        return 'חתונה';
    }
  }
}

/// Logical groups for the proposals screen tabs. These are derived from a
/// match's [MatchStatus] together with the availability of the two people,
/// so they are not stored on the model directly.
enum MatchProposalTab {
  open,
  waiting,
  dating,
  dated,
  rejected,
  weddings;

  String get displayName {
    switch (this) {
      case MatchProposalTab.open:
        return 'פתוח';
      case MatchProposalTab.waiting:
        return 'בהמתנה';
      case MatchProposalTab.dating:
        return 'יוצאים';
      case MatchProposalTab.dated:
        return 'יצאו';
      case MatchProposalTab.rejected:
        return 'נדחו';
      case MatchProposalTab.weddings:
        return 'חתונות';
    }
  }
}

/// Resolves which proposals tab a match belongs to.
///
/// Returns `null` when the match should be hidden entirely (a non-terminal
/// proposal whose side is already engaged / married).
///
/// A proposal moves to [MatchProposalTab.waiting] either when its own status
/// is [MatchStatus.unavailable] or when one of the people is currently paused
/// (busy / on a break) on their personal card.
MatchProposalTab? matchProposalTabFor({
  required MatchStatus status,
  required bool anyPersonArchived,
  required bool anyPersonPaused,
}) {
  switch (status) {
    case MatchStatus.married:
      return MatchProposalTab.weddings;
    case MatchStatus.dated:
      return MatchProposalTab.dated;
    case MatchStatus.rejected:
      return MatchProposalTab.rejected;
    case MatchStatus.dating:
      // A "מזל טוב" (archived) side drops the active proposal out of the
      // matches view entirely.
      if (anyPersonArchived) {
        return null;
      }
      return MatchProposalTab.dating;
    case MatchStatus.idea:
    case MatchStatus.checking:
    case MatchStatus.unavailable:
      if (anyPersonArchived) {
        return null;
      }
      if (status == MatchStatus.unavailable || anyPersonPaused) {
        return MatchProposalTab.waiting;
      }
      return MatchProposalTab.open;
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
        return 'בהפסקה';
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

  /// Whether this status means the person is currently not available, so their
  /// open proposals should move to the "בהמתנה" tab.
  bool get pausesMatches =>
      this == ProfileStatus.busy || this == ProfileStatus.onBreak;
}

/// Personal marital status of a person in the database. Display labels are
/// gender-aware so a woman reads "גרושה" and a man reads "גרוש".
@HiveType(typeId: 9)
enum MaritalStatus {
  @HiveField(0)
  single,

  @HiveField(1)
  divorced,

  @HiveField(2)
  widowed;

  String displayNameFor(Gender gender) {
    final bool isFemale = gender == Gender.female;
    switch (this) {
      case MaritalStatus.single:
        return isFemale ? 'רווקה' : 'רווק';
      case MaritalStatus.divorced:
        return isFemale ? 'גרושה' : 'גרוש';
      case MaritalStatus.widowed:
        return isFemale ? 'אלמנה' : 'אלמן';
    }
  }

  /// Neutral label used where the gender is unknown or irrelevant.
  String get displayName => displayNameFor(Gender.male);

  /// Label for filters, which cover both genders at once.
  ///
  /// Plural rather than "רווק/ה": a filter selects a group, and the Hebrew
  /// plural already covers a mixed one — which spares the reader a slash in the
  /// middle of every chip.
  String get filterLabel {
    switch (this) {
      case MaritalStatus.single:
        return 'רווקים';
      case MaritalStatus.divorced:
        return 'גרושים';
      case MaritalStatus.widowed:
        return 'אלמנים';
    }
  }
}

/// Where the proposal stands in the outreach process ("איפה זה עומד?"). This is
/// a soft, optional annotation separate from [MatchStatus] — it tracks who has
/// been approached and whether they answered, up to both sides agreeing.
@HiveType(typeId: 10)
enum MatchProgress {
  @HiveField(0)
  notStarted,

  @HiveField(1)
  contactedHim,

  @HiveField(2)
  contactedHer,

  @HiveField(3)
  waitingHim,

  @HiveField(4)
  waitingHer,

  @HiveField(5)
  waitingBoth,

  @HiveField(6)
  bothInterested,

  @HiveField(7)
  other;

  String get displayName {
    switch (this) {
      case MatchProgress.notStarted:
        return 'טרם פניתי';
      case MatchProgress.contactedHim:
        return 'פניתי אליו';
      case MatchProgress.contactedHer:
        return 'פניתי אליה';
      case MatchProgress.waitingHim:
        return 'מחכה לתשובה ממנו';
      case MatchProgress.waitingHer:
        return 'מחכה לתשובה ממנה';
      case MatchProgress.waitingBoth:
        return 'מחכה לתשובה משניהם';
      case MatchProgress.bothInterested:
        return 'שניהם מעוניינים';
      case MatchProgress.other:
        return 'אחר';
    }
  }
}

/// Where in the country a candidate lives, for the extended filtering.
///
/// Deliberately coarser than a city: a matchmaker looking for "someone in the
/// south" is not going to enumerate towns, and a candidate with no region set
/// is simply absent from a region search rather than being guessed at.
@HiveType(typeId: 14)
enum Region {
  @HiveField(0)
  north,

  @HiveField(1)
  haifa,

  @HiveField(2)
  sharon,

  @HiveField(3)
  center,

  @HiveField(4)
  jerusalem,

  @HiveField(5)
  shfela,

  @HiveField(6)
  judeaSamaria,

  @HiveField(7)
  south,

  @HiveField(8)
  abroad;

  String get displayName {
    switch (this) {
      case Region.north:
        return 'צפון';
      case Region.haifa:
        return 'חיפה והקריות';
      case Region.sharon:
        return 'השרון';
      case Region.center:
        return 'מרכז';
      case Region.jerusalem:
        return 'ירושלים והסביבה';
      case Region.shfela:
        return 'שפלה';
      case Region.judeaSamaria:
        return 'יהודה ושומרון';
      case Region.south:
        return 'דרום';
      case Region.abroad:
        return 'חו״ל';
    }
  }
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
