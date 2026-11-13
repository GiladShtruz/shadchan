'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { MatchStatus, ProfileStatus } from '@/domain/enums';
import type { AccessState, AppNotification, Database, MatchIdea, Person, PersonalArea } from '@/domain/types';
import { demoDatabase, demoNotifications, demoPersonal } from './demo';

/**
 * The one place the screens read and write.
 *
 * In this prototype it holds the demo database in memory: edits work and are
 * visible everywhere at once, and a refresh puts the demo back. The next phase
 * keeps this exact API and swaps what is behind it: a Firestore listener on
 * `users/{uid}/*` fills the state, and every write goes to Firestore with
 * `_w: serverTimestamp()` (and tombstones, never hard deletes), which is what
 * the phones' `AccountSyncEngine` listens for.
 */

export type Area = 'matchmaker' | 'personal';

interface Session {
  signedIn: boolean;
  method: 'demo' | 'google' | 'apple' | 'email' | null;
  email: string | null;
}

interface Store {
  session: Session;
  signIn: (method: Session['method'], email?: string) => void;
  signOut: () => void;

  db: Database;
  byId: Map<string, Person>;
  visiblePeople: Person[];
  personal: PersonalArea;
  notifications: AppNotification[];
  unreadCount: number;

  updatePerson: (id: string, patch: Partial<Person>) => void;
  addPerson: (p: Partial<Person> & Pick<Person, 'firstName' | 'gender'>) => Person;
  deletePerson: (id: string) => void;
  setProfileStatus: (id: string, status: ProfileStatus) => void;
  toggleFavorite: (id: string) => void;
  addPersonNote: (personId: string, text: string) => void;

  createMatch: (aId: string, bId: string) => MatchIdea;
  setMatchStatus: (id: string, status: MatchStatus, reason?: string) => void;
  markAsked: (id: string, side: 'male' | 'female') => void;
  setReminder: (id: string, iso: string | null, note?: string | null) => void;
  addMatchNote: (matchId: string, text: string) => void;
  deleteMatch: (id: string) => void;

  markAllRead: () => void;
  markRead: (id: string) => void;

  setAccess: (matchmakerUid: string, status: AccessState | 'removed') => void;
  togglePrivateFor: (matchmakerUid: string) => void;
  setPersonalStatus: (status: ProfileStatus) => void;
  updatePersonal: (patch: Partial<PersonalArea>) => void;
  updatePersonalCard: (patch: Partial<Person>) => void;
}

const Ctx = createContext<Store | null>(null);

const SESSION_KEY = 'shadchan.web.session';

const nowIso = () => new Date().toISOString();
const newId = () => (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : String(Math.random()).slice(2));

export function StoreProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session>({ signedIn: false, method: null, email: null });
  const [hydrated, setHydrated] = useState(false);
  const [db, setDb] = useState<Database>(demoDatabase);
  const [personal, setPersonal] = useState<PersonalArea>(demoPersonal);
  const [notifications, setNotifications] = useState<AppNotification[]>(() => demoNotifications(demoDatabase));

  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(SESSION_KEY);
      if (raw) setSession(JSON.parse(raw) as Session);
    } catch {
      /* private mode — stays signed out */
    }
    setHydrated(true);
  }, []);

  const signIn = useCallback((method: Session['method'], email?: string) => {
    const s: Session = { signedIn: true, method, email: email ?? null };
    setSession(s);
    try {
      sessionStorage.setItem(SESSION_KEY, JSON.stringify(s));
    } catch {
      /* ignore */
    }
  }, []);

  const signOut = useCallback(() => {
    setSession({ signedIn: false, method: null, email: null });
    try {
      sessionStorage.removeItem(SESSION_KEY);
    } catch {
      /* ignore */
    }
  }, []);

  const byId = useMemo(() => new Map(db.people.map((p) => [p.id, p])), [db.people]);
  const visiblePeople = useMemo(() => db.people.filter((p) => !p.hidden), [db.people]);

  const patchPerson = useCallback((id: string, fn: (p: Person) => Person) => {
    setDb((d) => ({ ...d, people: d.people.map((p) => (p.id === id ? { ...fn(p), updatedAt: nowIso() } : p)) }));
  }, []);

  const patchMatch = useCallback((id: string, fn: (m: MatchIdea) => MatchIdea) => {
    setDb((d) => ({ ...d, matches: d.matches.map((m) => (m.id === id ? { ...fn(m), updatedAt: nowIso() } : m)) }));
  }, []);

  const journal = useCallback((matchId: string, text: string, auto: boolean) => {
    setDb((d) => ({
      ...d,
      matchNotes: [...d.matchNotes, { id: newId(), matchId, text, createdAt: nowIso(), isAutomatic: auto, mazelTovFrom: null }],
    }));
  }, []);

  const store: Store = {
    session,
    signIn,
    signOut,
    db,
    byId,
    visiblePeople,
    personal,
    notifications,
    unreadCount: notifications.filter((n) => !n.read).length,

    updatePerson: (id, patch) => patchPerson(id, (p) => ({ ...p, ...patch })),
    addPerson: (partial) => {
      const base = demoDatabase.people[0];
      const p: Person = {
        ...base,
        lastName: null,
        manualAge: null,
        manualAgeUpdatedAt: nowIso(),
        religiousLevel: null,
        city: null,
        phone: null,
        description: null,
        inquiryContactName: null,
        heightCm: null,
        maritalStatus: null,
        region: null,
        cardOwnerUid: null,
        tags: [],
        profileStatus: 'available',
        isFavorite: false,
        ...partial,
        id: newId(),
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      setDb((d) => ({ ...d, people: [p, ...d.people] }));
      return p;
    },
    deletePerson: (id) =>
      setDb((d) => ({
        ...d,
        people: d.people.filter((p) => p.id !== id),
        matches: d.matches.filter((m) => m.personAId !== id && m.personBId !== id),
      })),
    setProfileStatus: (id, status) => patchPerson(id, (p) => ({ ...p, profileStatus: status })),
    toggleFavorite: (id) => patchPerson(id, (p) => ({ ...p, isFavorite: !p.isFavorite })),
    addPersonNote: (personId, text) =>
      setDb((d) => ({ ...d, personNotes: [...d.personNotes, { id: newId(), personId, text, createdAt: nowIso(), isAutomatic: false }] })),

    createMatch: (aId, bId) => {
      const m: MatchIdea = {
        id: newId(),
        personAId: aId,
        personBId: bId,
        status: 'idea',
        currentHandler: 'me',
        handlerName: null,
        reminderDate: new Date(Date.now() + 30 * 86400000).toISOString(),
        reminderNote: null,
        waitingReason: null,
        progress: null,
        progressOther: null,
        relatedContacts: [],
        lastShareLabel: null,
        lastShareAt: null,
        createdAt: nowIso(),
        updatedAt: nowIso(),
        askedMaleAt: null,
        askedFemaleAt: null,
      };
      setDb((d) => ({ ...d, matches: [m, ...d.matches] }));
      const a = byId.get(aId);
      const b = byId.get(bId);
      journal(m.id, `נפתח רעיון בין ${a?.firstName ?? ''} ל${b?.firstName ?? ''}`, true);
      return m;
    },
    setMatchStatus: (id, status, reason) => {
      const words: Partial<Record<MatchStatus, string>> = {
        idea: 'הרעיון נפתח מחדש',
        unavailable: `הרעיון הועבר להמתנה${reason ? ` — ${reason}` : ''}`,
        dating: 'מתחילים לצאת! 🎉',
        dated: 'הזוג החליטו להיפרד',
        rejected: `הרעיון נסגר${reason ? ` — ${reason}` : ''}`,
        married: 'מזל טוב! 💍',
      };
      patchMatch(id, (m) => ({
        ...m,
        status,
        waitingReason: status === 'unavailable' ? reason ?? null : m.waitingReason,
        datingStartedAt: status === 'dating' ? nowIso() : m.datingStartedAt,
        datingEndedAt: status === 'dated' ? nowIso() : m.datingEndedAt,
        reminderDate: status === 'rejected' || status === 'dated' || status === 'married' ? null : m.reminderDate,
      }));
      const w = words[status];
      if (w) journal(id, w, true);
    },
    markAsked: (id, side) => {
      const m = db.matches.find((x) => x.id === id);
      if (!m) return;
      const a = byId.get(m.personAId);
      const b = byId.get(m.personBId);
      const male = a?.gender === 'male' ? a : b;
      const female = a?.gender === 'male' ? b : a;
      const to = side === 'male' ? male : female;
      const of = side === 'male' ? female : male;
      patchMatch(id, (x) => ({
        ...x,
        status: x.status === 'idea' ? 'checking' : x.status,
        askedMaleAt: side === 'male' ? nowIso() : x.askedMaleAt,
        askedFemaleAt: side === 'female' ? nowIso() : x.askedFemaleAt,
        lastShareLabel: `הכרטיס של ${of?.firstName ?? ''} נשלח ל${to?.firstName ?? ''}`,
        lastShareAt: nowIso(),
      }));
      journal(id, `נשלח הכרטיס של ${of?.firstName ?? ''} אל ${to?.firstName ?? ''}`, true);
    },
    setReminder: (id, iso, note) => {
      patchMatch(id, (m) => ({ ...m, reminderDate: iso, reminderNote: note ?? m.reminderNote }));
    },
    addMatchNote: (matchId, text) => journal(matchId, text, false),
    deleteMatch: (id) => setDb((d) => ({ ...d, matches: d.matches.filter((m) => m.id !== id) })),

    markAllRead: () => setNotifications((ns) => ns.map((n) => ({ ...n, read: true }))),
    markRead: (id) => setNotifications((ns) => ns.map((n) => (n.id === id ? { ...n, read: true } : n))),

    setAccess: (uid, status) =>
      setPersonal((pa) => {
        if (status === 'removed') return { ...pa, access: pa.access.filter((a) => a.matchmakerUid !== uid) };
        const existing = pa.access.find((a) => a.matchmakerUid === uid);
        if (existing) return { ...pa, access: pa.access.map((a) => (a.matchmakerUid === uid ? { ...a, status } : a)) };
        const helper = pa.helpers.find((h) => h.uid === uid);
        if (!helper) return pa;
        return {
          ...pa,
          helpers: pa.helpers.filter((h) => h.uid !== uid),
          access: [
            ...pa.access,
            {
              matchmakerUid: uid,
              matchmakerName: helper.name,
              matchmakerGender: null,
              status,
              seesPrivateLooking: false,
              requestedAt: nowIso(),
              databaseCount: helper.databaseCount,
              lastActiveAt: helper.lastActiveAt,
            },
          ],
        };
      }),
    togglePrivateFor: (uid) =>
      setPersonal((pa) => ({
        ...pa,
        access: pa.access.map((a) => (a.matchmakerUid === uid ? { ...a, seesPrivateLooking: !a.seesPrivateLooking } : a)),
      })),
    setPersonalStatus: (status) => setPersonal((pa) => ({ ...pa, card: { ...pa.card, profileStatus: status, updatedAt: nowIso() } })),
    updatePersonal: (patch) => setPersonal((pa) => ({ ...pa, ...patch })),
    updatePersonalCard: (patch) => setPersonal((pa) => ({ ...pa, card: { ...pa.card, ...patch, updatedAt: nowIso() } })),
  };

  if (!hydrated) return null;
  return <Ctx.Provider value={store}>{children}</Ctx.Provider>;
}

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error('useStore outside StoreProvider');
  return s;
}
