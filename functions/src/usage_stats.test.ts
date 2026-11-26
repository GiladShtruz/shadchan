import { test } from 'node:test';
import assert from 'node:assert/strict';
import { usageBlock, monthKeyOf } from './usage_stats';

const now = Date.parse('2026-11-26T12:00:00Z');

test('storage is the largest phone of an account, not the sum', () => {
  const b = usageBlock(
    [
      {
        uid: 'a',
        email: 'a@x',
        devices: {
          p1: { storage: { photos: 10, photoBytes: 1000, voice: 1, voiceBytes: 50 } },
          p2: { storage: { photos: 12, photoBytes: 1200, voice: 0, voiceBytes: 0 } },
        },
      },
    ],
    [],
    now,
  );
  assert.equal(b.storage.photoBytes, 1200);
  assert.equal(b.storage.top[0].email, 'a@x');
});

test('features: accounts, recent accounts and uses, most used first', () => {
  const b = usageBlock(
    [
      { uid: 'a', devices: { p: { features: { 'screen:/people': { n: 5, last: '2026-11-25' }, 'feature:tags': { n: 1, last: '2026-01-01' } } } } },
      { uid: 'b', devices: { p: { features: { 'screen:/people': { n: 2, last: '2026-11-20' } } } } },
    ],
    [],
    now,
  );
  assert.deepEqual(b.features[0], { code: 'screen:/people', accounts: 2, accounts30: 2, uses: 7 });
  assert.deepEqual(b.features[1], { code: 'feature:tags', accounts: 1, accounts30: 0, uses: 1 });
});

test('AI: totals, this month, per feature, and the costliest first', () => {
  const month = monthKeyOf(now);
  const b = usageBlock(
    [{ uid: 'b', email: 'b@x' }],
    [
      { uid: 'a', calls: 1, inputTokens: 100, outputTokens: 10, features: { card: { calls: 1, inputTokens: 100, outputTokens: 10 } } },
      {
        uid: 'b',
        calls: 3,
        inputTokens: 5000,
        outputTokens: 900,
        months: { [month]: { calls: 2, inputTokens: 4000, outputTokens: 800 } },
        features: { import: { calls: 3, inputTokens: 5000, outputTokens: 900 } },
      },
    ],
    now,
  );
  assert.equal(b.ai.calls, 4);
  assert.equal(b.ai.monthInputTokens, 4000);
  assert.equal(b.ai.byFeature.import.calls, 3);
  assert.equal(b.ai.top[0].uid, 'b');
  assert.equal(b.ai.top[0].email, 'b@x');
});

test('administrators are left out', () => {
  const b = usageBlock([{ uid: 'adm', devices: { p: { storage: { photoBytes: 9 } } } }], [{ uid: 'adm', calls: 5 }], now, new Set(['adm']));
  assert.equal(b.storage.accounts, 0);
  assert.equal(b.ai.calls, 0);
});
