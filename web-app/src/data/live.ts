'use client';

import { collection, doc, getDoc, limit, onSnapshot, orderBy, query, where, type DocumentData, type Unsubscribe } from 'firebase/firestore';
import { fb } from './firebase';
import type { Gender, ProfileStatus } from '@/domain/enums';
import { GENDERS, PROFILE_STATUSES } from '@/domain/enums';
import type {
  AccessState,
  AppNotification,
  CardAccessRow,
  Database,
  MatchIdea,
  MatchNote,
  MatchStatusEvent,
  MatchmakerProfile,
  Person,
  PersonEvent,
  PersonNote,
  PersonalArea,
} from '@/domain/types';

/**
 * Reads the account's database live from Firestore — read-only.
 *
 * The documents are exactly what the phones write (`AccountSyncEngine`):
 * `users/{databaseUid}/{collection}/{id}` with the record body plus `_w`/`_d`,
 * or a tombstone `{_deleted: true}`. Tombstones are dropped and `_` fields
 * stripped. A couple's shared database lives under the uid in
 * `memberships/{uid}.databaseUid`; their photos under `coupleFiles/{operation}`.
 */

export type LiveStatus = 'connecting' | 'ready' | 'denied' | 'error';

export interface LiveSnapshot {
  status: LiveStatus;
  error: string | null;
  db: Database;
  personal: PersonalArea | null;
  notifications: AppNotification[];
  /** Storage folder that holds this database's photos. */
  photoRoot: string;
  isCouple: boolean;
}

const RECORDS = ['people', 'personNotes', 'matches', 'matchNotes', 'personEvents', 'matchStatusEvents'] as const;
type RecordCollection = (typeof RECORDS)[number];

function clean(data: DocumentData): DocumentData | null {
  if (data._deleted === true) return null;
  const out: DocumentData = {};
  for (const [k, v] of Object.entries(data)) if (!k.startsWith('_')) out[k] = v;
  return out;
}

const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null);
const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const arr = <T,>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : []);
const iso = (v: unknown, fallback = new Date(0).toISOString()): string => {
  if (typeof v === 'string') return v;
  if (v && typeof v === 'object' && 'toDate' in v) return (v as { toDate: () => Date }).toDate().toISOString();
  return fallback;
};

function toPerson(id: string, d: DocumentData): Person {
  const gender = (GENDERS as readonly string[]).includes(d.gender) ? (d.gender as Gender) : 'unknown';
  const status = (PROFILE_STATUSES as readonly string[]).includes(d.profileStatus) ? (d.profileStatus as ProfileStatus) : 'available';
  return {
    id: str(d.id) ?? id,
    firstName: str(d.firstName) ?? '',
    lastName: str(d.lastName),
    gender,
    manualAge: num(d.manualAge),
    manualAgeUpdatedAt: str(d.manualAgeUpdatedAt),
    religiousLevel: str(d.religiousLevel) as Person['religiousLevel'],
    religiousLevelOther: str(d.religiousLevelOther),
    city: str(d.city),
    phone: str(d.phone),
    source: str(d.source),
    notes: str(d.notes),
    description: str(d.description),
    inquiryContactName: str(d.inquiryContactName),
    inquiryContactPhone: str(d.inquiryContactPhone),
    heightCm: num(d.heightCm),
    maritalStatus: str(d.maritalStatus) as Person['maritalStatus'],
    region: str(d.region) as Person['region'],
    importBatchId: str(d.importBatchId),
    dateOfBirth: str(d.dateOfBirth),
    cardOwnerUid: str(d.cardOwnerUid),
    cardSyncDetached: d.cardSyncDetached === true,
    preSyncSnapshot: str(d.preSyncSnapshot),
    cardRemoteStatus: str(d.cardRemoteStatus),
    tags: arr<string>(d.tags).filter((t) => typeof t === 'string'),
    additionalContacts: arr(d.additionalContacts),
    preferredMinAge: num(d.preferredMinAge),
    preferredMaxAge: num(d.preferredMaxAge),
    preferredMinHeightCm: num(d.preferredMinHeightCm),
    preferredMaxHeightCm: num(d.preferredMaxHeightCm),
    preferredCity: str(d.preferredCity),
    preferredRegions: arr(d.preferredRegions),
    preferredMaritalStatuses: arr(d.preferredMaritalStatuses),
    preferredReligiousLevels: arr(d.preferredReligiousLevels),
    preferredReligiousLevelOtherLabels: arr(d.preferredReligiousLevelOtherLabels),
    profileStatus: status,
    photos: arr<string>(d.photos).filter((p) => typeof p === 'string').map((p) => p.split(/[\\/]/).pop() ?? p),
    isFavorite: d.isFavorite === true,
    needsReview: d.needsReview === true,
    hidden: d.hidden === true,
    avatarIndex: num(d.avatarIndex),
    createdAt: iso(d.createdAt),
    updatedAt: iso(d.updatedAt, iso(d.createdAt)),
  };
}

function toMatch(id: string, d: DocumentData): MatchIdea {
  return {
    id: str(d.id) ?? id,
    personAId: str(d.personAId) ?? '',
    personBId: str(d.personBId) ?? '',
    status: (str(d.status) ?? 'idea') as MatchIdea['status'],
    currentHandler: (str(d.currentHandler) ?? 'me') as MatchIdea['currentHandler'],
    handlerName: str(d.handlerName),
    reminderDate: str(d.reminderDate),
    reminderNote: str(d.reminderNote),
    waitingReason: str(d.waitingReason),
    progress: str(d.progress) as MatchIdea['progress'],
    progressOther: str(d.progressOther),
    relatedContacts: arr(d.relatedContacts),
    lastShareLabel: str(d.lastShareLabel),
    lastShareAt: str(d.lastShareAt),
    createdAt: iso(d.createdAt),
    updatedAt: iso(d.updatedAt, iso(d.createdAt)),
    askedMaleAt: str(d.askedMaleAt),
    askedFemaleAt: str(d.askedFemaleAt),
    checkInEveryDays: num(d.checkInEveryDays),
    datingStartedAt: str(d.datingStartedAt),
    datingEndedAt: str(d.datingEndedAt),
  };
}

const MAPPERS = {
  people: toPerson,
  matches: toMatch,
  personNotes: (id: string, d: DocumentData): PersonNote => ({
    id: str(d.id) ?? id,
    personId: str(d.personId) ?? '',
    text: typeof d.text === 'string' ? d.text : '',
    createdAt: iso(d.createdAt),
    isAutomatic: d.isAutomatic === true,
    audioFile: str(d.audioFile) ?? undefined,
    audioDurationMs: num(d.audioDurationMs) ?? undefined,
  }),
  matchNotes: (id: string, d: DocumentData): MatchNote => ({
    id: str(d.id) ?? id,
    matchId: str(d.matchId) ?? '',
    text: typeof d.text === 'string' ? d.text : '',
    createdAt: iso(d.createdAt),
    isAutomatic: d.isAutomatic === true,
    mazelTovFrom: str(d.mazelTovFrom),
  }),
  personEvents: (id: string, d: DocumentData): PersonEvent => ({
    id: str(d.id) ?? id,
    personId: str(d.personId) ?? '',
    type: (str(d.type) ?? 'note') as PersonEvent['type'],
    text: typeof d.text === 'string' ? d.text : '',
    createdAt: iso(d.createdAt),
    relatedPersonId: str(d.relatedPersonId),
    relatedMatchId: str(d.relatedMatchId),
  }),
  matchStatusEvents: (id: string, d: DocumentData): MatchStatusEvent => ({
    id: str(d.id) ?? id,
    matchId: str(d.matchId) ?? '',
    fromStatus: str(d.fromStatus) as MatchStatusEvent['fromStatus'],
    toStatus: (str(d.toStatus) ?? 'idea') as MatchStatusEvent['toStatus'],
    createdAt: iso(d.createdAt),
    automatic: d.automatic === true,
  }),
} satisfies Record<RecordCollection, (id: string, d: DocumentData) => unknown>;

/** A setting's `v` is JSON; some values are themselves JSON strings. */
function settingValue(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw;
  try {
    const once = JSON.parse(raw);
    if (typeof once === 'string' && /^[[{]/.test(once.trim())) {
      try {
        return JSON.parse(once);
      } catch {
        return once;
      }
    }
    return once;
  } catch {
    return raw;
  }
}

function profileFrom(settings: Map<string, unknown>, fallbackName: string | null): MatchmakerProfile {
  const full = (settings.get('userName') as string | undefined) ?? fallbackName ?? '';
  const [first, ...rest] = full.trim().split(/\s+/);
  const gender = settings.get('userGender');
  return {
    firstName: (settings.get('userFirstName') as string | undefined) ?? first ?? '',
    lastName: (settings.get('userLastName') as string | undefined) ?? rest.join(' '),
    gender: gender === 'female' || gender === 'male' ? gender : 'unknown',
    isSingle: settings.get('userIsSingle') === true,
    about: (settings.get('userAbout') as string | undefined) ?? null,
  };
}

function inboxKind(kind: string): AppNotification['kind'] {
  if (kind === 'cardCreated' || kind === 'accessApproved' || kind === 'accessRequest') return kind;
  if (kind.startsWith('support')) return 'support';
  return 'statusEvent';
}

const EMPTY_DB: Database = {
  profile: { firstName: '', lastName: '', gender: 'unknown', isSingle: false, about: null },
  people: [],
  personNotes: [],
  matches: [],
  matchNotes: [],
  personEvents: [],
  matchStatusEvents: [],
};

/** Starts every listener for [uid]; calls [onChange] with each new picture. */
export function subscribeAccount(uid: string, displayName: string | null, onChange: (s: LiveSnapshot) => void): () => void {
  const { db } = fb();
  const unsubs: Unsubscribe[] = [];
  let stopped = false;

  const records: Record<RecordCollection, Map<string, unknown>> = {
    people: new Map(),
    personNotes: new Map(),
    matches: new Map(),
    matchNotes: new Map(),
    personEvents: new Map(),
    matchStatusEvents: new Map(),
  };
  const loaded = new Set<string>();
  const settings = new Map<string, unknown>();
  let inbox: AppNotification[] = [];
  let access: CardAccessRow[] = [];
  let helpers: PersonalArea['helpers'] = [];
  let status: LiveStatus = 'connecting';
  let error: string | null = null;
  let photoRoot = `users/${uid}/photos`;
  let isCouple = false;
  let scheduled = false;

  const emit = () => {
    if (stopped || scheduled) return;
    scheduled = true;
    queueMicrotask(() => {
      scheduled = false;
      if (stopped) return;
      if (status === 'connecting' && RECORDS.every((c) => loaded.has(c)) && loaded.has('settings')) status = 'ready';
      const database: Database = {
        ...EMPTY_DB,
        profile: profileFrom(settings, displayName),
        people: [...records.people.values()] as Person[],
        personNotes: [...records.personNotes.values()] as PersonNote[],
        matches: [...records.matches.values()] as MatchIdea[],
        matchNotes: [...records.matchNotes.values()] as MatchNote[],
        personEvents: [...records.personEvents.values()] as PersonEvent[],
        matchStatusEvents: [...records.matchStatusEvents.values()] as MatchStatusEvent[],
      };
      const cardRaw = settings.get('personalCard.person');
      const card = cardRaw && typeof cardRaw === 'object' ? toPerson('personal-card', cardRaw as DocumentData) : null;
      const personal: PersonalArea | null = card
        ? {
            card,
            privateLooking: null,
            acceptsRequests: settings.get('personalCard.acceptsRequests') !== false,
            announces: settings.get('personalCard.announces') !== false,
            access,
            helpers: helpers.filter((h) => !access.some((a) => a.matchmakerUid === h.uid)),
          }
        : null;

      const now = Date.now();
      const byId = new Map(database.people.map((p) => [p.id, p]));
      const reminders: AppNotification[] = database.matches
        .filter((m) => m.reminderDate && new Date(m.reminderDate).getTime() <= now && !['rejected', 'dated', 'married'].includes(m.status))
        .map((m) => {
          const a = byId.get(m.personAId);
          const b = byId.get(m.personBId);
          return {
            id: `reminder:${m.id}:${m.reminderDate}`,
            kind: 'reminder' as const,
            title: m.reminderNote?.trim() || `לבדוק מה קורה עם ${a?.firstName ?? ''} ו${b?.firstName ?? ''}`,
            subtitle: 'תזכורת · רעיון',
            createdAt: m.reminderDate!,
            read: false,
            matchId: m.id,
          };
        });
      onChange({ status, error, db: database, personal, notifications: [...reminders, ...inbox], photoRoot, isCouple });
    });
  };

  const fail = (e: unknown) => {
    const code = (e as { code?: string })?.code ?? '';
    status = code.includes('permission-denied') ? 'denied' : 'error';
    error = code || String(e);
    emit();
  };

  (async () => {
    let databaseUid = uid;
    try {
      const membership = await getDoc(doc(db, 'memberships', uid));
      const m = membership.data();
      if (membership.exists() && m?.state === 'active' && typeof m.databaseUid === 'string') {
        databaseUid = m.databaseUid;
        isCouple = true;
        if (typeof m.operation === 'string') photoRoot = `coupleFiles/${m.operation}/photos`;
      }
    } catch (e) {
      // No membership document is the ordinary case; a denial here means App
      // Check or the rules refused us, which every other read will hit too.
      const code = (e as { code?: string })?.code ?? '';
      if (code.includes('permission-denied')) return fail(e);
    }
    if (stopped) return;

    for (const name of RECORDS) {
      unsubs.push(
        onSnapshot(
          collection(db, 'users', databaseUid, name),
          (snap) => {
            for (const change of snap.docChanges()) {
              const data = clean(change.doc.data());
              if (change.type === 'removed' || !data) records[name].delete(change.doc.id);
              else records[name].set(change.doc.id, MAPPERS[name](change.doc.id, data));
            }
            loaded.add(name);
            emit();
          },
          fail,
        ),
      );
    }

    unsubs.push(
      onSnapshot(
        collection(db, 'users', uid, 'settings'),
        (snap) => {
          for (const change of snap.docChanges()) {
            const data = change.doc.data();
            const key = typeof data.k === 'string' ? data.k : decodeURIComponent(change.doc.id);
            if (change.type === 'removed' || data._deleted === true) settings.delete(key);
            else settings.set(key, settingValue(data.v));
          }
          loaded.add('settings');
          emit();
        },
        fail,
      ),
    );

    unsubs.push(
      onSnapshot(
        query(collection(db, 'users', uid, 'inbox'), orderBy('createdAt', 'desc'), limit(100)),
        (snap) => {
          inbox = snap.docs.map((d) => {
            const v = d.data();
            const body = typeof v.body === 'string' && v.body.trim() ? v.body : null;
            return {
              id: d.id,
              kind: inboxKind(String(v.kind ?? '')),
              title: String(v.title ?? ''),
              subtitle: body,
              createdAt: iso(v.createdAt, new Date().toISOString()),
              read: v.read === true,
            };
          });
          emit();
        },
        () => {
          /* the inbox is optional — never block the database on it */
        },
      ),
    );

    unsubs.push(
      onSnapshot(
        query(collection(db, 'cardAccess'), where('ownerUid', '==', uid)),
        (snap) => {
          access = snap.docs
            .map((d) => d.data())
            .filter((v) => ['pending', 'approved', 'declined'].includes(v.status))
            .map((v) => ({
              matchmakerUid: String(v.matchmakerUid ?? ''),
              matchmakerName: String(v.matchmakerName ?? ''),
              matchmakerGender: v.matchmakerGender === 'male' || v.matchmakerGender === 'female' ? v.matchmakerGender : null,
              status: v.status as AccessState,
              seesPrivateLooking: v.lookingGranted === true,
              requestedAt: iso(v.updatedAt ?? v.createdAt),
              databaseCount: null,
              lastActiveAt: null,
            }));
          emit();
        },
        () => {},
      ),
    );

    unsubs.push(
      onSnapshot(
        doc(db, 'users', uid, 'private', 'helpers'),
        (snap) => {
          const list = snap.data()?.helpers;
          helpers = Array.isArray(list)
            ? list
                .filter((h) => h && typeof h.uid === 'string' && h.uid !== uid)
                .map((h) => ({
                  uid: h.uid as string,
                  name: String(h.name ?? ''),
                  databaseCount: num(h.databaseCount),
                  lastActiveAt: h.lastActiveAt ? iso(h.lastActiveAt) : null,
                }))
            : [];
          emit();
        },
        () => {},
      ),
    );
  })();

  emit();
  return () => {
    stopped = true;
    for (const u of unsubs) u();
  };
}
