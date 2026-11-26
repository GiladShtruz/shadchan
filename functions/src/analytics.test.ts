import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  Account,
  applyBatch,
  NO_PRICING,
  PricingVersion,
  RawEvent,
  summarize,
  thresholdAlerts,
  updateSummary,
  addDeltas,
  UserDay,
  UserSummary,
} from './analytics';

const T = Date.parse('2026-11-26T10:00:00Z'); // Israel 12:00
const DAY = 24 * 60 * 60 * 1000;

const v1: PricingVersion = { ...NO_PRICING, id: 'v1', from: 0, usdToIls: 4, aiIn: 1, aiOut: 2, readsPer100k: 0.06, writesPer100k: 0.18 };
const v2: PricingVersion = { ...v1, id: 'v2', from: T + DAY / 2, aiIn: 10, aiOut: 20 };

let n = 0;
function ev(t: RawEvent['t'], f: string, a?: string, extra: Partial<RawEvent> = {}): RawEvent {
  n += 1;
  return { id: `e${n}`, t, f, a, ts: T, s: 's1', ...extra };
}

function fold(uid: string, events: RawEvent[], batch = `b${n}`, existing: Record<string, UserDay | undefined> = {}) {
  return applyBatch(batch, { uid, v: '1.0.20', p: 'android', ut: 'matchmaker' }, events, existing, [v1, v2]);
}

test('events fold into one document per account per Israel day', () => {
  const out = fold('u1', [ev('open', 'matches'), ev('start', 'matches', 'preview'), ev('done', 'matches', 'idea')]);
  const d = out['2026-11-26'];
  assert.equal(d.f.matches.o, 1);
  assert.equal(d.fa['matches~preview'].s, 1);
  assert.equal(d.fa['matches~idea'].c, 1);
  assert.equal(d.ut, 'matchmaker');
  assert.equal(d.ver['1.0.20'], 3);
});

test('a retried batch is counted once', () => {
  const first = fold('u1', [ev('open', 'home')], 'same');
  const again = fold('u1', [ev('open', 'home')], 'same', first);
  assert.deepEqual(again, {});
});

test('a duplicated event id inside a batch is counted once', () => {
  const e = ev('open', 'home');
  const out = fold('u1', [e, e]);
  assert.equal(out['2026-11-26'].f.home.o, 1);
});

test('AI is priced with the version in force at the call, never repriced', () => {
  const out = fold('u1', [
    ev('ai', 'ai', 'import', { ms: 1200, x: { model: 'gemini', in: 1_000_000, out: 1_000_000, ok: true, tries: 2 } }),
  ]);
  const a = out['2026-11-26'].ai.ai;
  assert.equal(a.usd, 3); // v1: 1 + 2
  assert.deepEqual(a.pv, { v1: 1 });
  assert.equal(a.tries, 1);
  assert.equal(a.lat, 1200);
});

test('a failed action is an error row with its version and platform', () => {
  const out = fold('u1', [ev('fail', 'whatsapp_share', 'card', { e: 'TimeoutException', ms: 30000 })]);
  const d = out['2026-11-26'];
  assert.equal(d.f.whatsapp_share.x, 1);
  assert.deepEqual(Object.keys(d.err), ['whatsapp_share~timeoutexception~1.0.20~android']);
});

test('meters add up and are priced as an estimate; storage is the latest', () => {
  const out = fold('u1', [ev('meter', 'app', undefined, { x: { r: 100000, w: 100000, photosB: 5e9, voiceB: 0, photos: 900 } })]);
  const d = out['2026-11-26'];
  assert.equal(d.m.r, 100000);
  assert.ok(Math.abs(d.m.usd - 0.24) < 1e-9);
  assert.equal(d.st?.photos, 900);
});

function dayDoc(uid: string, day: string, partial: Partial<UserDay>): UserDay {
  return {
    uid,
    day,
    plat: { android: 1 },
    ver: { '1.0.20': 1 },
    ut: 'matchmaker',
    ev: 1,
    sess: { n: 1, ms: 60000 },
    f: {},
    fa: {},
    ai: {},
    err: {},
    perf: {},
    m: { r: 0, w: 0, d: 0, q: 0, upB: 0, dnB: 0, upN: 0, dnN: 0, fn: 0, usd: 0 },
    batches: [],
    ...partial,
  };
}

function summaryOf(uid: string, days: string[], ut = 'matchmaker'): UserSummary {
  return { uid, firstDay: days[0], lastDay: days[days.length - 1], days, ut, plat: 'android', ver: '1.0.20', aiUsd: 0, infraUsd: 0, aiCalls: 0, events: 0 };
}

test('the dashboard: features, funnels, AI by feature, costs per idea, returning users', () => {
  const accounts: Account[] = [
    { uid: 'a', email: 'a@x', created: Date.parse('2026-01-01') },
    { uid: 'b', email: 'b@x', created: Date.parse('2026-11-20T12:00:00Z') },
  ];
  const days: UserDay[] = [
    dayDoc('a', '2026-11-25', {
      f: { matches: { o: 2, s: 1, c: 1 }, idea_open: { c: 1 } },
      fa: { 'matches~preview': { s: 1 }, 'matches~idea': { c: 1 }, 'idea_open~create': { c: 1 } },
      ai: { ai: { n: 2, ok: 1, x: 1, tries: 1, lat: 3000, in: 1000, out: 500, usd: 0.5, pv: { v1: 2 }, models: { gemini: 2 } } },
    }),
    dayDoc('b', '2026-11-26', { ut: 'single', f: { matches: { o: 1 } } }),
  ];
  const s = summarize({
    from: '2026-11-20',
    to: '2026-11-26',
    today: '2026-11-26',
    days,
    prevDays: [dayDoc('a', '2026-11-15', { f: { matches: { o: 1 } } })],
    accounts,
    summaries: [summaryOf('a', ['2026-10-01', '2026-11-25']), summaryOf('b', ['2026-11-21', '2026-11-26'], 'single')],
    pricing: [v1],
  });
  assert.equal(s.overview.activeUsers, 2);
  assert.equal(s.overview.newUsers, 1);
  assert.equal(s.overview.ideas, 1);
  assert.equal(s.overview.activeSingles, 1);
  assert.equal(s.overview.activeMatchmakers, 1);
  assert.equal(s.movement.returned, 1); // a: gap from 10-01 to 11-25
  const matches = s.features.find((f) => f.id === 'matches')!;
  assert.equal(matches.users, 2);
  assert.equal(matches.share, 100);
  assert.equal(matches.usesChange, 300); // 4 vs 1
  const funnel = s.funnels.find((f) => f.id === 'matches')!;
  assert.deepEqual(funnel.steps.map((st) => st.users), [2, 1, 1]);
  assert.equal(s.ai.byFeature[0].ils, 2); // 0.5 USD × 4
  assert.equal(s.ai.failed, 1);
  assert.equal(s.costs.perIdeaIls, 2);
  assert.equal(s.users[0].uid, 'a');
});

test('summary totals follow the difference each fold made', () => {
  const first = fold('u9', [ev('ai', 'ai', 'card', { x: { model: 'g', in: 1e6, out: 0 } })], 'x1');
  const s = updateSummary(undefined, 'u9', Object.values(first), { uid: 'u9' });
  addDeltas(s, undefined, first['2026-11-26']);
  const second = fold('u9', [ev('ai', 'ai', 'card', { x: { model: 'g', in: 1e6, out: 0 } })], 'x2', first);
  addDeltas(s, first['2026-11-26'], second['2026-11-26']);
  assert.equal(s.aiCalls, 2);
  assert.equal(s.aiUsd, 2);
});

test('thresholds: daily AI cost, one expensive user, a spike, the error rate', () => {
  const today = [
    dayDoc('a', '2026-11-26', {
      ai: { ai: { n: 1, ok: 1, x: 0, tries: 0, lat: 0, in: 0, out: 0, usd: 10, pv: {}, models: {} } },
      f: { search: { o: 200, c: 10, x: 40 } },
    }),
  ];
  const week = [dayDoc('a', '2026-11-20', { f: { search: { o: 70 } } })];
  const alerts = thresholdAlerts(today, week, { aiDailyIls: 20, userDailyIls: 30, featureSpikeFactor: 3, errorRatePercent: 20 }, 4);
  const codes = alerts.map((a) => a.code).sort();
  assert.deepEqual(codes, ['ai_daily', 'error_rate', 'spike_search', 'user_a']);
});
