/**
 * The monitoring pipeline's arithmetic — pure, so it is tested without
 * Firestore (`analytics.test.ts`). The Firestore glue is `analytics_store.ts`.
 *
 * **Flow.** The app keeps every usage event in a local queue (`Telemetry`)
 * and writes them in batches to `telemetryBatches/{batchId}`. Each batch is
 * folded ([applyBatch]) into one document per account per Israel day,
 * `analyticsUserDays/{day}_{uid}`, and into the account's running summary
 * `analyticsUsers/{uid}`; then deleted. The dashboard ([summarize]) reads
 * those documents for any period and segment.
 *
 * **Taxonomy** (one place, see `lib/services/telemetry.dart`): an event is
 * `open` (feature_opened), `start` / `done` / `fail` (action_started /
 * _completed / _failed) with a `feature` id and an `action` code, plus
 * `sess` (session start/end), `time` (a performance measure), `err` (an
 * uncaught error), `ai` (one AI call's metadata) and `meter` (counters of
 * database operations, file transfer and backend calls). A new feature is a
 * new `feature` id — nothing here or on the dashboard has to change.
 *
 * **Privacy by design:** only codes, numbers and times. Never a name, phone,
 * card text, note, chat message, recording or prompt.
 *
 * **Costs.** AI calls are priced at fold time with the pricing version in
 * force at the call's own timestamp, and the result is stored with the
 * version's id — a later price change never rewrites a past month. Token
 * counts are the provider's own (`usageMetadata`); the price table is ours,
 * because Vertex AI returns no per-call cost. Everything that is not AI is an
 * **estimate** from client-side counters and is labelled so.
 */

export type EventType = 'open' | 'start' | 'done' | 'fail' | 'sess' | 'time' | 'err' | 'ai' | 'meter';

export interface RawEvent {
  id: string;
  t: EventType;
  f?: string;
  a?: string;
  ts: number;
  s?: string;
  ms?: number;
  e?: string;
  x?: Record<string, unknown>;
}

export interface BatchHeader {
  uid: string;
  /** App version, e.g. `1.0.20`. */
  v?: string;
  /** `android` | `ios`. */
  p?: string;
  /** `single` | `matchmaker` | `both`. */
  ut?: string;
}

export interface Counts {
  o?: number;
  s?: number;
  c?: number;
  x?: number;
  ms?: number;
  mn?: number;
}

export interface AiCounts {
  n: number;
  ok: number;
  x: number;
  tries: number;
  lat: number;
  in: number;
  out: number;
  usd: number;
  pv: Record<string, number>;
  models: Record<string, number>;
}

export interface Meter {
  r: number;
  w: number;
  d: number;
  q: number;
  upB: number;
  dnB: number;
  upN: number;
  dnN: number;
  fn: number;
  usd: number;
}

export interface UserDay {
  uid: string;
  day: string;
  plat: Record<string, number>;
  ver: Record<string, number>;
  ut: string;
  ev: number;
  sess: { n: number; ms: number };
  f: Record<string, Counts>;
  fa: Record<string, Counts>;
  ai: Record<string, AiCounts>;
  err: Record<string, { n: number; last: number; ms: number }>;
  perf: Record<string, { n: number; sum: number; max: number; slow: number }>;
  m: Meter;
  st?: { photosB: number; voiceB: number; photos: number; voice: number; at: number };
  batches: string[];
}

export interface PricingVersion {
  id: string;
  /** In force from this moment (ms). */
  from: number;
  usdToIls: number;
  /** USD per million tokens, default for every model. */
  aiIn: number;
  aiOut: number;
  /** Per-model overrides. */
  aiModels?: Record<string, { in: number; out: number }>;
  readsPer100k: number;
  writesPer100k: number;
  deletesPer100k: number;
  storageGbMonth: number;
  egressGb: number;
  fnPerMillion: number;
}

export const NO_PRICING: PricingVersion = {
  id: 'none',
  from: 0,
  usdToIls: 3.7,
  aiIn: 0,
  aiOut: 0,
  readsPer100k: 0,
  writesPer100k: 0,
  deletesPer100k: 0,
  storageGbMonth: 0,
  egressGb: 0,
  fnPerMillion: 0,
};

const DAY_MS = 24 * 60 * 60 * 1000;
/** A screen slower than this to draw counts as slow. */
export const SLOW_MS = 2000;
/** Batch ids kept on a day document, for idempotent retries. */
const KEPT_BATCHES = 60;

export function israelDay(ms: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Jerusalem',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(ms));
}

/** `YYYY-MM-DD` + [n] days. */
export function addDays(day: string, n: number): string {
  const t = Date.parse(`${day}T12:00:00Z`) + n * DAY_MS;
  return new Date(t).toISOString().slice(0, 10);
}

export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T12:00:00Z`) - Date.parse(`${from}T12:00:00Z`)) / DAY_MS);
}

/** A code safe as a map key: lowercase ascii, digits, `_` `:` `/` `-` `.`. */
export function code(raw: unknown, max = 60): string {
  if (typeof raw !== 'string') return '';
  return raw.toLowerCase().replace(/[^a-z0-9_:/.-]/g, '_').slice(0, max);
}

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : 0;
}

export function emptyDay(uid: string, day: string): UserDay {
  return {
    uid,
    day,
    plat: {},
    ver: {},
    ut: 'unknown',
    ev: 0,
    sess: { n: 0, ms: 0 },
    f: {},
    fa: {},
    ai: {},
    err: {},
    perf: {},
    m: { r: 0, w: 0, d: 0, q: 0, upB: 0, dnB: 0, upN: 0, dnN: 0, fn: 0, usd: 0 },
    batches: [],
  };
}

/** The pricing version in force at [ts]: the latest whose `from` ≤ ts. */
export function pricingAt(versions: PricingVersion[], ts: number): PricingVersion {
  let best: PricingVersion | undefined;
  for (const v of versions) {
    if (v.from <= ts && (!best || v.from > best.from)) best = v;
  }
  return best ?? NO_PRICING;
}

export function aiCostUsd(p: PricingVersion, model: string, input: number, output: number): number {
  const rate = p.aiModels?.[model] ?? { in: p.aiIn, out: p.aiOut };
  return (input / 1e6) * rate.in + (output / 1e6) * rate.out;
}

export function meterCostUsd(p: PricingVersion, m: Partial<Meter>): number {
  return (
    (num(m.r) / 1e5) * p.readsPer100k +
    (num(m.w) / 1e5) * p.writesPer100k +
    (num(m.d) / 1e5) * p.deletesPer100k +
    (num(m.dnB) / 1e9) * p.egressGb +
    (num(m.fn) / 1e6) * p.fnPerMillion
  );
}

function bump(map: Record<string, number>, key: string, by = 1): void {
  if (!key) return;
  map[key] = (map[key] ?? 0) + by;
}

/**
 * Folds one batch into the account's day documents (by Israel day of each
 * event). Returns the days touched, or none when every one of them already
 * holds this batch id — a retried batch is counted once.
 */
export function applyBatch(
  batchId: string,
  header: BatchHeader,
  events: RawEvent[],
  existing: Record<string, UserDay | undefined>,
  pricing: PricingVersion[],
): Record<string, UserDay> {
  const out: Record<string, UserDay> = {};
  const seen = new Set<string>();
  for (const ev of events) {
    if (!ev || typeof ev.ts !== 'number' || !ev.t) continue;
    if (ev.id && seen.has(ev.id)) continue;
    if (ev.id) seen.add(ev.id);
    const day = israelDay(ev.ts);
    let d = out[day];
    if (!d) {
      const prior = existing[day];
      if (prior?.batches?.includes(batchId)) continue;
      d = prior ? (JSON.parse(JSON.stringify(prior)) as UserDay) : emptyDay(header.uid, day);
      out[day] = d;
    }
    fold(d, ev, header, pricing);
  }
  for (const d of Object.values(out)) {
    if (header.ut) d.ut = code(header.ut, 12);
    d.batches = [...d.batches.filter((b) => b !== batchId), batchId].slice(-KEPT_BATCHES);
  }
  return out;
}

function fold(d: UserDay, ev: RawEvent, h: BatchHeader, pricing: PricingVersion[]): void {
  const feature = code(ev.f, 40) || 'app';
  const action = code(ev.a, 40);
  const x = ev.x ?? {};
  d.ev += 1;
  bump(d.plat, code(h.p, 12) || 'unknown');
  bump(d.ver, (h.v ?? 'unknown').replace(/[^0-9a-z.+-]/gi, '').slice(0, 20) || 'unknown');
  const counts = (d.f[feature] ??= {});
  const ak = action ? `${feature}~${action}` : '';
  const acounts = ak ? (d.fa[ak] ??= {}) : undefined;
  switch (ev.t) {
    case 'open':
      counts.o = (counts.o ?? 0) + 1;
      break;
    case 'start':
      counts.s = (counts.s ?? 0) + 1;
      if (acounts) acounts.s = (acounts.s ?? 0) + 1;
      break;
    case 'done':
    case 'fail': {
      const k = ev.t === 'done' ? 'c' : 'x';
      counts[k] = (counts[k] ?? 0) + 1;
      if (acounts) acounts[k] = (acounts[k] ?? 0) + 1;
      if (num(ev.ms) > 0) {
        counts.ms = (counts.ms ?? 0) + num(ev.ms);
        counts.mn = (counts.mn ?? 0) + 1;
      }
      if (ev.t === 'fail') {
        const key = `${feature}~${code(ev.e, 40) || 'unknown'}~${h.v ?? ''}~${code(h.p, 12)}`;
        const e = (d.err[key] ??= { n: 0, last: 0, ms: 0 });
        e.n += 1;
        e.last = Math.max(e.last, ev.ts);
        e.ms += num(ev.ms);
      }
      break;
    }
    case 'err': {
      const key = `${feature}~${code(ev.e, 40) || 'unknown'}~${h.v ?? ''}~${code(h.p, 12)}`;
      const e = (d.err[key] ??= { n: 0, last: 0, ms: 0 });
      e.n += 1;
      e.last = Math.max(e.last, ev.ts);
      break;
    }
    case 'sess':
      if (action === 'start') d.sess.n += 1;
      if (action === 'end') d.sess.ms += Math.min(num(ev.ms), 6 * 60 * 60 * 1000);
      break;
    case 'time': {
      const metric = action ? `${feature}~${action}` : feature;
      const p = (d.perf[metric] ??= { n: 0, sum: 0, max: 0, slow: 0 });
      const ms = Math.min(num(ev.ms), 5 * 60 * 1000);
      p.n += 1;
      p.sum += ms;
      p.max = Math.max(p.max, ms);
      if (ms > SLOW_MS) p.slow += 1;
      break;
    }
    case 'ai': {
      const model = code(x.model, 40) || 'unknown';
      const input = num(x.in);
      const output = num(x.out);
      const ok = x.ok !== false;
      const version = pricingAt(pricing, ev.ts);
      const a = (d.ai[feature] ??= {
        n: 0,
        ok: 0,
        x: 0,
        tries: 0,
        lat: 0,
        in: 0,
        out: 0,
        usd: 0,
        pv: {},
        models: {},
      });
      a.n += 1;
      if (ok) a.ok += 1;
      else a.x += 1;
      a.tries += Math.max(0, num(x.tries) - 1);
      a.lat += num(ev.ms);
      a.in += input;
      a.out += output;
      a.usd += aiCostUsd(version, model, input, output);
      bump(a.pv, version.id);
      bump(a.models, model);
      const p = (d.perf['ai~latency'] ??= { n: 0, sum: 0, max: 0, slow: 0 });
      p.n += 1;
      p.sum += num(ev.ms);
      p.max = Math.max(p.max, num(ev.ms));
      if (!ok) {
        const key = `ai~${code(ev.e, 40) || 'failed'}~${h.v ?? ''}~${code(h.p, 12)}`;
        const e = (d.err[key] ??= { n: 0, last: 0, ms: 0 });
        e.n += 1;
        e.last = Math.max(e.last, ev.ts);
        e.ms += num(ev.ms);
      }
      break;
    }
    case 'meter': {
      const m: Partial<Meter> = {
        r: num(x.r),
        w: num(x.w),
        d: num(x.d),
        q: num(x.q),
        upB: num(x.upB),
        dnB: num(x.dnB),
        upN: num(x.upN),
        dnN: num(x.dnN),
        fn: num(x.fn),
      };
      for (const k of ['r', 'w', 'd', 'q', 'upB', 'dnB', 'upN', 'dnN', 'fn'] as const) {
        d.m[k] += m[k] ?? 0;
      }
      d.m.usd += meterCostUsd(pricingAt(pricing, ev.ts), m);
      if (x.photosB !== undefined || x.voiceB !== undefined) {
        d.st = {
          photosB: num(x.photosB),
          voiceB: num(x.voiceB),
          photos: num(x.photos),
          voice: num(x.voice),
          at: ev.ts,
        };
      }
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// The account's running summary.

export interface UserSummary {
  uid: string;
  firstDay: string;
  lastDay: string;
  /** Active days, newest last, at most 400. */
  days: string[];
  ut: string;
  plat: string;
  ver: string;
  aiUsd: number;
  infraUsd: number;
  aiCalls: number;
  events: number;
}

export function updateSummary(prior: UserSummary | undefined, uid: string, days: UserDay[], header: BatchHeader): UserSummary {
  const s: UserSummary = prior
    ? { ...prior, days: [...prior.days] }
    : { uid, firstDay: '', lastDay: '', days: [], ut: 'unknown', plat: '', ver: '', aiUsd: 0, infraUsd: 0, aiCalls: 0, events: 0 };
  for (const d of days) {
    if (!s.days.includes(d.day)) s.days.push(d.day);
  }
  s.days.sort();
  s.days = s.days.slice(-400);
  s.firstDay = s.firstDay && s.firstDay < s.days[0] ? s.firstDay : s.days[0] ?? s.firstDay;
  s.lastDay = s.days[s.days.length - 1] ?? s.lastDay;
  if (header.ut) s.ut = code(header.ut, 12);
  if (header.p) s.plat = code(header.p, 12);
  if (header.v) s.ver = header.v;
  return s;
}

/** Adds the difference a fold made to the running totals. */
export function addDeltas(s: UserSummary, before: UserDay | undefined, after: UserDay): void {
  const ai = (d?: UserDay) => Object.values(d?.ai ?? {}).reduce((t, a) => t + a.usd, 0);
  const calls = (d?: UserDay) => Object.values(d?.ai ?? {}).reduce((t, a) => t + a.n, 0);
  s.aiUsd += ai(after) - ai(before);
  s.aiCalls += calls(after) - calls(before);
  s.infraUsd += after.m.usd - (before?.m.usd ?? 0);
  s.events += after.ev - (before?.ev ?? 0);
}

// ---------------------------------------------------------------------------
// The dashboard.

export interface Account {
  uid: string;
  email: string;
  created: number;
  lastSignIn?: number;
}

export interface Segment {
  platform?: string;
  version?: string;
  userType?: string;
  /** `new` = signed up within 30 days of the day; `veteran` = earlier. */
  cohort?: 'new' | 'veteran';
}

export interface FunnelStep {
  label: string;
  feature: string;
  action?: string;
  kind: 'o' | 's' | 'c';
}

export interface FunnelDef {
  id: string;
  title: string;
  steps: FunnelStep[];
}

/** The central flows, where users are expected to drop off. */
export const FUNNELS: FunnelDef[] = [
  {
    id: 'add_friend',
    title: 'הוספת חבר מאנשי הקשר',
    steps: [
      { label: 'פתח הוספת חבר', feature: 'add_contacts', kind: 'o' },
      { label: 'בחר איש קשר', feature: 'add_contacts', action: 'pick', kind: 's' },
      { label: 'החבר נוסף', feature: 'add_contacts', action: 'save', kind: 'c' },
    ],
  },
  {
    id: 'ai',
    title: 'ייבוא באמצעות AI',
    steps: [
      { label: 'פתח AI', feature: 'ai', kind: 'o' },
      { label: 'העלה קובץ/כרטיס', feature: 'ai', action: 'upload', kind: 's' },
      { label: 'AI עיבד', feature: 'ai', action: 'parse', kind: 'c' },
      { label: 'אישר ושמר', feature: 'ai', action: 'save', kind: 'c' },
    ],
  },
  {
    id: 'matches',
    title: 'מהתאמות לרעיון',
    steps: [
      { label: 'פתח התאמות', feature: 'matches', kind: 'o' },
      { label: 'פתח התאמה', feature: 'matches', action: 'preview', kind: 's' },
      { label: 'נפתח רעיון', feature: 'matches', action: 'idea', kind: 'c' },
    ],
  },
  {
    id: 'access',
    title: 'בקשת גישה לכרטיס',
    steps: [
      { label: 'ביקש גישה', feature: 'access', action: 'request', kind: 'c' },
      { label: 'הגישה אושרה', feature: 'access', action: 'approved', kind: 'c' },
    ],
  },
  {
    id: 'shared_idea',
    title: 'רעיון בין שדכנים',
    steps: [
      // The approval happens on the other matchmaker's phone; on the
      // proposer's side it shows as the idea arriving.
      { label: 'נשלחה הצעה', feature: 'shared_idea', action: 'propose', kind: 'c' },
      { label: 'אושרה והפכה לרעיון', feature: 'shared_idea', action: 'open', kind: 'c' },
    ],
  },
];

/** Hebrew names for the feature ids; an unknown id is shown as is. */
export const FEATURE_NAMES: Record<string, string> = {
  home: 'בית',
  people: 'המאגר',
  ideas: 'רעיונות',
  matches: 'התאמות',
  chats: 'צ\'אטים',
  profile: 'פרופיל',
  personal_card: 'כרטיס אישי',
  my_matchmakers: 'השדכנים שלי',
  partner_matchmakers: 'שדכנים שותפים',
  database_sharing: 'שיתוף מאגר',
  add_friend: 'הוספת חבר',
  add_contacts: 'הוספה מאנשי קשר',
  add_manual: 'הוספה ידנית',
  ai: 'AI',
  search: 'חיפוש',
  filters: 'פילטרים',
  notifications: 'התראות',
  whatsapp_share: 'שיתוף ל־WhatsApp',
  voice_notes: 'הקלטות',
  photo_upload: 'העלאת תמונות',
  card_open: 'פתיחת כרטיס',
  access: 'בקשת/אישור גישה',
  idea_open: 'פתיחת רעיון',
  idea_status: 'שינוי סטטוס רעיון',
  shared_idea: 'רעיון בין שדכנים',
  settings: 'הגדרות',
  activity: 'פעילות וקהילה',
  board: 'הלוח שלי',
  tags: 'תגיות',
  notes: 'הערות',
  app: 'האפליקציה',
};

export interface SummarizeInput {
  from: string;
  to: string;
  today: string;
  days: UserDay[];
  prevDays: UserDay[];
  accounts: Account[];
  summaries: UserSummary[];
  segment?: Segment;
  pricing: PricingVersion[];
}

function pct(part: number, whole: number): number {
  return whole > 0 ? Math.round((part / whole) * 1000) / 10 : 0;
}

export function change(now: number, before: number): number | null {
  if (before <= 0) return now > 0 ? null : 0;
  return Math.round(((now - before) / before) * 1000) / 10;
}

function matches(d: UserDay, seg: Segment | undefined, created: Map<string, number>): boolean {
  if (!seg) return true;
  if (seg.platform && !(d.plat[seg.platform] > 0)) return false;
  if (seg.version && !(d.ver[seg.version] > 0)) return false;
  if (seg.userType && d.ut !== seg.userType && !(d.ut === 'both' && seg.userType !== 'both')) return false;
  if (seg.cohort) {
    const c = created.get(d.uid);
    const dayMs = Date.parse(`${d.day}T12:00:00Z`);
    const isNew = c !== undefined && dayMs - c < 30 * DAY_MS;
    if ((seg.cohort === 'new') !== isNew) return false;
  }
  return true;
}

interface PeriodTotals {
  users: Set<string>;
  features: Map<string, { users: Set<string>; o: number; s: number; c: number; x: number; ms: number; mn: number }>;
  actions: Map<string, { users: Set<string>; s: number; c: number; x: number }>;
  aiUsd: number;
  infraUsd: number;
  aiCalls: number;
  ideas: number;
  couples: number;
  sessions: number;
  sessionMs: number;
}

function totals(days: UserDay[]): PeriodTotals {
  const t: PeriodTotals = {
    users: new Set(),
    features: new Map(),
    actions: new Map(),
    aiUsd: 0,
    infraUsd: 0,
    aiCalls: 0,
    ideas: 0,
    couples: 0,
    sessions: 0,
    sessionMs: 0,
  };
  for (const d of days) {
    t.users.add(d.uid);
    t.sessions += d.sess.n;
    t.sessionMs += d.sess.ms;
    t.infraUsd += d.m.usd;
    for (const [f, c] of Object.entries(d.f)) {
      const r = t.features.get(f) ?? { users: new Set<string>(), o: 0, s: 0, c: 0, x: 0, ms: 0, mn: 0 };
      r.users.add(d.uid);
      r.o += c.o ?? 0;
      r.s += c.s ?? 0;
      r.c += c.c ?? 0;
      r.x += c.x ?? 0;
      r.ms += c.ms ?? 0;
      r.mn += c.mn ?? 0;
      t.features.set(f, r);
    }
    for (const [k, c] of Object.entries(d.fa)) {
      const r = t.actions.get(k) ?? { users: new Set<string>(), s: 0, c: 0, x: 0 };
      r.users.add(d.uid);
      r.s += c.s ?? 0;
      r.c += c.c ?? 0;
      r.x += c.x ?? 0;
      t.actions.set(k, r);
    }
    for (const a of Object.values(d.ai)) {
      t.aiUsd += a.usd;
      t.aiCalls += a.n;
    }
    t.ideas += d.fa['idea_open~create']?.c ?? 0;
    t.couples += d.fa['idea_status~dating']?.c ?? 0;
  }
  return t;
}

/** Storage held, priced for the period (estimated): the latest footprint per user. */
function storageUsd(days: UserDay[], pricing: PricingVersion[], periodDays: number, to: string): Map<string, number> {
  const latest = new Map<string, NonNullable<UserDay['st']>>();
  for (const d of days) {
    if (!d.st) continue;
    const prior = latest.get(d.uid);
    if (!prior || d.st.at > prior.at) latest.set(d.uid, d.st);
  }
  const p = pricingAt(pricing, Date.parse(`${to}T23:00:00Z`));
  const out = new Map<string, number>();
  for (const [uid, st] of latest) {
    out.set(uid, ((st.photosB + st.voiceB) / 1e9) * p.storageGbMonth * (periodDays / 30));
  }
  return out;
}

export function summarize(input: SummarizeInput) {
  const { from, to, today, accounts, summaries, pricing, segment } = input;
  const created = new Map(accounts.map((a) => [a.uid, a.created] as const));
  const emailOf = new Map(accounts.map((a) => [a.uid, a.email] as const));
  const days = input.days.filter((d) => d.day >= from && d.day <= to && matches(d, segment, created));
  const prev = input.prevDays.filter((d) => matches(d, segment, created));
  const periodDays = daysBetween(from, to) + 1;
  const now = totals(days);
  const before = totals(prev);
  const latestPricing = pricingAt(pricing, Date.now());
  const ils = latestPricing.usdToIls;
  const storage = storageUsd(days, pricing, periodDays, to);
  const storageTotal = [...storage.values()].reduce((a, b) => a + b, 0);
  const prevStorage = [...storageUsd(prev, pricing, periodDays, from).values()].reduce((a, b) => a + b, 0);
  const startMs = Date.parse(`${from}T00:00:00Z`) - 3 * 60 * 60 * 1000;
  const endMs = Date.parse(`${to}T00:00:00Z`) + DAY_MS - 2 * 60 * 60 * 1000;
  const newUsers = accounts.filter((a) => a.created >= startMs && a.created < endMs);

  // Who was active when: from the summaries (all of an account's days).
  const activeOn = (day: string) => summaries.filter((s) => s.days.includes(day)).length;
  const activeBetween = (a: string, b: string) =>
    summaries.filter((s) => s.days.some((d) => d >= a && d <= b)).length;

  // ---- overview
  const usersByType = { single: 0, matchmaker: 0, both: 0 };
  const typeOf = new Map<string, string>();
  for (const d of days) typeOf.set(d.uid, d.ut);
  for (const ut of typeOf.values()) {
    if (ut === 'single' || ut === 'matchmaker' || ut === 'both') usersByType[ut] += 1;
  }
  const dauSeries: { day: string; users: number; signups: number }[] = [];
  for (let i = 0; i < periodDays; i++) {
    const day = addDays(from, i);
    const dayStart = Date.parse(`${day}T00:00:00Z`) - 3 * 60 * 60 * 1000;
    dauSeries.push({
      day,
      users: new Set(days.filter((d) => d.day === day).map((d) => d.uid)).size,
      signups: accounts.filter((a) => a.created >= dayStart && a.created < dayStart + DAY_MS).length,
    });
  }
  const totalUsd = now.aiUsd + now.infraUsd + storageTotal;
  const prevTotalUsd = before.aiUsd + before.infraUsd + prevStorage;

  // ---- returning, stopping, days per week
  let returned = 0;
  for (const s of summaries) {
    const inRange = s.days.filter((d) => d >= from && d <= to);
    if (inRange.length === 0) continue;
    const earlier = s.days.filter((d) => d < inRange[0]);
    const last = earlier[earlier.length - 1];
    if (last && daysBetween(last, inRange[0]) >= 14) returned += 1;
  }
  const prevFrom = addDays(from, -periodDays);
  let stopped = 0;
  for (const s of summaries) {
    const wasActive = s.days.some((d) => d >= prevFrom && d < from);
    const isActive = s.days.some((d) => d >= from && d <= to);
    if (wasActive && !isActive && daysBetween(s.lastDay, to) >= 14) stopped += 1;
  }
  const activeDaysPerUser = new Map<string, number>();
  for (const d of days) activeDaysPerUser.set(d.uid, (activeDaysPerUser.get(d.uid) ?? 0) + 1);
  const avgDaysPerWeek =
    activeDaysPerUser.size > 0
      ? Math.round(
          ([...activeDaysPerUser.values()].reduce((a, b) => a + b, 0) / activeDaysPerUser.size) *
            (7 / Math.max(7, periodDays)) *
            10,
        ) / 10
      : 0;

  // ---- retention, for accounts that signed up in the period
  const retention = { cohort: 0, d1: null as number | null, d7: null as number | null, d30: null as number | null };
  const byUid = new Map(summaries.map((s) => [s.uid, s] as const));
  const rate = (n: number) => {
    let eligible = 0;
    let kept = 0;
    for (const a of newUsers) {
      const day0 = israelDay(a.created);
      if (addDays(day0, n) > today) continue;
      eligible += 1;
      const s = byUid.get(a.uid);
      const lo = addDays(day0, n);
      const hi = addDays(day0, n === 1 ? 1 : n + 6);
      if (s?.days.some((d) => d >= lo && d <= hi)) kept += 1;
    }
    return eligible > 0 ? pct(kept, eligible) : null;
  };
  retention.cohort = newUsers.length;
  retention.d1 = rate(1);
  retention.d7 = rate(7);
  retention.d30 = rate(30);

  // ---- features
  const activeUsers = now.users.size;
  const features = [...new Set([...now.features.keys(), ...before.features.keys()])].map((id) => {
    const r = now.features.get(id);
    const p = before.features.get(id);
    const uses = (r?.o ?? 0) + (r?.c ?? 0) + (r?.x ?? 0);
    const prevUses = (p?.o ?? 0) + (p?.c ?? 0) + (p?.x ?? 0);
    const users = r?.users.size ?? 0;
    const attempts = (r?.c ?? 0) + (r?.x ?? 0);
    return {
      id,
      name: FEATURE_NAMES[id] ?? id,
      users,
      uses,
      opens: r?.o ?? 0,
      completed: r?.c ?? 0,
      failed: r?.x ?? 0,
      perUser: users > 0 ? Math.round((uses / users) * 10) / 10 : 0,
      share: pct(users, activeUsers),
      successRate: attempts > 0 ? pct(r?.c ?? 0, attempts) : null,
      avgMs: r && r.mn > 0 ? Math.round(r.ms / r.mn) : null,
      usersChange: change(users, p?.users.size ?? 0),
      usesChange: change(uses, prevUses),
    };
  });
  features.sort((a, b) => b.users - a.users || b.uses - a.uses);
  const actions = [...now.actions.entries()].map(([key, r]) => {
    const [feature, action] = key.split('~');
    const attempts = r.c + r.x;
    return {
      feature,
      action,
      users: r.users.size,
      started: r.s,
      completed: r.c,
      failed: r.x,
      successRate: attempts > 0 ? pct(r.c, attempts) : null,
    };
  });
  actions.sort((a, b) => b.users - a.users || b.completed - a.completed);

  // ---- funnels (unique users who reached each step and every step before it)
  const perUser = new Map<string, { f: Record<string, Counts>; fa: Record<string, Counts> }>();
  for (const d of days) {
    const u = perUser.get(d.uid) ?? { f: {}, fa: {} };
    for (const [k, c] of Object.entries(d.f)) {
      const t = (u.f[k] ??= {});
      for (const key of ['o', 's', 'c', 'x'] as const) t[key] = (t[key] ?? 0) + (c[key] ?? 0);
    }
    for (const [k, c] of Object.entries(d.fa)) {
      const t = (u.fa[k] ??= {});
      for (const key of ['s', 'c', 'x'] as const) t[key] = (t[key] ?? 0) + (c[key] ?? 0);
    }
    perUser.set(d.uid, u);
  }
  const funnels = FUNNELS.map((def) => {
    const reached = def.steps.map(() => 0);
    for (const u of perUser.values()) {
      for (let i = 0; i < def.steps.length; i++) {
        const st = def.steps[i];
        const c = st.action ? u.fa[`${st.feature}~${st.action}`] : u.f[st.feature];
        if (!c || !((c[st.kind] ?? 0) > 0)) break;
        reached[i] += 1;
      }
    }
    return {
      id: def.id,
      title: def.title,
      steps: def.steps.map((s, i) => ({
        label: s.label,
        users: reached[i],
        fromPrevious: i === 0 ? null : pct(reached[i], reached[i - 1]),
      })),
    };
  });

  // ---- AI
  const aiByFeature = new Map<string, { calls: number; users: Set<string>; ok: number; x: number; tries: number; lat: number; in: number; out: number; usd: number; models: Record<string, number> }>();
  const aiByUser = new Map<string, { calls: number; in: number; out: number; usd: number; features: Set<string> }>();
  const pricingVersions: Record<string, number> = {};
  for (const d of days) {
    for (const [f, a] of Object.entries(d.ai)) {
      const r = aiByFeature.get(f) ?? { calls: 0, users: new Set<string>(), ok: 0, x: 0, tries: 0, lat: 0, in: 0, out: 0, usd: 0, models: {} };
      r.calls += a.n;
      r.users.add(d.uid);
      r.ok += a.ok;
      r.x += a.x;
      r.tries += a.tries;
      r.lat += a.lat;
      r.in += a.in;
      r.out += a.out;
      r.usd += a.usd;
      for (const [m, n] of Object.entries(a.models)) bump(r.models, m, n);
      for (const [v, n] of Object.entries(a.pv)) bump(pricingVersions, v, n);
      aiByFeature.set(f, r);
      const u = aiByUser.get(d.uid) ?? { calls: 0, in: 0, out: 0, usd: 0, features: new Set<string>() };
      u.calls += a.n;
      u.in += a.in;
      u.out += a.out;
      u.usd += a.usd;
      u.features.add(f);
      aiByUser.set(d.uid, u);
    }
  }
  const aiUsersCount = aiByUser.size;
  const avgAiUsd = aiUsersCount > 0 ? now.aiUsd / aiUsersCount : 0;
  const allAi = [...aiByFeature.values()];
  const ai = {
    calls: now.aiCalls,
    users: aiUsersCount,
    ok: allAi.reduce((t, r) => t + r.ok, 0),
    failed: allAi.reduce((t, r) => t + r.x, 0),
    retries: allAi.reduce((t, r) => t + r.tries, 0),
    avgLatencyMs: now.aiCalls > 0 ? Math.round(allAi.reduce((t, r) => t + r.lat, 0) / now.aiCalls) : null,
    inputTokens: allAi.reduce((t, r) => t + r.in, 0),
    outputTokens: allAi.reduce((t, r) => t + r.out, 0),
    usd: now.aiUsd,
    ils: now.aiUsd * ils,
    prevIls: before.aiUsd * ils,
    pricingVersions,
    byFeature: [...aiByFeature.entries()]
      .map(([id, r]) => ({
        id,
        name: FEATURE_NAMES[id] ?? id,
        calls: r.calls,
        users: r.users.size,
        ok: r.ok,
        failed: r.x,
        retries: r.tries,
        avgLatencyMs: r.calls > 0 ? Math.round(r.lat / r.calls) : null,
        inputTokens: r.in,
        outputTokens: r.out,
        ils: r.usd * ils,
        models: r.models,
      }))
      .sort((a, b) => b.ils - a.ils),
    byUser: [...aiByUser.entries()]
      .map(([uid, r]) => ({
        uid,
        email: emailOf.get(uid) ?? '',
        calls: r.calls,
        tokens: r.in + r.out,
        ils: r.usd * ils,
        totalIls: (byUid.get(uid)?.aiUsd ?? r.usd) * ils,
        features: [...r.features],
        timesAverage: avgAiUsd > 0 ? Math.round((r.usd / avgAiUsd) * 10) / 10 : null,
      }))
      .sort((a, b) => b.ils - a.ils)
      .slice(0, 200),
  };

  // ---- users
  const userRows = new Map<string, {
    uid: string; email: string; ut: string; platform: string; version: string; created: number | null;
    lastDay: string; activeDays: number; sessions: number; sessionMs: number; events: number;
    aiCalls: number; aiIls: number; infraIls: number; totalIls: number; cumulativeIls: number;
    uploads: number; backend: number; reads: number; writes: number; storageBytes: number;
  }>();
  for (const d of days) {
    const r = userRows.get(d.uid) ?? {
      uid: d.uid,
      email: emailOf.get(d.uid) ?? '',
      ut: d.ut,
      platform: Object.keys(d.plat)[0] ?? '',
      version: '',
      created: created.get(d.uid) ?? null,
      lastDay: d.day,
      activeDays: 0,
      sessions: 0,
      sessionMs: 0,
      events: 0,
      aiCalls: 0,
      aiIls: 0,
      infraIls: 0,
      totalIls: 0,
      cumulativeIls: 0,
      uploads: 0,
      backend: 0,
      reads: 0,
      writes: 0,
      storageBytes: 0,
    };
    r.activeDays += 1;
    r.sessions += d.sess.n;
    r.sessionMs += d.sess.ms;
    r.events += d.ev;
    if (d.day >= r.lastDay) {
      r.lastDay = d.day;
      r.ut = d.ut;
      const v = Object.entries(d.ver).sort((a, b) => b[1] - a[1])[0];
      if (v) r.version = v[0];
    }
    for (const a of Object.values(d.ai)) {
      r.aiCalls += a.n;
      r.aiIls += a.usd * ils;
    }
    r.infraIls += d.m.usd * ils;
    r.uploads += d.m.upN;
    r.backend += d.m.fn + d.m.q;
    r.reads += d.m.r;
    r.writes += d.m.w;
    if (d.st) r.storageBytes = d.st.photosB + d.st.voiceB;
    userRows.set(d.uid, r);
  }
  for (const r of userRows.values()) {
    r.infraIls += (storage.get(r.uid) ?? 0) * ils;
    r.totalIls = r.aiIls + r.infraIls;
    const s = byUid.get(r.uid);
    r.cumulativeIls = s ? (s.aiUsd + s.infraUsd) * ils + (storage.get(r.uid) ?? 0) * ils : r.totalIls;
  }
  const users = [...userRows.values()].sort((a, b) => b.totalIls - a.totalIls);

  // ---- costs
  const registered = accounts.length;
  const costs = {
    estimated: true,
    totalIls: totalUsd * ils,
    prevTotalIls: prevTotalUsd * ils,
    totalChange: change(totalUsd, prevTotalUsd),
    aiIls: now.aiUsd * ils,
    infraIls: (now.infraUsd + storageTotal) * ils,
    breakdown: (() => {
      const p = pricingAt(pricing, Date.parse(`${to}T23:00:00Z`));
      let r = 0, w = 0, dl = 0, dn = 0, fn = 0, upB = 0, upN = 0, dnN = 0, q = 0;
      for (const d of days) {
        r += d.m.r; w += d.m.w; dl += d.m.d; dn += d.m.dnB; fn += d.m.fn; upB += d.m.upB; upN += d.m.upN; dnN += d.m.dnN; q += d.m.q;
      }
      let photosB = 0, voiceB = 0;
      const latest = new Map<string, NonNullable<UserDay['st']>>();
      for (const d of days) if (d.st && (!latest.get(d.uid) || d.st.at > latest.get(d.uid)!.at)) latest.set(d.uid, d.st);
      for (const st of latest.values()) { photosB += st.photosB; voiceB += st.voiceB; }
      return [
        { id: 'ai', label: 'AI', amount: now.aiCalls, unit: 'קריאות', ils: now.aiUsd * ils, estimated: false },
        { id: 'reads', label: 'קריאות ממסד הנתונים', amount: r, unit: 'מסמכים', ils: (r / 1e5) * p.readsPer100k * ils, estimated: true },
        { id: 'writes', label: 'כתיבות למסד הנתונים', amount: w, unit: 'מסמכים', ils: (w / 1e5) * p.writesPer100k * ils, estimated: true },
        { id: 'deletes', label: 'מחיקות', amount: dl, unit: 'מסמכים', ils: (dl / 1e5) * p.deletesPer100k * ils, estimated: true },
        { id: 'queries', label: 'שאילתות/האזנות', amount: q, unit: 'שאילתות', ils: 0, estimated: true },
        { id: 'photos', label: 'אחסון תמונות', amount: photosB, unit: 'bytes', ils: (photosB / 1e9) * p.storageGbMonth * (periodDays / 30) * ils, estimated: true },
        { id: 'voice', label: 'אחסון הקלטות', amount: voiceB, unit: 'bytes', ils: (voiceB / 1e9) * p.storageGbMonth * (periodDays / 30) * ils, estimated: true },
        { id: 'egress', label: 'הורדות קבצים (תעבורה)', amount: dn, unit: 'bytes', ils: (dn / 1e9) * p.egressGb * ils, estimated: true },
        { id: 'uploads', label: 'העלאות קבצים', amount: upB, unit: 'bytes', ils: 0, estimated: true, count: upN },
        { id: 'downloads', label: 'הורדות', amount: dnN, unit: 'קבצים', ils: 0, estimated: true },
        { id: 'functions', label: 'קריאות Backend (Functions)', amount: fn, unit: 'קריאות', ils: (fn / 1e6) * p.fnPerMillion * ils, estimated: true },
        { id: 'push', label: 'התראות Push (FCM)', amount: 0, unit: '', ils: 0, estimated: false, note: 'ללא עלות' },
        { id: 'auth', label: 'הזדהות (ללא SMS)', amount: 0, unit: '', ils: 0, estimated: false, note: 'ללא עלות במסלול הנוכחי' },
      ];
    })(),
    perActiveUserIls: activeUsers > 0 ? (totalUsd * ils) / activeUsers : 0,
    perRegisteredUserIls: registered > 0 ? (totalUsd * ils) / registered : 0,
    aiPerAiUserIls: aiUsersCount > 0 ? (now.aiUsd * ils) / aiUsersCount : 0,
    perIdeaIls: now.ideas > 0 ? (totalUsd * ils) / now.ideas : null,
    perCoupleIls: now.couples > 0 ? (totalUsd * ils) / now.couples : null,
    perNewUserIls: (() => {
      if (newUsers.length === 0) return null;
      const ids = new Set(newUsers.map((a) => a.uid));
      const spent = users.filter((u) => ids.has(u.uid)).reduce((t, u) => t + u.totalIls, 0);
      return spent / newUsers.length;
    })(),
  };

  // ---- errors and performance
  const errMap = new Map<string, { feature: string; code: string; version: string; platform: string; count: number; users: Set<string>; last: number; ms: number }>();
  for (const d of days) {
    for (const [k, e] of Object.entries(d.err)) {
      const [feature, c, version, platform] = k.split('~');
      const r = errMap.get(k) ?? { feature, code: c, version, platform, count: 0, users: new Set<string>(), last: 0, ms: 0 };
      r.count += e.n;
      r.users.add(d.uid);
      r.last = Math.max(r.last, e.last);
      r.ms += e.ms;
      errMap.set(k, r);
    }
  }
  const errors = [...errMap.values()]
    .map((r) => ({
      feature: r.feature,
      name: FEATURE_NAMES[r.feature] ?? r.feature,
      code: r.code,
      version: r.version,
      platform: r.platform,
      count: r.count,
      users: r.users.size,
      last: r.last,
      avgMs: r.count > 0 && r.ms > 0 ? Math.round(r.ms / r.count) : null,
      timeout: r.code.includes('timeout'),
    }))
    .sort((a, b) => b.users - a.users || b.count - a.count);
  const perfMap = new Map<string, { n: number; sum: number; max: number; slow: number }>();
  for (const d of days) {
    for (const [k, p] of Object.entries(d.perf)) {
      const r = perfMap.get(k) ?? { n: 0, sum: 0, max: 0, slow: 0 };
      r.n += p.n;
      r.sum += p.sum;
      r.max = Math.max(r.max, p.max);
      r.slow += p.slow;
      perfMap.set(k, r);
    }
  }
  const performance = [...perfMap.entries()]
    .map(([metric, r]) => ({ metric, count: r.n, avgMs: r.n > 0 ? Math.round(r.sum / r.n) : 0, maxMs: r.max, slowShare: pct(r.slow, r.n) }))
    .sort((a, b) => b.count - a.count);
  const failedRequests = errors.reduce((t, e) => t + e.count, 0);
  const timeouts = errors.filter((e) => e.timeout).reduce((t, e) => t + e.count, 0);

  // ---- versions
  const verMap = new Map<string, { users: Set<string>; sessions: number; sessionMs: number; errors: number; fails: number; done: number; startSum: number; startN: number }>();
  for (const d of days) {
    const v = Object.entries(d.ver).sort((a, b) => b[1] - a[1])[0]?.[0] ?? 'unknown';
    const r = verMap.get(v) ?? { users: new Set<string>(), sessions: 0, sessionMs: 0, errors: 0, fails: 0, done: 0, startSum: 0, startN: 0 };
    r.users.add(d.uid);
    r.sessions += d.sess.n;
    r.sessionMs += d.sess.ms;
    r.errors += Object.values(d.err).reduce((t, e) => t + e.n, 0);
    for (const c of Object.values(d.f)) {
      r.fails += c.x ?? 0;
      r.done += c.c ?? 0;
    }
    const st = d.perf['app~start'];
    if (st) {
      r.startSum += st.sum;
      r.startN += st.n;
    }
    verMap.set(v, r);
  }
  const versions = [...verMap.entries()]
    .map(([version, r]) => ({
      version,
      users: r.users.size,
      sessions: r.sessions,
      avgSessionMin: r.sessions > 0 ? Math.round((r.sessionMs / r.sessions / 60000) * 10) / 10 : 0,
      errorsPerUser: r.users.size > 0 ? Math.round((r.errors / r.users.size) * 10) / 10 : 0,
      failRate: pct(r.fails, r.fails + r.done),
      avgStartMs: r.startN > 0 ? Math.round(r.startSum / r.startN) : null,
    }))
    .sort((a, b) => b.version.localeCompare(a.version, undefined, { numeric: true }));

  // ---- anomalies
  const anomalies: { kind: string; uid?: string; email?: string; detail: string }[] = [];
  const avg = (vals: number[]) => (vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : 0);
  const avgUploads = avg(users.map((u) => u.uploads));
  const avgBackend = avg(users.map((u) => u.backend));
  for (const u of ai.byUser) {
    if (u.timesAverage !== null && u.timesAverage >= 5 && u.ils >= 1) {
      anomalies.push({ kind: 'ai', uid: u.uid, email: u.email, detail: `AI פי ${u.timesAverage} מהממוצע (${u.ils.toFixed(2)} ₪)` });
    }
  }
  for (const u of users) {
    if (u.uploads >= 100 && u.uploads >= avgUploads * 5) {
      anomalies.push({ kind: 'uploads', uid: u.uid, email: u.email, detail: `${u.uploads} העלאות (ממוצע ${Math.round(avgUploads)})` });
    }
    if (u.backend >= 2000 && u.backend >= avgBackend * 5) {
      anomalies.push({ kind: 'backend', uid: u.uid, email: u.email, detail: `${u.backend} קריאות Backend (ממוצע ${Math.round(avgBackend)})` });
    }
  }
  for (const d of days) {
    if (d.ev >= 5000 || d.m.w >= 20000 || d.m.r >= 200000) {
      anomalies.push({ kind: 'loop', uid: d.uid, email: emailOf.get(d.uid) ?? '', detail: `${d.day}: ${d.ev} אירועים, ${d.m.r} קריאות, ${d.m.w} כתיבות ביום אחד — ייתכן לולאה` });
    }
  }
  if (prevTotalUsd > 0 && totalUsd >= prevTotalUsd * 2 && totalUsd * ils >= 5) {
    anomalies.push({ kind: 'cost', detail: `העלות קפצה מ־${(prevTotalUsd * ils).toFixed(2)} ל־${(totalUsd * ils).toFixed(2)} ₪ מול התקופה הקודמת` });
  }

  return {
    period: { from, to, days: periodDays, prevFrom, prevTo: addDays(from, -1) },
    pricing: { current: latestPricing.id, set: latestPricing.id !== 'none', usdToIls: ils },
    overview: {
      registered,
      activeUsers,
      activeUsersChange: change(activeUsers, before.users.size),
      dau: Math.round(avg(dauSeries.map((s) => s.users)) * 10) / 10,
      wau: activeBetween(addDays(to, -6), to),
      mau: activeBetween(addDays(to, -29), to),
      dauToday: activeOn(to),
      newUsers: newUsers.length,
      activeSingles: usersByType.single + usersByType.both,
      activeMatchmakers: usersByType.matchmaker + usersByType.both,
      ideas: now.ideas,
      ideasChange: change(now.ideas, before.ideas),
      couples: now.couples,
      couplesChange: change(now.couples, before.couples),
      totalIls: costs.totalIls,
      aiIls: costs.aiIls,
      infraIls: costs.infraIls,
      series: dauSeries,
    },
    movement: {
      returned,
      stopped,
      sessions: now.sessions,
      sessionsChange: change(now.sessions, before.sessions),
      avgSessionMin: now.sessions > 0 ? Math.round((now.sessionMs / now.sessions / 60000) * 10) / 10 : 0,
      avgDaysPerWeek,
      retention,
      byType: usersByType,
    },
    features,
    actions,
    funnels,
    ai,
    costs,
    users,
    errors,
    performance,
    failedRequests,
    timeouts,
    versions,
    anomalies,
  };
}

export type Dashboard = ReturnType<typeof summarize>;

/** The internal thresholds an administrator sets. Zero = off. */
export interface Thresholds {
  aiDailyIls: number;
  userDailyIls: number;
  featureSpikeFactor: number;
  errorRatePercent: number;
}

/** Alerts for one day, against the thresholds and the seven days before. */
export function thresholdAlerts(
  today: UserDay[],
  week: UserDay[],
  t: Thresholds,
  usdToIls: number,
): { code: string; title: string; body: string }[] {
  const out: { code: string; title: string; body: string }[] = [];
  const aiIls = today.reduce((s, d) => s + Object.values(d.ai).reduce((a, x) => a + x.usd, 0), 0) * usdToIls;
  if (t.aiDailyIls > 0 && aiIls > t.aiDailyIls) {
    out.push({ code: 'ai_daily', title: 'עלות AI יומית חרגה', body: `היום: ${aiIls.toFixed(2)} ₪ (סף ${t.aiDailyIls} ₪)` });
  }
  if (t.userDailyIls > 0) {
    for (const d of today) {
      const ils = (Object.values(d.ai).reduce((a, x) => a + x.usd, 0) + d.m.usd) * usdToIls;
      if (ils > t.userDailyIls) {
        out.push({ code: `user_${d.uid}`, title: 'משתמש חרג מסכום יומי', body: `${d.uid}: ${ils.toFixed(2)} ₪ היום (סף ${t.userDailyIls} ₪)` });
      }
    }
  }
  if (t.featureSpikeFactor > 1) {
    const uses = (days: UserDay[]) => {
      const m = new Map<string, number>();
      for (const d of days) for (const [f, c] of Object.entries(d.f)) m.set(f, (m.get(f) ?? 0) + (c.o ?? 0) + (c.c ?? 0) + (c.x ?? 0));
      return m;
    };
    const now = uses(today);
    const before = uses(week);
    for (const [f, n] of now) {
      const daily = (before.get(f) ?? 0) / 7;
      if (n >= 50 && daily > 0 && n > daily * t.featureSpikeFactor) {
        out.push({ code: `spike_${f}`, title: 'קפיצה חריגה בשימוש', body: `${FEATURE_NAMES[f] ?? f}: ${n} היום מול ממוצע ${Math.round(daily)} ליום` });
      }
    }
  }
  if (t.errorRatePercent > 0) {
    let done = 0;
    let fail = 0;
    for (const d of today) for (const c of Object.values(d.f)) {
      done += c.c ?? 0;
      fail += c.x ?? 0;
    }
    const rate = pct(fail, done + fail);
    if (done + fail >= 30 && rate > t.errorRatePercent) {
      out.push({ code: 'error_rate', title: 'שיעור השגיאות עלה', body: `${rate}% מהפעולות נכשלו היום (סף ${t.errorRatePercent}%)` });
    }
  }
  return out;
}
