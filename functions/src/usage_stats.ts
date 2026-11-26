/**
 * The administrator's cost and usage lists, added up from two places the
 * app already writes — pure, so it is tested without Firestore:
 *
 * - `accountHealth/{uid}.devices.*` — per phone, the photos/voice-notes
 *   footprint (`storage`) and the page/feature tally (`features`,
 *   `FeatureUsage` in the app);
 * - `aiUsage/{uid}` — token counters kept with increments after every
 *   Gemini answer (`AiUsage`).
 *
 * Money is **not** computed here: prices change and live in
 * `adminConfig/pricing`, which the console applies to these counts.
 */

export interface HealthDoc {
  uid: string;
  email?: string;
  devices?: Record<string, unknown>;
}

export interface AiDoc {
  uid: string;
  calls?: number;
  inputTokens?: number;
  outputTokens?: number;
  months?: Record<string, { calls?: number; inputTokens?: number; outputTokens?: number }>;
  features?: Record<string, { calls?: number; inputTokens?: number; outputTokens?: number }>;
}

export interface UsageBlock {
  storage: {
    accounts: number;
    photos: number;
    photoBytes: number;
    voice: number;
    voiceBytes: number;
    top: { uid: string; email: string; bytes: number; photos: number }[];
  };
  ai: {
    accounts: number;
    calls: number;
    inputTokens: number;
    outputTokens: number;
    month: string;
    monthCalls: number;
    monthInputTokens: number;
    monthOutputTokens: number;
    byFeature: Record<string, { calls: number; inputTokens: number; outputTokens: number }>;
    top: {
      uid: string;
      email: string;
      calls: number;
      inputTokens: number;
      outputTokens: number;
      monthInputTokens: number;
      monthOutputTokens: number;
    }[];
  };
  /** Most used first, by accounts active with it in the last 30 days. */
  features: { code: string; accounts: number; accounts30: number; uses: number }[];
}

const DAY = 24 * 60 * 60 * 1000;

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : 0;
}

export function monthKeyOf(now: number): string {
  const d = new Date(now);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

export function usageBlock(health: HealthDoc[], ai: AiDoc[], now: number, internal: Set<string> = new Set()): UsageBlock {
  const emailOf = new Map<string, string>();
  const storageRows: { uid: string; email: string; bytes: number; photos: number; voice: number; voiceBytes: number; photoBytes: number }[] = [];
  const featureAgg = new Map<string, { accounts: number; accounts30: number; uses: number }>();
  const since30 = now - 30 * DAY;

  for (const doc of health) {
    if (internal.has(doc.uid)) continue;
    const email = (doc.email ?? '').toString();
    emailOf.set(doc.uid, email);
    const devices = doc.devices && typeof doc.devices === 'object' ? Object.values(doc.devices) : [];
    // The account's files are the same on each of its phones: the largest
    // phone is the account, not the sum.
    let best = { photos: 0, photoBytes: 0, voice: 0, voiceBytes: 0 };
    const perFeature = new Map<string, { uses: number; last: number }>();
    for (const raw of devices) {
      if (!raw || typeof raw !== 'object') continue;
      const d = raw as Record<string, unknown>;
      const s = d.storage as Record<string, unknown> | undefined;
      if (s && typeof s === 'object') {
        const row = {
          photos: num(s.photos),
          photoBytes: num(s.photoBytes),
          voice: num(s.voice),
          voiceBytes: num(s.voiceBytes),
        };
        if (row.photoBytes + row.voiceBytes > best.photoBytes + best.voiceBytes) best = row;
      }
      const f = d.features as Record<string, unknown> | undefined;
      if (f && typeof f === 'object') {
        for (const [code, value] of Object.entries(f)) {
          if (!value || typeof value !== 'object') continue;
          const v = value as Record<string, unknown>;
          const last = typeof v.last === 'string' ? Date.parse(v.last) : NaN;
          const prev = perFeature.get(code) ?? { uses: 0, last: 0 };
          perFeature.set(code, {
            uses: prev.uses + num(v.n),
            last: Math.max(prev.last, Number.isNaN(last) ? 0 : last),
          });
        }
      }
    }
    const bytes = best.photoBytes + best.voiceBytes;
    if (bytes > 0) storageRows.push({ uid: doc.uid, email, bytes, ...best });
    for (const [code, v] of perFeature) {
      const agg = featureAgg.get(code) ?? { accounts: 0, accounts30: 0, uses: 0 };
      agg.accounts += 1;
      if (v.last >= since30) agg.accounts30 += 1;
      agg.uses += v.uses;
      featureAgg.set(code, agg);
    }
  }

  const month = monthKeyOf(now);
  const byFeature: UsageBlock['ai']['byFeature'] = {};
  const aiRows: UsageBlock['ai']['top'] = [];
  let calls = 0;
  let input = 0;
  let output = 0;
  let mCalls = 0;
  let mInput = 0;
  let mOutput = 0;
  for (const doc of ai) {
    if (internal.has(doc.uid)) continue;
    const m = doc.months?.[month] ?? {};
    calls += num(doc.calls);
    input += num(doc.inputTokens);
    output += num(doc.outputTokens);
    mCalls += num(m.calls);
    mInput += num(m.inputTokens);
    mOutput += num(m.outputTokens);
    for (const [name, v] of Object.entries(doc.features ?? {})) {
      const agg = (byFeature[name] ??= { calls: 0, inputTokens: 0, outputTokens: 0 });
      agg.calls += num(v?.calls);
      agg.inputTokens += num(v?.inputTokens);
      agg.outputTokens += num(v?.outputTokens);
    }
    aiRows.push({
      uid: doc.uid,
      email: emailOf.get(doc.uid) ?? '',
      calls: num(doc.calls),
      inputTokens: num(doc.inputTokens),
      outputTokens: num(doc.outputTokens),
      monthInputTokens: num(m.inputTokens),
      monthOutputTokens: num(m.outputTokens),
    });
  }
  // Output tokens cost several times input tokens; rank by a rough weight so
  // the list leads with who costs most whatever the exact prices are.
  aiRows.sort((a, b) => b.inputTokens + 4 * b.outputTokens - (a.inputTokens + 4 * a.outputTokens));
  storageRows.sort((a, b) => b.bytes - a.bytes);

  return {
    storage: {
      accounts: storageRows.length,
      photos: storageRows.reduce((t, r) => t + r.photos, 0),
      photoBytes: storageRows.reduce((t, r) => t + r.photoBytes, 0),
      voice: storageRows.reduce((t, r) => t + r.voice, 0),
      voiceBytes: storageRows.reduce((t, r) => t + r.voiceBytes, 0),
      top: storageRows.slice(0, 20).map(({ uid, email, bytes, photos }) => ({ uid, email, bytes, photos })),
    },
    ai: {
      accounts: ai.filter((d) => !internal.has(d.uid) && num(d.calls) > 0).length,
      calls,
      inputTokens: input,
      outputTokens: output,
      month,
      monthCalls: mCalls,
      monthInputTokens: mInput,
      monthOutputTokens: mOutput,
      byFeature,
      top: aiRows.slice(0, 25),
    },
    features: [...featureAgg.entries()]
      .map(([code, v]) => ({ code, ...v }))
      .sort((a, b) => b.accounts30 - a.accounts30 || b.uses - a.uses),
  };
}
