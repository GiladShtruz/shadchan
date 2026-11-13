/**
 * The wire format shared with the phone app.
 *
 * Every string here is the Dart enum's `.name` from `lib/utils/enums.dart`.
 * Those strings are what Firestore stores, so they must never be renamed on
 * one side only — change the Dart enum, this file and the stored data together.
 * The Hebrew labels mirror the Dart `displayName` getters.
 */

export const GENDERS = ['male', 'female', 'unknown'] as const;
export type Gender = (typeof GENDERS)[number];

export const RELIGIOUS_LEVELS = [
  'datlashi',
  'masorti',
  'datiOpen',
  'datiLeumi',
  'datiLeumiTorani',
  'chardal',
  'datiLite',
  'chabad',
  'harediModern',
  'hasid',
  'haredi',
  'hiloni',
  'other',
] as const;
export type ReligiousLevel = (typeof RELIGIOUS_LEVELS)[number];

/** The one list offered as a choice (`ReligiousLevels.global`). */
export const RELIGIOUS_LEVELS_GLOBAL: ReligiousLevel[] = [
  'hiloni',
  'masorti',
  'datlashi',
  'datiOpen',
  'datiLeumi',
  'datiLeumiTorani',
  'chardal',
  'haredi',
];

export const RELIGIOUS_LABEL: Record<ReligiousLevel, string> = {
  datlashi: 'דתל״ש',
  masorti: 'מסורתי',
  datiOpen: 'דתי פתוח',
  datiLeumi: 'דתי לאומי',
  datiLeumiTorani: 'דתי לאומי תורני',
  chardal: 'חרד״ל',
  datiLite: 'דתי לייט',
  chabad: 'חב״דניק',
  harediModern: 'חרדי מודרני',
  hasid: 'חסיד',
  haredi: 'חרדי',
  hiloni: 'חילוני',
  other: 'אחר',
};

export const MATCH_STATUSES = [
  'idea',
  'checking',
  'unavailable',
  'rejected',
  'dating',
  'dated',
  'married',
] as const;
export type MatchStatus = (typeof MATCH_STATUSES)[number];

export const MATCH_STATUS_LABEL: Record<MatchStatus, string> = {
  idea: 'רעיון',
  checking: 'בבדיקה',
  unavailable: 'בהמתנה',
  rejected: 'נדחה',
  dating: 'יוצאים!',
  dated: 'יצאו',
  married: 'חתונה',
};

/** `MatchStatus.stateLabel` — the coarse word a card wears. */
export const MATCH_STATE_LABEL: Record<MatchStatus, string> = {
  idea: 'פתוח',
  checking: 'פתוח',
  unavailable: 'בהמתנה',
  dating: 'יוצאים',
  rejected: 'נסגרה',
  dated: 'נסגרה',
  married: 'חתונה',
};

export const PROFILE_STATUSES = ['available', 'busy', 'onBreak', 'mazelTov'] as const;
export type ProfileStatus = (typeof PROFILE_STATUSES)[number];

export function profileStatusLabel(status: ProfileStatus, gender: Gender): string {
  const female = gender === 'female';
  switch (status) {
    case 'available':
      return female ? 'פנויה' : 'פנוי';
    case 'busy':
      return female ? 'תפוסה' : 'תפוס';
    case 'onBreak':
      return 'בהפסקה';
    case 'mazelTov':
      return 'מזל טוב';
  }
}

export const MARITAL_STATUSES = ['single', 'divorced', 'widowed'] as const;
export type MaritalStatus = (typeof MARITAL_STATUSES)[number];

export function maritalLabel(status: MaritalStatus, gender: Gender): string {
  const f = gender === 'female';
  switch (status) {
    case 'single':
      return f ? 'רווקה' : 'רווק';
    case 'divorced':
      return f ? 'גרושה' : 'גרוש';
    case 'widowed':
      return f ? 'אלמנה' : 'אלמן';
  }
}

export const MARITAL_FILTER_LABEL: Record<MaritalStatus, string> = {
  single: 'רווק',
  divorced: 'גרוש',
  widowed: 'אלמן',
};

export const REGIONS = [
  'north',
  'haifa',
  'sharon',
  'center',
  'jerusalem',
  'shfela',
  'judeaSamaria',
  'south',
  'abroad',
] as const;
export type Region = (typeof REGIONS)[number];

export const REGIONS_SELECTABLE: Region[] = ['jerusalem', 'center', 'north', 'south'];

export const REGION_LABEL: Record<Region, string> = {
  north: 'צפון',
  haifa: 'חיפה והקריות',
  sharon: 'השרון',
  center: 'מרכז',
  jerusalem: 'ירושלים והסביבה',
  shfela: 'שפלה',
  judeaSamaria: 'יהודה ושומרון',
  south: 'דרום',
  abroad: 'חו״ל',
};

export const CURRENT_HANDLERS = ['me', 'personA', 'personB', 'thirdParty'] as const;
export type CurrentHandler = (typeof CURRENT_HANDLERS)[number];

export const MATCH_PROGRESS = [
  'notStarted',
  'contactedHim',
  'contactedHer',
  'waitingHim',
  'waitingHer',
  'waitingBoth',
  'bothInterested',
  'other',
] as const;
export type MatchProgress = (typeof MATCH_PROGRESS)[number];

export const PERSON_EVENT_TYPES = [
  'proposalOpened',
  'dated',
  'rejected',
  'statusChanged',
  'note',
  'cardChanged',
  'reminderSet',
  'cardSynced',
  'cardSyncedMinor',
] as const;
export type PersonEventType = (typeof PERSON_EVENT_TYPES)[number];

/** The six tabs of `MatchProposalTab` — derived, never stored. */
export type ProposalTab = 'open' | 'waiting' | 'dating' | 'dated' | 'rejected' | 'weddings';

export const PROPOSAL_TAB_LABEL: Record<ProposalTab, string> = {
  open: 'פתוח',
  waiting: 'בהמתנה',
  dating: 'יוצאים',
  dated: 'יצאו',
  rejected: 'נדחו',
  weddings: 'חתונות',
};
