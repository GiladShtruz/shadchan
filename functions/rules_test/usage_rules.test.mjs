// The monitoring pipeline (2026-11-26): `telemetryBatches`, the server-only
// analytics documents and `adminConfig/*` — run with `npm run test:rules`.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

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
    .authenticatedContext(uid, { email, email_verified: true, firebase: { sign_in_provider: 'password' } })
    .firestore();
}

const batch = (uid) => ({
  uid,
  did: 'device',
  v: '1.0.20',
  p: 'android',
  ut: 'matchmaker',
  events: [{ id: 'e1', t: 'open', f: 'home', ts: 1 }],
  createdAt: serverTimestamp(),
});

test('a phone adds a batch in its own name only, and cannot read it back', async () => {
  await assertSucceeds(setDoc(doc(as('u1'), 'telemetryBatches/b1'), batch('u1')));
  await assertFails(setDoc(doc(as('u1'), 'telemetryBatches/b2'), batch('u2')));
  await assertFails(getDoc(doc(as('u1'), 'telemetryBatches/b1')));
  await assertFails(deleteDoc(doc(as('u1'), 'telemetryBatches/b1')));
  await assertFails(setDoc(doc(as('u1'), 'telemetryBatches/b3'), { ...batch('u1'), text: 'card text' }));
});

test('the monitoring documents are for administrators only, and the server writes them', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'analyticsUsers/u1'), { uid: 'u1' }));
  await assertFails(getDoc(doc(as('u1'), 'analyticsUsers/u1')));
  await assertSucceeds(getDoc(doc(as('adm', 'yitz292@gmail.com'), 'analyticsUsers/u1')));
  await assertFails(setDoc(doc(as('adm', 'yitz292@gmail.com'), 'analyticsUsers/u1'), { uid: 'u1' }));
});

test('prices are versions that only grow; thresholds are administrators\' alone', async () => {
  const admin = as('adm', 'yitz292@gmail.com');
  const v = { id: 'v1', from: 1, usdToIls: 3.7, aiIn: 0.5, aiOut: 3 };
  await assertSucceeds(setDoc(doc(admin, 'adminConfig/pricing'), { versions: [v], updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(admin, 'adminConfig/pricing'), { versions: [], updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(as('u1'), 'adminConfig/pricing'), { versions: [v, v], updatedAt: serverTimestamp() }));
  const t = { aiDailyIls: 20, userDailyIls: 5, featureSpikeFactor: 3, errorRatePercent: 10, updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(admin, 'adminConfig/thresholds'), t));
  await assertFails(setDoc(doc(as('u1'), 'adminConfig/thresholds'), t));
});
