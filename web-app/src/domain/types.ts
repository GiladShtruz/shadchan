import type {
  CurrentHandler,
  Gender,
  MaritalStatus,
  MatchProgress,
  MatchStatus,
  PersonEventType,
  ProfileStatus,
  Region,
  ReligiousLevel,
} from './enums';

/**
 * Record shapes, exactly as the phone stores them in Firestore under
 * `users/{uid}/{collection}/{id}`: the body of each document is the map built
 * by `BackupService.*ToJson` in the Flutter app. Dates are ISO-8601 strings,
 * enums are their Dart `.name`, photos are basenames in Cloud Storage.
 *
 * Fields starting with `_` (`_w`, `_d`, `_deleted`) are sync metadata, not
 * part of the record — the data layer strips them and drops tombstones.
 */

export interface MatchContact {
  name: string;
  phone: string | null;
  description: string | null;
}

export interface Person {
  id: string;
  firstName: string;
  lastName: string | null;
  gender: Gender;
  manualAge: number | null;
  manualAgeUpdatedAt: string | null;
  religiousLevel: ReligiousLevel | null;
  religiousLevelOther: string | null;
  city: string | null;
  phone: string | null;
  source: string | null;
  notes: string | null;
  /** "כרטיסייה לשליחה" — the card text that is shared. */
  description: string | null;
  inquiryContactName: string | null;
  inquiryContactPhone: string | null;
  heightCm: number | null;
  maritalStatus: MaritalStatus | null;
  region: Region | null;
  importBatchId: string | null;
  dateOfBirth: string | null;
  cardOwnerUid: string | null;
  cardSyncDetached: boolean;
  preSyncSnapshot: string | null;
  cardRemoteStatus: string | null;
  tags: string[];
  additionalContacts: MatchContact[];
  preferredMinAge: number | null;
  preferredMaxAge: number | null;
  preferredMinHeightCm: number | null;
  preferredMaxHeightCm: number | null;
  preferredCity: string | null;
  preferredRegions: Region[];
  preferredMaritalStatuses: MaritalStatus[];
  preferredReligiousLevels: ReligiousLevel[];
  preferredReligiousLevelOtherLabels: string[];
  profileStatus: ProfileStatus;
  photos: string[];
  isFavorite: boolean;
  needsReview: boolean;
  hidden: boolean;
  avatarIndex: number | null;
  createdAt: string;
  updatedAt: string;
}

export interface MatchIdea {
  id: string;
  personAId: string;
  personBId: string;
  status: MatchStatus;
  currentHandler: CurrentHandler;
  handlerName: string | null;
  reminderDate: string | null;
  reminderNote: string | null;
  waitingReason: string | null;
  progress: MatchProgress | null;
  progressOther: string | null;
  relatedContacts: MatchContact[];
  lastShareLabel: string | null;
  lastShareAt: string | null;
  createdAt: string;
  updatedAt: string;
  // Carried by the sync engine beyond `matchToJson`.
  askedMaleAt?: string | null;
  askedFemaleAt?: string | null;
  checkInEveryDays?: number | null;
  datingStartedAt?: string | null;
  datingEndedAt?: string | null;
}

export interface PersonNote {
  id: string;
  personId: string;
  text: string;
  createdAt: string;
  isAutomatic: boolean;
  audioFile?: string;
  audioDurationMs?: number;
}

export interface MatchNote {
  id: string;
  matchId: string;
  text: string;
  createdAt: string;
  isAutomatic: boolean;
  mazelTovFrom: string | null;
}

export interface PersonEvent {
  id: string;
  personId: string;
  type: PersonEventType;
  text: string;
  createdAt: string;
  relatedPersonId: string | null;
  relatedMatchId: string | null;
}

export interface MatchStatusEvent {
  id: string;
  matchId: string;
  fromStatus: MatchStatus | null;
  toStatus: MatchStatus;
  createdAt: string;
  automatic: boolean;
}

/** The matchmaker's own profile (`settings` keys in the app). */
export interface MatchmakerProfile {
  firstName: string;
  lastName: string;
  gender: Gender;
  isSingle: boolean;
  about: string | null;
}

/** Everything one account holds — the same set on every device. */
export interface Database {
  profile: MatchmakerProfile;
  people: Person[];
  personNotes: PersonNote[];
  matches: MatchIdea[];
  matchNotes: MatchNote[];
  personEvents: PersonEvent[];
  matchStatusEvents: MatchStatusEvent[];
}

// ---- Personal area (the single's own card) ------------------------------

export type AccessState = 'pending' | 'approved' | 'declined' | 'blocked';

export interface CardAccessRow {
  matchmakerUid: string;
  matchmakerName: string;
  matchmakerGender: Gender | null;
  status: AccessState;
  /** Permission to see "מה אני מחפש/ת" as well. */
  seesPrivateLooking: boolean;
  requestedAt: string;
  databaseCount: number | null;
  lastActiveAt: string | null;
}

export interface PersonalArea {
  card: Person;
  privateLooking: string | null;
  acceptsRequests: boolean;
  announces: boolean;
  access: CardAccessRow[];
  /** Matchmakers among my contacts who have not been given access. */
  helpers: { uid: string; name: string; databaseCount: number | null; lastActiveAt: string | null }[];
}

// ---- Community ----------------------------------------------------------

export type CommunityWindow = 'day' | 'week' | 'month' | 'all';

export interface CommunityTotals {
  points: number;
  friends: number;
  ideas: number;
  couples: number;
  engagements: number;
  activeMatchmakers: number;
  newMatchmakers: number;
}

export interface LeaderboardRow {
  uid: string;
  name: string;
  points: number;
  isMe: boolean;
}

export interface Tip {
  id: string;
  text: string;
  authorName: string | null;
}

export interface AppNotification {
  id: string;
  kind: 'reminder' | 'cardCreated' | 'accessApproved' | 'accessRequest' | 'support' | 'statusEvent';
  title: string;
  subtitle: string | null;
  createdAt: string;
  read: boolean;
  personId?: string;
  matchId?: string;
}
