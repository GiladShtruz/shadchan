// The admin dashboard's usage counters (2026-11-26): `aiUsage/{uid}` and
// `adminConfig/pricing` — run with `npm run test:rules`.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, increment, serverTimestamp } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shadchan',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

function as(uid, email) {
  return env
    .authenticatedContext(uid, {
      email,
      email_verified: true,
      firebase: { sign_in_provider: 'password' },
    })
    .firestore();
}

const first = {
  calls: 1,
  inputTokens: 100,
  outputTokens: 20,
  months: { '2026-11': { calls: 1, inputTokens: 100, outputTokens: 20 } },
  features: { card: { calls: 1, inputTokens: 100, outputTokens: 20 } },
};

test('an account keeps its own AI counters, and they only grow', async () => {
  const db = as('u1');
  await assertSucceeds(setDoc(doc(db, 'aiUsage/u1'), first));
  await assertSucceeds(
    updateDoc(doc(db, 'aiUsage/u1'), { calls: increment(1), inputTokens: increment(5), outputTokens: increment(1) }),
  );
  await assertFails(updateDoc(doc(db, 'aiUsage/u1'), { calls: 0 }));
  await assertFails(updateDoc(doc(db, 'aiUsage/u1'), { prompt: 'text' }));
});

test('nobody writes or reads another account\'s counters', async () => {
  await assertFails(setDoc(doc(as('u2'), 'aiUsage/u1'), first));
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'aiUsage/u1'), first));
  await assertFails(getDoc(doc(as('u2'), 'aiUsage/u1')));
});

test('the root administrator reads every counter and sets the prices', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'aiUsage/u1'), first));
  const admin = as('adm', 'yitz292@gmail.com');
  await assertSucceeds(getDoc(doc(admin, 'aiUsage/u1')));
  const pricing = { aiInputPerMillion: 0.5, aiOutputPerMillion: 3, storagePerGbMonth: 0.026, usdToIls: 3.7, updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(admin, 'adminConfig/pricing'), pricing));
  await assertFails(setDoc(doc(as('u1'), 'adminConfig/pricing'), pricing));
  await assertFails(getDoc(doc(as('u1'), 'adminConfig/pricing')));
});
