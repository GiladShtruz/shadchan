// Security rules for the network between connected matchmakers — shared
// cards, idea proposals and chats — run against the Firestore emulator:
//
//   cd functions && npm run test:rules
//
// Everything here is readable only across an approved connection, a single's
// own card only with their consent, and each side of an idea writes only its
// own half.
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

const A = 'mmA'; // shares
const B = 'mmB'; // connected to A
const C = 'mmC'; // not connected
const S = 'single1'; // a single with a personal card
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
    await setDoc(doc(db, `matchmakerConnections/${PAIR}`), {
      uids: [A, B], fromUid: A, toUid: B, status: 'approved',
      names: { [A]: 'A', [B]: 'B' },
    });
    await setDoc(doc(db, `cardAccess/${S}_${A}`), {
      ownerUid: S, matchmakerUid: A, status: 'approved', cardGranted: true,
    });
    await setDoc(doc(db, `sharedCards/${A}/cards/p1`), card('p1'));
  });
});

function as(uid) {
  return env
    .authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } })
    .firestore();
}

function card(personId, extra = {}) {
  return {
    ownerUid: A, ownerName: 'A', personId,
    firstName: 'נועה', lastName: 'כהן', gender: 'female', age: 25,
    description: 'כרטיס מלא', photoPaths: [`sharedCards/${A}/${personId}/1.jpg`],
    tags: [], status: 'available', identity: null, cardOwnerUid: null,
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

test('a shared card is read by a connected matchmaker, not by a stranger', async () => {
  await assertSucceeds(getDoc(doc(as(B), `sharedCards/${A}/cards/p1`)));
  await assertSucceeds(getDocs(collection(as(B), `sharedCards/${A}/cards`)));
  await assertFails(getDoc(doc(as(C), `sharedCards/${A}/cards/p1`)));
  await assertFails(getDocs(collection(as(C), `sharedCards/${A}/cards`)));
});

test('ending the connection ends the reading', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `matchmakerConnections/${PAIR}`), { status: 'declined' });
  });
  await assertFails(getDocs(collection(as(B), `sharedCards/${A}/cards`)));
});

test('only the owner shares, only a complete card, and never a phone', async () => {
  await assertSucceeds(setDoc(doc(as(A), `sharedCards/${A}/cards/p2`), card('p2')));
  await assertFails(setDoc(doc(as(B), `sharedCards/${A}/cards/p3`), card('p3')));
  await assertFails(setDoc(doc(as(A), `sharedCards/${A}/cards/p4`), card('p4', { photoPaths: [] })));
  await assertFails(setDoc(doc(as(A), `sharedCards/${A}/cards/p5`), card('p5', { description: '' })));
  await assertFails(setDoc(doc(as(A), `sharedCards/${A}/cards/p6`), card('p6', { phone: '0501234567' })));
  await assertFails(setDoc(doc(as(A), `sharedCards/${A}/cards/p7`), card('p7', { notes: 'פרטי' })));
});

test("a single's own card is shared only with the single's consent", async () => {
  await assertFails(
    setDoc(doc(as(A), `sharedCards/${A}/cards/p8`), card('p8', { cardOwnerUid: S })),
  );
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `cardAccess/${S}_${A}`), { shareOnward: true });
  });
  await assertSucceeds(
    setDoc(doc(as(A), `sharedCards/${A}/cards/p8`), card('p8', { cardOwnerUid: S })),
  );
});

test('a matchmaker may ask for onward consent, but only the single gives it', async () => {
  await assertSucceeds(
    updateDoc(doc(as(A), `cardAccess/${S}_${A}`), {
      shareOnwardRequested: true, updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(as(A), `cardAccess/${S}_${A}`), {
      shareOnward: true, updatedAt: serverTimestamp(),
    }),
  );
});

function proposal(extra = {}) {
  return {
    fromUid: B, toUid: A, uids: [B, A], fromName: 'B', toName: 'A',
    status: 'pending',
    target: { personId: 'p1', firstName: 'נועה' },
    candidate: { personId: 'q1', firstName: 'דוד', description: 'כרטיס', photoPaths: [] },
    note: '', sides: {},
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...extra,
  };
}

test('an idea is offered only across a connection, for a shared card', async () => {
  await assertSucceeds(setDoc(doc(as(B), 'ideaProposals/x1'), proposal()));
  await assertFails(
    setDoc(doc(as(C), 'ideaProposals/x2'), proposal({ fromUid: C, uids: [C, A] })),
  );
  await assertFails(
    setDoc(doc(as(B), 'ideaProposals/x3'), proposal({ target: { personId: 'nope' } })),
  );
  await assertFails(setDoc(doc(as(B), 'ideaProposals/x4'), proposal({ status: 'approved' })));
});

test('only the side asked answers; each side writes only its own half', async () => {
  await setDoc(doc(as(B), 'ideaProposals/x1'), proposal());
  await assertFails(
    updateDoc(doc(as(B), 'ideaProposals/x1'), { status: 'approved', updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(doc(as(A), 'ideaProposals/x1'), { status: 'approved', updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(doc(as(A), 'ideaProposals/x1'), {
      [`sides.${A}`]: { status: 'checking' }, updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(as(A), 'ideaProposals/x1'), {
      [`sides.${B}`]: { status: 'checking' }, updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(getDoc(doc(as(C), 'ideaProposals/x1')));
});

function chat(extra = {}) {
  return {
    members: [A, B], type: 'direct', kind: 'matchmakers',
    names: { [A]: 'A', [B]: 'B' },
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...extra,
  };
}

test('a chat is opened between connected matchmakers and read by its members', async () => {
  await assertSucceeds(setDoc(doc(as(B), `chats/${PAIR}`), chat()));
  await assertFails(
    setDoc(doc(as(C), `chats/${A}_${C}`), chat({ members: [A, C] })),
  );
  await assertSucceeds(
    setDoc(doc(as(B), `chats/${PAIR}/messages/m1`), {
      fromUid: B, text: 'שלום', at: serverTimestamp(),
      ref: { kind: 'card', id: 'p1', ownerUid: A, label: 'נועה כהן' },
    }),
  );
  await assertSucceeds(getDoc(doc(as(A), `chats/${PAIR}/messages/m1`)));
  await assertFails(getDoc(doc(as(C), `chats/${PAIR}/messages/m1`)));
  // Nobody writes in somebody else's name.
  await assertFails(
    setDoc(doc(as(B), `chats/${PAIR}/messages/m2`), {
      fromUid: A, text: 'x', at: serverTimestamp(),
    }),
  );
  // Each member marks only their own reading.
  await assertSucceeds(
    updateDoc(doc(as(A), `chats/${PAIR}`), {
      [`readAt.${A}`]: serverTimestamp(), updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(as(A), `chats/${PAIR}`), {
      [`readAt.${B}`]: serverTimestamp(), updatedAt: serverTimestamp(),
    }),
  );
});

test('after a disconnect the chat stays readable but takes no new messages', async () => {
  await setDoc(doc(as(B), `chats/${PAIR}`), chat());
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `matchmakerConnections/${PAIR}`), { status: 'declined' });
  });
  await assertSucceeds(getDoc(doc(as(A), `chats/${PAIR}`)));
  await assertFails(
    setDoc(doc(as(A), `chats/${PAIR}/messages/m3`), {
      fromUid: A, text: 'שלום', at: serverTimestamp(),
    }),
  );
});
