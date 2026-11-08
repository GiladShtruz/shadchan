/**
 * The administrators' dashboard — "נתונים" in the support console.
 *
 * Computed here, on the server, from the data the product already keeps,
 * every few hours and on demand. **Only counts leave this file**: no uid, no
 * name, no number. The document it writes (`adminStats/current`, plus one
 * snapshot a day under `adminStats/history/days/{yyyy-mm-dd}` for trends) is
 * readable by support administrators only (`firestore.rules`).
 *
 * Funnels, retention and cohorts come from Google Analytics for Firebase
 * (the console's own reports); this file answers the questions the data
 * itself can answer exactly — how many cards are live, how many trust links
 * exist, how big the databases are.
 */
import { getAuth, UserRecord } from 'firebase-admin/auth';
import { Firestore, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { isActiveCard } from './card_activity';
import {
  AdminAlert,
  ContactsBlock,
  ContactsDevice,
  computeAlerts,
  contactsBlock,
  newAlerts,
} from './admin_alerts';
import { notify } from './notices';

const ROOT_ADMIN = 'yitz292@gmail.com';
const DAY = 24 * 60 * 60 * 1000;

export interface AdminStats {
  computedAt: number;
  users: Record<string, number>;
  activity: Record<string, number>;
  singles: Record<string, number>;
  access: Record<string, number>;
  ideas: Record<string, number>;
  databases: Record<string, number>;
  contacts: ContactsBlock;
  alerts: AdminAlert[];
}

function isoMillis(value: unknown): number | undefined {
  if (typeof value !== 'string') return undefined;
  const t = Date.parse(value);
  return Number.isNaN(t) ? undefined : t;
}

/** Every device's address-book report, from `accountHealth` (no contacts). */
async function contactDevices(db: Firestore, internal: Set<string>): Promise<ContactsDevice[]> {
  const out: ContactsDevice[] = [];
  const docs = await db.collection('accountHealth').select('devices').get();
  for (const doc of docs.docs) {
    if (internal.has(doc.id)) continue;
    const devices = doc.get('devices');
    if (!devices || typeof devices !== 'object') continue;
    for (const device of Object.values(devices as Record<string, unknown>)) {
      if (!device || typeof device !== 'object') continue;
      const d = device as Record<string, unknown>;
      const c = d.contacts as Record<string, unknown> | undefined;
      if (!c || typeof c !== 'object') continue;
      const version = typeof d.appVersion === 'string' && /\d/.test(d.appVersion) ? d.appVersion : undefined;
      out.push({
        appVersion: version,
        readAt: isoMillis(c.readAt),
        failedAt: isoMillis(c.failedAt),
        failure: typeof c.failure === 'string' ? c.failure : undefined,
        permission: typeof c.permission === 'string' ? c.permission : undefined,
        suitable: typeof c.suitable === 'number' ? c.suitable : undefined,
        deviceCount: typeof c.deviceCount === 'number' ? c.deviceCount : undefined,
      });
    }
  }
  return out;
}

function millis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === 'number') return value;
  return null;
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

/** Every durable (non-anonymous) account, with administrators set apart. */
async function listAccounts(adminEmails: Set<string>): Promise<{
  users: UserRecord[];
  internal: Set<string>;
}> {
  const users: UserRecord[] = [];
  const internal = new Set<string>();
  let token: string | undefined;
  do {
    const page = await getAuth().listUsers(1000, token);
    for (const user of page.users) {
      if (user.providerData.length === 0) continue; // anonymous
      const email = (user.email ?? '').toLowerCase();
      if (email && adminEmails.has(email)) {
        internal.add(user.uid);
        continue;
      }
      users.push(user);
    }
    token = page.pageToken;
  } while (token);
  return { users, internal };
}

export async function computeAdminStats(db: Firestore, now = Date.now()): Promise<AdminStats> {
  const admins = await db.collection('supportAdmins').get();
  const adminEmails = new Set<string>([ROOT_ADMIN, ...admins.docs.map((d) => d.id.toLowerCase())]);
  const { users, internal } = await listAccounts(adminEmails);

  // ---- accounts
  const created = users.map((u) => Date.parse(u.metadata.creationTime));
  const inWindow = (t: number, from: number, to: number) => t >= now - from && t < now - to;
  const usersBlock = {
    total: users.length,
    newToday: created.filter((t) => inWindow(t, DAY, 0)).length,
    new7: created.filter((t) => inWindow(t, 7 * DAY, 0)).length,
    newPrev7: created.filter((t) => inWindow(t, 14 * DAY, 7 * DAY)).length,
    new30: created.filter((t) => inWindow(t, 30 * DAY, 0)).length,
    newPrev30: created.filter((t) => inWindow(t, 60 * DAY, 30 * DAY)).length,
    internalExcluded: internal.size,
  };

  // ---- activity: the app reports itself in the foreground (matchmakerActivity)
  const activityDocs = (await db.collection('matchmakerActivity').get()).docs.filter(
    (d) => !internal.has(d.id),
  );
  const lastActive = activityDocs.map((d) => millis(d.get('lastActiveAt'))).filter((t): t is number => t !== null);
  const dau = lastActive.filter((t) => t >= now - DAY).length;
  const wau = lastActive.filter((t) => t >= now - 7 * DAY).length;
  const wauPrev = lastActive.filter((t) => t >= now - 14 * DAY && t < now - 7 * DAY).length;
  const mau = lastActive.filter((t) => t >= now - 30 * DAY).length;

  // ---- community counters (what matchmakers actually did)
  const members = (await db.collection('communityMembers').get()).docs.filter((d) => !internal.has(d.id));
  // The current window is the newest key in use — a member who has not opened
  // the app this week still carries last week's.
  const newestKey = (field: string) =>
    members.reduce((best, d) => {
      const key = d.get(field);
      return typeof key === 'string' && key > best ? key : best;
    }, '');
  const weekKey = newestKey('weekKey');
  const monthKey = newestKey('monthKey');
  const inWeek = members.filter((d) => d.get('weekKey') === weekKey);
  const inMonth = members.filter((d) => d.get('monthKey') === monthKey);
  const sum = (docs: typeof members, field: string) =>
    docs.reduce((n, d) => n + (typeof d.get(field) === 'number' ? (d.get(field) as number) : 0), 0);

  const activityBlock = {
    dau,
    wau,
    wauPrev,
    mau,
    wauMauPercent: mau ? Math.round((wau / mau) * 100) : 0,
    activeMatchmakersWeek: inWeek.filter((d) => (d.get('weekActions') ?? 0) > 0).length,
    activeMatchmakersMonth: inMonth.filter((d) => (d.get('monthActions') ?? 0) > 0).length,
    pointsWeek: sum(inWeek, 'weekActions'),
    pointsAll: sum(members, 'allActions'),
  };

  const ideasAll = sum(members, 'allIdeas');
  const datingAll = sum(members, 'allCouples');
  const ideasBlock = {
    newWeek: sum(inWeek, 'weekIdeas'),
    newMonth: sum(inMonth, 'monthIdeas'),
    datingWeek: sum(inWeek, 'weekCouples'),
    datingMonth: sum(inMonth, 'monthCouples'),
    weddingsMonth: sum(inMonth, 'monthEngagements'),
    ideasAll,
    datingAll,
    datingPercent: ideasAll ? Math.round((datingAll / ideasAll) * 1000) / 10 : 0,
    weddingsAll: sum(members, 'allEngagements'),
    friendsWeek: sum(inWeek, 'weekFriends'),
  };

  // ---- personal cards and access
  const cards = (
    await db.collection('personalCards').select('description', 'photoPaths', 'deleted', 'joinedAt').get()
  ).docs.filter((d) => !internal.has(d.id));
  const liveOwners = new Set(cards.filter((d) => isActiveCard(d.data())).map((d) => d.id));
  const access = (await db.collection('cardAccess').select('ownerUid', 'matchmakerUid', 'status', 'createdAt', 'updatedAt').get()).docs;
  const approved = access.filter((d) => d.get('status') === 'approved');
  const trust = approved.filter((d) => liveOwners.has(d.get('ownerUid')));
  const perOwner = new Map<string, number>();
  const perDatabase = new Map<string, number>();
  for (const d of trust) {
    perOwner.set(d.get('ownerUid'), (perOwner.get(d.get('ownerUid')) ?? 0) + 1);
    perDatabase.set(d.get('matchmakerUid'), (perDatabase.get(d.get('matchmakerUid')) ?? 0) + 1);
  }
  const requestedOwners = new Set(access.map((d) => d.get('ownerUid') as string));
  const recent = (d: FirebaseFirestore.QueryDocumentSnapshot, field: string) =>
    (millis(d.get(field)) ?? 0) >= now - 7 * DAY;

  const singlesBlock = {
    cardsStarted: cards.filter((d) => d.get('deleted') !== true).length,
    cardsActive: liveOwners.size,
    newActive7: cards.filter((d) => liveOwners.has(d.id) && recent(d, 'joinedAt')).length,
    gotRequest: [...liveOwners].filter((uid) => requestedOwners.has(uid)).length,
    approvedOne: [...perOwner.values()].filter((n) => n >= 1).length,
    approvedTwoPlus: [...perOwner.values()].filter((n) => n >= 2).length,
  };
  const accessBlock = {
    pending: access.filter((d) => d.get('status') === 'pending').length,
    approvedTotal: approved.length,
    trustLinks: trust.length,
    newRequests7: access.filter((d) => recent(d, 'createdAt')).length,
    newApprovals7: approved.filter((d) => recent(d, 'updatedAt')).length,
    avgMatchmakersPerSingle: liveOwners.size ? round1(trust.length / liveOwners.size) : 0,
    avgCardsPerDatabase: perDatabase.size ? round1(trust.length / perDatabase.size) : 0,
  };

  // ---- database sizes (reported by each matchmaker's own app)
  const sizes = activityDocs
    .map((d) => d.get('databaseCount'))
    .filter((n): n is number => typeof n === 'number' && n > 0);
  const between = (lo: number, hi: number) => sizes.filter((n) => n >= lo && n <= hi).length;
  const databasesBlock = {
    count: sizes.length,
    average: sizes.length ? round1(sizes.reduce((a, b) => a + b, 0) / sizes.length) : 0,
    median: median(sizes),
    b1_4: between(1, 4),
    b5_9: between(5, 9),
    b10_24: between(10, 24),
    b25_49: between(25, 49),
    b50plus: sizes.filter((n) => n >= 50).length,
    reached5: sizes.filter((n) => n >= 5).length,
    reached10: sizes.filter((n) => n >= 10).length,
  };

  // ---- address-book reads, and the early warnings
  const devices = await contactDevices(db, internal);
  const contacts = contactsBlock(devices, now);
  const history = (
    await db
      .collection('adminStats/history/days')
      .orderBy('computedAt', 'desc')
      .limit(8)
      .get()
  ).docs
    .map((d) => d.data())
    .reverse();
  const weekAgo = history.find((h) => typeof h.computedAt === 'number' && h.computedAt <= now - 6.5 * DAY);
  const reminders = await db.doc('publicStats/serverReminders').get();
  const alerts = computeAlerts({
    now,
    contacts,
    contactDevices: devices,
    dau,
    dauHistory: history
      .filter((h) => typeof h.computedAt === 'number' && h.computedAt < now - 12 * 60 * 60 * 1000)
      .map((h) => h.activity?.dau)
      .filter((n): n is number => typeof n === 'number')
      .slice(-7),
    new7: usersBlock.new7,
    newPrev7: usersBlock.newPrev7,
    pending: accessBlock.pending,
    pendingWeekAgo: typeof weekAgo?.access?.pending === 'number' ? weekAgo.access.pending : null,
    remindersLastRunAt: millis(reminders.get('lastRunAt')),
  });

  return {
    computedAt: now,
    users: usersBlock,
    activity: activityBlock,
    singles: singlesBlock,
    access: accessBlock,
    ideas: ideasBlock,
    databases: databasesBlock,
    contacts,
    alerts,
  };
}

/** Tells every administrator about alerts that were not raised last time. */
async function announceAlerts(db: Firestore, fresh: AdminAlert[]): Promise<void> {
  if (fresh.length === 0) return;
  const admins = await db.collection('supportAdmins').get();
  const emails = [ROOT_ADMIN, ...admins.docs.map((d) => d.id.toLowerCase())];
  const title = fresh.length === 1 ? fresh[0].title : `${fresh.length} בעיות בולטות בנתונים`;
  const body = fresh.length === 1 ? fresh[0].detail : fresh.map((a) => a.title).join(' · ');
  for (const email of emails) {
    try {
      const user = await getAuth().getUserByEmail(email);
      await notify(user.uid, { kind: 'adminAlert', title, body, route: '/profile/admin' });
    } catch (error) {
      console.warn('announceAlerts: could not tell an administrator', error);
    }
  }
}

/** Israel's calendar day, for the history document's id. */
function israelDay(now: number): string {
  return new Date(now).toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' });
}

export async function writeAdminStats(db: Firestore): Promise<AdminStats> {
  const previous = await db.doc('adminStats/current').get();
  const stats = await computeAdminStats(db);
  await announceAlerts(db, newAlerts(previous.get('alerts') as AdminAlert[] | undefined, stats.alerts));
  const payload = { ...stats, updatedAt: FieldValue.serverTimestamp() };
  await db.doc('adminStats/current').set(payload);
  await db.doc(`adminStats/history/days/${israelDay(stats.computedAt)}`).set(payload);
  return stats;
}

/** Whether [email] may read the dashboard — the same list the rules use. */
export async function isSupportAdminEmail(db: Firestore, email: string | undefined): Promise<boolean> {
  const lower = (email ?? '').toLowerCase();
  if (!lower) return false;
  if (lower === ROOT_ADMIN) return true;
  return (await db.doc(`supportAdmins/${lower}`).get()).exists;
}
