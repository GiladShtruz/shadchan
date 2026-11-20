// The couple space (2026-11-20): `partnerships`, `partnerCards`, and ideas
// between partners — run against the Firestore emulator with
// `npm run test:rules`.
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
  getDocs,
  setDoc,
  updateDoc,
  collection,
  serverTimestamp,
} from 'firebase/firestore';

const A = 'pA';
const B = 'pB'; // A's partner
const C = 'pC'; // a stranger
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
});

function as(uid) {
  return env
    .authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } })
    .firestore();
}

function pair(extra = {}) {
  return {
    uids: [A, B], fromUid: A, toUid: B, status: 'pending',
    names: { [A]: 'א', [B]: 'ב' },
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...extra,
  };
}

function card(personId, extra = {}) {
  return {
    ownerUid: A, ownerName: 'א', personId,
    firstName: 'נועה', lastName: 'כהן', gender: 'female', age: 25,
    description: '', photoPaths: [], tags: [], status: 'available',
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

async function activate() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `partnerships/${PAIR}`), {
      uids: [A, B], fromUid: A, toUid: B, status: 'active',
      names: { [A]: 'א', [B]: 'ב' },
    });
  });
}

test('an invitation is approved by the one invited, and ended by either', async () => {
  await assertSucceeds(setDoc(doc(as(A), `partnerships/${PAIR}`), pair()));
  // The one who invited cannot approve their own invitation.
  await assertFails(
    updateDoc(doc(as(A), `partnerships/${PAIR}`), { status: 'active', updatedAt: serverTimestamp() }),
  );
  await assertFails(getDoc(doc(as(C), `partnerships/${PAIR}`)));
  await assertSucceeds(
    updateDoc(doc(as(B), `partnerships/${PAIR}`), { status: 'active', updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(doc(as(A), `partnerships/${PAIR}`), {
      status: 'ended', endedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }),
  );
  // Nobody invites in another's name.
  await assertFails(setDoc(doc(as(C), `partnerships/${PAIR}`), pair({ fromUid: C })));
});

test('the partner reads the whole database while active — never a stranger', async () => {
  await assertSucceeds(setDoc(doc(as(A), `partnerCards/${A}/cards/p1`), card('p1')));
  // Before approval: closed.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `partnerships/${PAIR}`), {
      uids: [A, B], fromUid: A, toUid: B, status: 'pending', names: {},
    });
  });
  await assertFails(getDoc(doc(as(B), `partnerCards/${A}/cards/p1`)));
  await activate();
  await assertSucceeds(getDocs(collection(as(B), `partnerCards/${A}/cards`)));
  await assertFails(getDocs(collection(as(C), `partnerCards/${A}/cards`)));
  // View only.
  await assertFails(setDoc(doc(as(B), `partnerCards/${A}/cards/p2`), card('p2')));
  // No phone, no notes.
  await assertFails(
    setDoc(doc(as(A), `partnerCards/${A}/cards/p3`), card('p3', { phone: '0501234567' })),
  );
});

test('an idea between partners opens at once, without a request', async () => {
  await activate();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `partnerCards/${B}/cards/t1`), card('t1', { ownerUid: B }));
  });
  const proposal = {
    fromUid: A, toUid: B, uids: [A, B], fromName: 'א', toName: 'ב',
    status: 'approved',
    target: { personId: 't1', firstName: 'נועה' },
    candidate: { personId: 'c1', firstName: 'דוד', description: '', photoPaths: [] },
    note: '', sides: {}, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(as(A), 'ideaProposals/x1'), proposal));
  // A stranger cannot open one as approved.
  await assertFails(
    setDoc(doc(as(C), 'ideaProposals/x2'), {
      ...proposal, fromUid: C, uids: [C, B],
    }),
  );
});
