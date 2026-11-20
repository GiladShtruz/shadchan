// Security rules for sharing between two matchmakers (matchmakerShares,
// 2026-11-20), run against the Firestore emulator:
//
//   cd functions && npm run test:rules
//
// Contacts are the layer of trust: a matchmaker shares with, or asks, only a
// matchmaker they know from the phone book. Only the owner decides what is
// shared; the reader may only ask. Nobody else reads the row.
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
const AB = `${A}_${B}`; // what A shares with B
const BA = `${B}_${A}`;

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

function share(owner, reader, mode, extra = {}) {
  return {
    ownerUid: owner,
    readerUid: reader,
    uids: [owner, reader],
    mode,
    count: 0,
    ownerName: `name of ${owner}`,
    readerName: `name of ${reader}`,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

async function seed(id, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `matchmakerShares/${id}`), {
      ...data,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });
}

test('a matchmaker shares with a matchmaker they know, without asking anyone', async () => {
  await assertSucceeds(setDoc(doc(as(A), `matchmakerShares/${AB}`), share(A, B, 'all')));
  await assertSucceeds(
    updateDoc(doc(as(A), `matchmakerShares/${AB}`), { mode: 'selected', count: 3, updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(doc(as(A), `matchmakerShares/${AB}`), { mode: 'none', count: 0, updatedAt: serverTimestamp() }),
  );
});

test('never with a stranger, never in somebody else\'s name', async () => {
  await assertFails(setDoc(doc(as(A), `matchmakerShares/${A}_${C}`), share(A, C, 'all')));
  await assertFails(setDoc(doc(as(C), `matchmakerShares/${AB}`), share(A, B, 'all')));
  // The reader cannot open the owner's database for themselves.
  await assertFails(setDoc(doc(as(B), `matchmakerShares/${AB}`), share(A, B, 'all')));
  // The id is always owner_reader.
  await assertFails(setDoc(doc(as(A), `matchmakerShares/${BA}`), share(A, B, 'all')));
});

test('the reader may only ask, and ask again after a stop', async () => {
  await assertSucceeds(setDoc(doc(as(B), `matchmakerShares/${AB}`), share(A, B, 'requested')));
  await assertFails(
    updateDoc(doc(as(B), `matchmakerShares/${AB}`), { mode: 'all', updatedAt: serverTimestamp() }),
  );
  // Withdrawn.
  await assertSucceeds(deleteDoc(doc(as(B), `matchmakerShares/${AB}`)));
  await seed(AB, share(A, B, 'none'));
  await assertSucceeds(
    updateDoc(doc(as(B), `matchmakerShares/${AB}`), { mode: 'requested', updatedAt: serverTimestamp() }),
  );
  await seed(AB, share(A, B, 'all'));
  // A share in force is not the reader's to remove.
  await assertFails(deleteDoc(doc(as(B), `matchmakerShares/${AB}`)));
  await assertSucceeds(deleteDoc(doc(as(A), `matchmakerShares/${AB}`)));
});

test('only the two can read it', async () => {
  await seed(AB, share(A, B, 'all'));
  await assertSucceeds(getDoc(doc(as(A), `matchmakerShares/${AB}`)));
  await assertSucceeds(getDoc(doc(as(B), `matchmakerShares/${AB}`)));
  await assertFails(getDoc(doc(as(C), `matchmakerShares/${AB}`)));
});

test('the old mutual connections are closed', async () => {
  await assertFails(
    setDoc(doc(as(A), `matchmakerConnections/${AB}`), { uids: [A, B], status: 'pending' }),
  );
});

test('a contact\'s activity figures are readable; a stranger\'s are not', async () => {
  await assertSucceeds(getDoc(doc(as(A), `matchmakerActivity/${B}`)));
  await assertFails(getDoc(doc(as(C), `matchmakerActivity/${B}`)));
});
