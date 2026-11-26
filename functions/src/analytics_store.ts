/**
 * Firestore around the monitoring pipeline (`analytics.ts`):
 *
 * - [processBatch] folds one `telemetryBatches/{id}` into
 *   `analyticsUserDays/{day}_{uid}` and `analyticsUsers/{uid}` (and
 *   `analyticsVersions/{version}`'s first day), then deletes the batch.
 * - [dashboard] answers the console for any period and segment, comparing
 *   with the period before; cached for 20 minutes.
 * - [userDetail] is one account's drill-down.
 * - [checkThresholds] raises the administrator's alerts.
 *
 * Every collection here is server-written and readable by support
 * administrators only (`firestore.rules`).
 */
import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import {
  Account,
  addDays,
  addDeltas,
  applyBatch,
  BatchHeader,
  daysBetween,
  israelDay,
  PricingVersion,
  pricingAt,
  RawEvent,
  Segment,
  summarize,
  thresholdAlerts,
  Thresholds,
  updateSummary,
  UserDay,
  UserSummary,
} from './analytics';
import { announceAlerts, listAccounts } from './admin_stats';

const ROOT_ADMIN = 'yitz292@gmail.com';

let pricingCache: { at: number; versions: PricingVersion[] } | undefined;

export async function loadPricing(db: Firestore): Promise<PricingVersion[]> {
  if (pricingCache && Date.now() - pricingCache.at < 5 * 60 * 1000) return pricingCache.versions;
  const doc = await db.doc('adminConfig/pricing').get();
  const raw = doc.get('versions');
  const versions: PricingVersion[] = Array.isArray(raw) ? (raw as PricingVersion[]) : [];
  pricingCache = { at: Date.now(), versions };
  return versions;
}

export async function processBatch(db: Firestore, batchId: string, data: Record<string, unknown>): Promise<void> {
  const header: BatchHeader = {
    uid: typeof data.uid === 'string' ? data.uid : '',
    v: typeof data.v === 'string' ? data.v : undefined,
    p: typeof data.p === 'string' ? data.p : undefined,
    ut: typeof data.ut === 'string' ? data.ut : undefined,
  };
  const events = Array.isArray(data.events) ? (data.events as RawEvent[]) : [];
  if (!header.uid || events.length === 0) {
    await db.doc(`telemetryBatches/${batchId}`).delete();
    return;
  }
  const pricing = await loadPricing(db);
  const dayKeys = [...new Set(events.filter((e) => typeof e?.ts === 'number').map((e) => israelDay(e.ts)))];
  const summaryRef = db.doc(`analyticsUsers/${header.uid}`);
  await db.runTransaction(async (tx) => {
    const refs = dayKeys.map((d) => db.doc(`analyticsUserDays/${d}_${header.uid}`));
    const snaps = refs.length ? await tx.getAll(...refs) : [];
    const summarySnap = await tx.get(summaryRef);
    const versionRef = header.v ? db.doc(`analyticsVersions/${header.v.replace(/\//g, '_')}`) : undefined;
    const versionSnap = versionRef ? await tx.get(versionRef) : undefined;
    const existing: Record<string, UserDay | undefined> = {};
    snaps.forEach((s, i) => (existing[dayKeys[i]] = s.exists ? (s.data() as UserDay) : undefined));
    const updated = applyBatch(batchId, header, events, existing, pricing);
    const days = Object.values(updated);
    if (days.length === 0) return;
    const summary = updateSummary(summarySnap.exists ? (summarySnap.data() as UserSummary) : undefined, header.uid, days, header);
    for (const d of days) {
      addDeltas(summary, existing[d.day], d);
      tx.set(db.doc(`analyticsUserDays/${d.day}_${header.uid}`), d);
    }
    tx.set(summaryRef, summary);
    if (versionRef && !versionSnap?.exists) {
      tx.set(versionRef, { version: header.v, firstDay: days.map((d) => d.day).sort()[0], platform: header.p ?? '' });
    }
  });
  await db.doc(`telemetryBatches/${batchId}`).delete();
}

async function readDays(db: Firestore, from: string, to: string): Promise<UserDay[]> {
  const snap = await db.collection('analyticsUserDays').where('day', '>=', from).where('day', '<=', to).get();
  return snap.docs.map((d) => d.data() as UserDay);
}

async function accountsAndSummaries(db: Firestore): Promise<{ accounts: Account[]; summaries: UserSummary[]; internal: Set<string> }> {
  const admins = await db.collection('supportAdmins').get();
  const adminEmails = new Set<string>([ROOT_ADMIN, ...admins.docs.map((d) => d.id.toLowerCase())]);
  const { users, internal } = await listAccounts(adminEmails);
  const accounts: Account[] = users.map((u) => ({
    uid: u.uid,
    email: (u.email ?? '').toLowerCase(),
    created: Date.parse(u.metadata.creationTime) || 0,
    lastSignIn: Date.parse(u.metadata.lastSignInTime) || undefined,
  }));
  const summaries = (await db.collection('analyticsUsers').get()).docs
    .map((d) => d.data() as UserSummary)
    .filter((s) => !internal.has(s.uid));
  return { accounts, summaries, internal };
}

export interface DashboardParams {
  from: string;
  to: string;
  segment?: Segment;
  /** "Before/after" a release: the version to compare around. */
  release?: string;
  force?: boolean;
}

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

export async function dashboard(db: Firestore, params: DashboardParams): Promise<Record<string, unknown>> {
  const today = israelDay(Date.now());
  let { from, to } = params;
  if (!DAY_RE.test(from) || !DAY_RE.test(to) || from > to) throw new Error('bad-range');
  if (to > today) to = today;
  if (daysBetween(from, to) > 366) from = addDays(to, -366);
  const segment = params.segment ?? {};
  const cacheId = JSON.stringify({ from, to, segment, release: params.release ?? '' }).replace(/[^a-zA-Z0-9]/g, '_').slice(0, 400);
  const cacheRef = db.doc(`analyticsCache/${cacheId}`);
  if (!params.force) {
    const cached = await cacheRef.get();
    if (cached.exists && Date.now() - (cached.get('at') as number) < 20 * 60 * 1000) {
      return JSON.parse(cached.get('json') as string) as Record<string, unknown>;
    }
  }
  const { accounts, summaries, internal } = await accountsAndSummaries(db);
  const pricing = await loadPricing(db);
  const len = daysBetween(from, to) + 1;
  const prevFrom = addDays(from, -len);
  const all = (await readDays(db, prevFrom, to)).filter((d) => !internal.has(d.uid));
  const result: Record<string, unknown> = summarize({
    from,
    to,
    today,
    days: all.filter((d) => d.day >= from),
    prevDays: all.filter((d) => d.day < from),
    accounts,
    summaries,
    segment,
    pricing,
  });
  if (params.release) {
    const v = await db.doc(`analyticsVersions/${params.release.replace(/\//g, '_')}`).get();
    const first = v.get('firstDay') as string | undefined;
    if (first) {
      const beforeFrom = addDays(first, -7);
      const afterTo = addDays(first, 6) > today ? today : addDays(first, 6);
      const around = (await readDays(db, beforeFrom, afterTo)).filter((d) => !internal.has(d.uid));
      const side = (a: string, b: string) => {
        const s = summarize({ from: a, to: b, today, days: around.filter((d) => d.day >= a && d.day <= b), prevDays: [], accounts, summaries, segment, pricing });
        const failed = s.features.reduce((t, f) => t + f.failed, 0);
        const done = s.features.reduce((t, f) => t + f.completed, 0);
        const start = s.performance.find((p) => p.metric === 'app~start');
        return {
          from: a,
          to: b,
          activeUsers: s.overview.activeUsers,
          dau: s.overview.dau,
          sessions: s.movement.sessions,
          avgSessionMin: s.movement.avgSessionMin,
          ideas: s.overview.ideas,
          errors: s.failedRequests,
          failRate: done + failed > 0 ? Math.round((failed / (done + failed)) * 1000) / 10 : 0,
          avgStartMs: start?.avgMs ?? null,
          retentionD1: s.movement.retention.d1,
        };
      };
      result.release = {
        version: params.release,
        firstDay: first,
        before: side(beforeFrom, addDays(first, -1)),
        after: side(first, afterTo),
      };
    }
  }
  result.knownVersions = (await db.collection('analyticsVersions').get()).docs
    .map((d) => ({ version: d.get('version') as string, firstDay: d.get('firstDay') as string }))
    .sort((a, b) => b.firstDay.localeCompare(a.firstDay));
  result.computedAt = Date.now();
  await cacheRef.set({ at: Date.now(), json: JSON.stringify(result) });
  return result;
}

export async function userDetail(db: Firestore, uid: string, from: string, to: string): Promise<Record<string, unknown>> {
  if (!DAY_RE.test(from) || !DAY_RE.test(to)) throw new Error('bad-range');
  const pricing = await loadPricing(db);
  const ils = pricingAt(pricing, Date.now()).usdToIls;
  const [summary, health, days] = await Promise.all([
    db.doc(`analyticsUsers/${uid}`).get(),
    db.doc(`accountHealth/${uid}`).get(),
    db.collection('analyticsUserDays').where('uid', '==', uid).where('day', '>=', from).where('day', '<=', to).get(),
  ]);
  let auth: { email?: string; created?: string; lastSignIn?: string; providers?: string[] } = {};
  try {
    const u = await getAuth().getUser(uid);
    auth = {
      email: u.email,
      created: u.metadata.creationTime,
      lastSignIn: u.metadata.lastSignInTime,
      providers: u.providerData.map((p) => p.providerId),
    };
  } catch {
    // A deleted account: what the analytics hold.
  }
  const userDays = days.docs.map((d) => d.data() as UserDay).sort((a, b) => a.day.localeCompare(b.day));
  const features: Record<string, number> = {};
  let sessions = 0;
  let sessionMs = 0;
  let aiCalls = 0;
  let aiUsd = 0;
  let infraUsd = 0;
  let chats = 0;
  let uploads = 0;
  for (const d of userDays) {
    sessions += d.sess.n;
    sessionMs += d.sess.ms;
    infraUsd += d.m.usd;
    uploads += d.m.upN;
    for (const [f, c] of Object.entries(d.f)) features[f] = (features[f] ?? 0) + (c.o ?? 0) + (c.c ?? 0) + (c.x ?? 0);
    for (const a of Object.values(d.ai)) {
      aiCalls += a.n;
      aiUsd += a.usd;
    }
    chats += (d.fa['chats~send']?.c ?? 0);
  }
  const last = [...userDays].reverse().find((d) => d.st);
  const len = daysBetween(from, to) + 1;
  const storageBytes = last?.st ? last.st.photosB + last.st.voiceB : 0;
  const storageUsd = (storageBytes / 1e9) * pricingAt(pricing, Date.now()).storageGbMonth * (len / 30);
  const s = summary.data() as UserSummary | undefined;
  const devices = (health.get('devices') ?? {}) as Record<string, Record<string, unknown>>;
  const counts = Object.values(devices)
    .map((d) => (d.counts ?? {}) as Record<string, number>)
    .sort((a, b) => (b.people ?? 0) - (a.people ?? 0))[0] ?? {};
  return {
    uid,
    email: auth.email ?? health.get('email') ?? '',
    signedUp: auth.created ?? null,
    lastSignIn: auth.lastSignIn ?? null,
    providers: auth.providers ?? [],
    firstActive: s?.firstDay ?? null,
    lastActive: s?.lastDay ?? null,
    userType: s?.ut ?? null,
    platform: s?.plat ?? null,
    version: s?.ver ?? null,
    activeDays: userDays.length,
    sessions,
    avgSessionMin: sessions > 0 ? Math.round((sessionMs / sessions / 60000) * 10) / 10 : 0,
    features: Object.entries(features).sort((a, b) => b[1] - a[1]).map(([id, uses]) => ({ id, uses })),
    friends: counts.people ?? null,
    ideas: counts.matches ?? null,
    chatMessages: chats,
    aiCalls,
    uploads,
    photos: last?.st?.photos ?? null,
    voice: last?.st?.voice ?? null,
    storageBytes,
    aiIls: aiUsd * ils,
    infraIls: (infraUsd + storageUsd) * ils,
    totalIls: (aiUsd + infraUsd + storageUsd) * ils,
    cumulativeIls: s ? (s.aiUsd + s.infraUsd) * ils : null,
    estimated: true,
    days: userDays.map((d) => ({
      day: d.day,
      events: d.ev,
      sessions: d.sess.n,
      aiCalls: Object.values(d.ai).reduce((t, a) => t + a.n, 0),
      ils: (Object.values(d.ai).reduce((t, a) => t + a.usd, 0) + d.m.usd) * ils,
    })),
  };
}

export async function checkThresholds(db: Firestore): Promise<number> {
  const t = (await db.doc('adminConfig/thresholds').get()).data() as Partial<Thresholds> | undefined;
  if (!t) return 0;
  const thresholds: Thresholds = {
    aiDailyIls: Number(t.aiDailyIls) || 0,
    userDailyIls: Number(t.userDailyIls) || 0,
    featureSpikeFactor: Number(t.featureSpikeFactor) || 0,
    errorRatePercent: Number(t.errorRatePercent) || 0,
  };
  const today = israelDay(Date.now());
  const all = await readDays(db, addDays(today, -7), today);
  const pricing = await loadPricing(db);
  const found = thresholdAlerts(
    all.filter((d) => d.day === today),
    all.filter((d) => d.day < today),
    thresholds,
    pricingAt(pricing, Date.now()).usdToIls,
  );
  const fresh = [];
  for (const a of found) {
    const ref = db.doc(`analyticsAlerts/${today}_${a.code.replace(/[^a-zA-Z0-9_]/g, '_')}`);
    if ((await ref.get()).exists) continue;
    await ref.set({ ...a, day: today, at: FieldValue.serverTimestamp() });
    fresh.push({ code: a.code, severity: 'high' as const, title: a.title, detail: a.body });
  }
  await announceAlerts(db, fresh);
  return fresh.length;
}

/** An account deleted: its monitoring metadata goes with it. */
export async function deleteAnalyticsOf(uid: string): Promise<void> {
  const { getFirestore } = await import('firebase-admin/firestore');
  const db = getFirestore();
  const days = await db.collection('analyticsUserDays').where('uid', '==', uid).get();
  for (const d of days.docs) await d.ref.delete();
  await db.doc(`analyticsUsers/${uid}`).delete();
  const batches = await db.collection('telemetryBatches').where('uid', '==', uid).get();
  for (const b of batches.docs) await b.ref.delete();
}
