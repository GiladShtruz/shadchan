// Security rules for "שדכנים שאני מכיר" (matchmakerConnections), run against
// the Firestore emulator:
//
//   cd functions && npm run test:rules
//
// Contacts are the layer of trust: a matchmaker may ask only a matchmaker
// saved in their own phone, only the side asked may answer, and nobody else
// may read the row.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

// Sorted, so the pair id is A_B.
const A = 'mmA';
const B = 'mmB';
const C = 'mmC'; // a stranger: not in A's phone
const A_HASH = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const B_HASH = 'bbbbbbbbbbbbbbbbbbbbbbbb';
const C_HASH = 'cccccccccccccccccccccccc';
const PAIR = `${A}_${B}`;

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shadchan',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, hash, matchmaker] of [
      [A, A_HASH, true],
      [B, B_HASH, true],
      [C, C_HASH, true],
    ]) {
      await setDoc(doc(db, `userPhones/${uid}`), { phoneHash: hash });
      await setDoc(doc(db, `phoneDirectory/${hash}`), {
        uid,
        name: uid,
        matchmaker,
        hasCard: false,
      });
    }
    // A has B saved; B has A saved; nobody has C.
    await setDoc(doc(db, `contactHashes/${A}`), { hashes: [B_HASH] });
    await setDoc(doc(db, `contactHashes/${B}`), { hashes: [A_HASH] });
    await setDoc(doc(db, `contactHashes/${C}`), { hashes: [] });
    await setDoc(doc(db, `matchmakerActivity/${B}`), {
      databaseCount: 40,
      lastActiveAt: Timestamp.now(),
    });
  });
});

function as(uid) {
  return env
    .authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } })
    .firestore();
}

function request(from, to, extra = {}) {
  const uids = [from, to].sort();
  return {
    uids,
    fromUid: from,
    toUid: to,
    status: 'pending',
    names: { [from]: `name of ${from}`, [to]: `name of ${to}` },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

async function seed(data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `matchmakerConnections/${PAIR}`), data);
  });
}

test('a matchmaker may ask a matchmaker saved in their phone', async () => {
  await assertSucceeds(
    setDoc(doc(as(A), `matchmakerConnections/${PAIR}`), request(A, B)),
  );
});

test('nobody may ask a stranger, or ask on somebody else\'s behalf', async () => {
  const pairAC = `${A}_${C}`;
  await assertFails(
    setDoc(doc(as(A), `matchmakerConnections/${pairAC}`), request(A, C)),
  );
  await assertFails(
    setDoc(doc(as(C), `matchmakerConnections/${PAIR}`), request(A, B)),
  );
  // Born approved is not asking.
  await assertFails(
    setDoc(
      doc(as(A), `matchmakerConnections/${PAIR}`),
      request(A, B, { status: 'approved' }),
    ),
  );
});

test('only the two can read it', async () => {
  await seed(request(A, B, { createdAt: Timestamp.now(), updatedAt: Timestamp.now() }));
  await assertSucceeds(getDoc(doc(as(A), `matchmakerConnections/${PAIR}`)));
  await assertSucceeds(getDoc(doc(as(B), `matchmakerConnections/${PAIR}`)));
  await assertFails(getDoc(doc(as(C), `matchmakerConnections/${PAIR}`)));
});

test('only the side asked may approve', async () => {
  await seed(request(A, B, { createdAt: Timestamp.now(), updatedAt: Timestamp.now() }));
  await assertFails(
    updateDoc(doc(as(A), `matchmakerConnections/${PAIR}`), {
      status: 'approved',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(as(B), `matchmakerConnections/${PAIR}`), {
      status: 'approved',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('after a "not now" the one declined waits; the one who declined may ask', async () => {
  await seed(
    request(A, B, {
      status: 'declined',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    }),
  );
  // A was declined a moment ago: no new request yet, and no deleting it away.
  await assertFails(
    setDoc(doc(as(A), `matchmakerConnections/${PAIR}`), request(A, B)),
  );
  await assertFails(deleteDoc(doc(as(A), `matchmakerConnections/${PAIR}`)));
  // B, who said "not now", may change their mind.
  await assertSucceeds(
    setDoc(doc(as(B), `matchmakerConnections/${PAIR}`), request(B, A)),
  );
});

test('a declined request may be asked again after thirty days', async () => {
  const old = Timestamp.fromMillis(Date.now() - 31 * 86400000);
  await seed(request(A, B, { status: 'declined', createdAt: old, updatedAt: old }));
  await assertSucceeds(
    setDoc(doc(as(A), `matchmakerConnections/${PAIR}`), request(A, B)),
  );
});

test('either side may leave a connection', async () => {
  await seed(
    request(A, B, {
      status: 'approved',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    }),
  );
  await assertFails(deleteDoc(doc(as(C), `matchmakerConnections/${PAIR}`)));
  await assertSucceeds(deleteDoc(doc(as(B), `matchmakerConnections/${PAIR}`)));
});

test('a contact\'s activity figures are readable; a stranger\'s are not', async () => {
  await assertSucceeds(getDoc(doc(as(A), `matchmakerActivity/${B}`)));
  await assertFails(getDoc(doc(as(C), `matchmakerActivity/${B}`)));
});
