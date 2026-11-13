'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { MatchStatus, ProfileStatus } from '@/domain/enums';
import type { AccessState, AppNotification, Database, MatchIdea, Person, PersonalArea } from '@/domain/types';
import { demoDatabase, demoNotifications, demoPersonal } from './demo';
import { onAuthStateChanged } from 'firebase/auth';
import { useToast } from '@/components/toast';
import { fb, firebaseConfigured, signOutFirebase } from './firebase';
import { subscribeAccount, type LiveSnapshot, type LiveStatus } from './live';

/**
 * The one place the screens read and write.
 *
 * Two sources behind one API:
 * - **demo** — a made-up database in memory; edits work and a refresh resets it.
 * - **live** — the signed-in account, read from Firestore by `subscribeAccount`.
 *   This phase is read-only: every mutator answers with a notice instead of
 *   writing. Writes come next, and must set `_w: serverTimestamp()` and write
 *   tombstones rather than delete — that is what the phones' `AccountSyncEngine`
 *   listens for.
 */

export type Area = 'matchmaker' | 'personal';

interface Session {
  signedIn: boolean;
  method: 'demo' | 'google' | 'apple' | 'email' | null;
  email: string | null;
  uid?: string | null;
}

export type DataMode = 'demo' | 'live';

interface Store {
  session: Session;
  mode: DataMode;
  /** True while the current data cannot be edited from the web. */
  readOnly: boolean;
  liveStatus: LiveStatus | null;
  liveError: string | null;
  /** Storage folder for this database's photos (live only). */
  photoRoot: string | null;
  isCouple: boolean;
  /** Firebase is still telling us whether somebody is signed in. */
  authPending: boolean;
  signIn: (method: Session['method'], email?: string) => void;
  signOut: () => void;

  db: Database;
  byId: Map<string, Person>;
  visiblePeople: Person[];
  personal: PersonalArea | null;
  notifications: AppNotification[];
  unreadCount: number;

  updatePerson: (id: string, patch: Partial<Person>) => void;
  addPerson: (p: Partial<Person> & Pick<Person, 'firstName' | 'gender'>) => Person | null;
  deletePerson: (id: string) => void;
  setProfileStatus: (id: string, status: ProfileStatus) => void;
  toggleFavorite: (id: string) => void;
  addPersonNote: (personId: string, text: string) => void;

  createMatch: (aId: string, bId: string) => MatchIdea | null;
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

const demoEmpty: Database = { ...demoDatabase, people: [], personNotes: [], matches: [], matchNotes: [], personEvents: [], matchStatusEvents: [] };

const READ_ONLY_NOTICE = 'בשלב הזה האתר מציג את המאגר האמיתי לקריאה בלבד. עריכה — דרך האפליקציה, ובקרוב גם כאן.';

export function StoreProvider({ children }: { children: ReactNode }) {
  const toast = useToast();
  const [session, setSession] = useState<Session>({ signedIn: false, method: null, email: null });
  const [hydrated, setHydrated] = useState(false);
  const [authPending, setAuthPending] = useState(firebaseConfigured);
  const [live, setLive] = useState<LiveSnapshot | null>(null);
  const [readIds, setReadIds] = useState<Set<string>>(new Set());
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

  // The real account: Firebase decides who is signed in, and a signed-in,
  // non-anonymous user replaces any demo session.
  useEffect(() => {
    if (!firebaseConfigured) return;
    let stopLive: (() => void) | null = null;
    const stopAuth = onAuthStateChanged(fb().auth, (user) => {
      stopLive?.();
      stopLive = null;
      setAuthPending(false);
      if (user && !user.isAnonymous) {
        const provider = user.providerData[0]?.providerId ?? '';
        setSession({
          signedIn: true,
          method: provider.includes('google') ? 'google' : provider.includes('apple') ? 'apple' : 'email',
          email: user.email,
          uid: user.uid,
        });
        setLive(null);
        stopLive = subscribeAccount(user.uid, user.displayName, setLive);
      } else {
        setLive(null);
        setSession((s) => (s.method === 'demo' ? s : { signedIn: false, method: null, email: null }));
      }
    });
    return () => {
      stopAuth();
      stopLive?.();
    };
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
    void signOutFirebase();
    setLive(null);
    setSession({ signedIn: false, method: null, email: null });
    try {
      sessionStorage.removeItem(SESSION_KEY);
    } catch {
      /* ignore */
    }
  }, []);

  const mode: DataMode = session.signedIn && session.method !== 'demo' ? 'live' : 'demo';
  const activeDb = mode === 'live' ? live?.db ?? demoEmpty : db;
  const byId = useMemo(() => new Map(activeDb.people.map((p) => [p.id, p])), [activeDb.people]);
  const visiblePeople = useMemo(() => activeDb.people.filter((p) => !p.hidden), [activeDb.people]);

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

  const demoStore: Store = {
    session,
    mode,
    readOnly: false,
    liveStatus: null,
    liveError: null,
    photoRoot: null,
    isCouple: false,
    authPending,
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

  let store: Store = demoStore;
  if (mode === 'live') {
    const blocked = () => toast(READ_ONLY_NOTICE, undefined, { priority: true });
    const liveNotifications = (live?.notifications ?? []).map((n) => (readIds.has(n.id) ? { ...n, read: true } : n));
    store = {
      ...demoStore,
      readOnly: true,
      liveStatus: live?.status ?? 'connecting',
      liveError: live?.error ?? null,
      photoRoot: live?.photoRoot ?? null,
      isCouple: live?.isCouple ?? false,
      db: activeDb,
      personal: live?.personal ?? null,
      notifications: liveNotifications,
      unreadCount: liveNotifications.filter((n) => !n.read).length,
      updatePerson: blocked,
      addPerson: () => (blocked(), null),
      deletePerson: blocked,
      setProfileStatus: blocked,
      toggleFavorite: blocked,
      addPersonNote: blocked,
      createMatch: () => (blocked(), null),
      setMatchStatus: blocked,
      markAsked: blocked,
      setReminder: blocked,
      addMatchNote: blocked,
      deleteMatch: blocked,
      // Read state is kept in this tab only until writes arrive.
      markAllRead: () => setReadIds(new Set(liveNotifications.map((n) => n.id))),
      markRead: (id) => setReadIds((s) => new Set(s).add(id)),
      setAccess: blocked,
      togglePrivateFor: blocked,
      setPersonalStatus: blocked,
      updatePersonal: blocked,
      updatePersonalCard: blocked,
    };
  }

  if (!hydrated) return null;
  return <Ctx.Provider value={store}>{children}</Ctx.Provider>;
}

/** The personal area; `/me` pages render only when it exists (see me/layout). */
export function usePersonal(): PersonalArea {
  const p = useStore().personal;
  if (!p) throw new Error('usePersonal without a personal card');
  return p;
}

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error('useStore outside StoreProvider');
  return s;
}
