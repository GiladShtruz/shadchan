// Security rules for sharing between matchmakers — published cards that
// name their readers, idea proposals and chats — run against the Firestore
// emulator:
//
//   cd functions && npm run test:rules
//
// A card is read only by the matchmakers it names, a single's own card is
// shared only with their consent, and each side of an idea writes only its
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
  query,
  where,
  serverTimestamp,
  writeBatch,
  increment,
} from 'firebase/firestore';

const A = 'mmA'; // shares
const B = 'mmB'; // A shares with B
const C = 'mmC'; // nothing with A
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
    await setDoc(doc(db, `matchmakerShares/${A}_${B}`), {
      ownerUid: A, readerUid: B, uids: [A, B], mode: 'all', count: 1,
      ownerName: 'A', readerName: 'B',
    });
    await setDoc(doc(db, `cardAccess/${S}_${A}`), {
      ownerUid: S, matchmakerUid: A, status: 'approved', cardGranted: true,
    });
    await setDoc(doc(db, `networkCards/${A}_p1`), card('p1'));
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
    readers: [B], nameKey: 'נועה כהן',
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

test('a published card is read by the readers it names, not by a stranger', async () => {
  await assertSucceeds(getDoc(doc(as(B), `networkCards/${A}_p1`)));
  await assertSucceeds(
    getDocs(query(collection(as(B), 'networkCards'), where('readers', 'array-contains', B))),
  );
  await assertFails(getDoc(doc(as(C), `networkCards/${A}_p1`)));
  // Nobody lists anybody's whole database.
  await assertFails(getDocs(collection(as(B), 'networkCards')));
  await assertFails(
    getDocs(query(collection(as(C), 'networkCards'), where('ownerUid', '==', A))),
  );
  await assertSucceeds(
    getDocs(query(collection(as(A), 'networkCards'), where('ownerUid', '==', A))),
  );
});

test('taking a reader off the card ends the reading at once', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `networkCards/${A}_p1`), { readers: ['someoneElse'] });
  });
  await assertFails(getDoc(doc(as(B), `networkCards/${A}_p1`)));
});

test('only the owner shares, only a complete card, and never a phone', async () => {
  await assertSucceeds(setDoc(doc(as(A), `networkCards/${A}_p2`), card('p2')));
  await assertFails(setDoc(doc(as(B), `networkCards/${A}_p3`), card('p3')));
  await assertFails(setDoc(doc(as(A), `networkCards/${A}_p4`), card('p4', { photoPaths: [] })));
  await assertFails(setDoc(doc(as(A), `networkCards/${A}_p5`), card('p5', { description: '' })));
  await assertFails(setDoc(doc(as(A), `networkCards/${A}_p6`), card('p6', { phone: '0501234567' })));
  await assertFails(setDoc(doc(as(A), `networkCards/${A}_p7`), card('p7', { notes: 'פרטי' })));
  // A card with no reader is not published at all.
  await assertFails(setDoc(doc(as(A), `networkCards/${A}_p9`), card('p9', { readers: [] })));
  // The id is always owner_person.
  await assertFails(setDoc(doc(as(A), `networkCards/${B}_p2`), card('p2')));
});

test("a single's own card is shared only with the single's consent", async () => {
  await assertFails(
    setDoc(doc(as(A), `networkCards/${A}_p8`), card('p8', { cardOwnerUid: S })),
  );
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `cardAccess/${S}_${A}`), { shareOnward: true });
  });
  await assertSucceeds(
    setDoc(doc(as(A), `networkCards/${A}_p8`), card('p8', { cardOwnerUid: S })),
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

test('an idea is offered only for a card shared with the one offering it', async () => {
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
  // Agreed is not open yet: either side opens it when they ask the friends.
  await assertSucceeds(
    updateDoc(doc(as(B), 'ideaProposals/x1'), { status: 'opened', updatedAt: serverTimestamp() }),
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

test('approving opens the shared idea at once; either side moves the one record', async () => {
  await setDoc(doc(as(B), 'ideaProposals/y1'), proposal());
  const seed = (by, status, extra = {}) => ({
    status, askedMaleAt: null, askedFemaleAt: null, updatedBy: by,
    updatedAt: serverTimestamp(), ...extra,
  });
  // The asked side approves straight into an open idea at "רעיון".
  await assertSucceeds(
    updateDoc(doc(as(A), 'ideaProposals/y1'), {
      status: 'opened', idea: seed(A, 'idea'), updatedAt: serverTimestamp(),
    }),
  );
  // B asked the boy: the one shared record says so, signed by B.
  await assertSucceeds(
    updateDoc(doc(as(B), 'ideaProposals/y1'), {
      idea: seed(B, 'checking', { askedMaleAt: new Date() }),
      [`sides.${B}`]: { status: 'checking' },
      updatedAt: serverTimestamp(),
    }),
  );
  // Never signed in the other's name, never an unknown status.
  await assertFails(
    updateDoc(doc(as(A), 'ideaProposals/y1'), {
      idea: seed(B, 'dating'), updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(as(A), 'ideaProposals/y1'), {
      idea: seed(A, 'whatever'), updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(as(A), 'ideaProposals/y1'), {
      idea: seed(A, 'dating'), updatedAt: serverTimestamp(),
    }),
  );
});

function chat(extra = {}) {
  return {
    members: [A, B], type: 'direct',
    names: { [A]: 'A', [B]: 'B' },
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...extra,
  };
}

// What `ChatService.send` writes: the conversation as a merge, and the
// message, in one batch — a create the first time, an update after.
function sendBatch(db, from, to, id, text, extra = {}) {
  const pair = [from, to].sort();
  const chatId = `${pair[0]}_${pair[1]}`;
  const batch = writeBatch(db);
  batch.set(
    doc(db, `chats/${chatId}`),
    {
      members: pair, type: 'direct', names: { [from]: from },
      lastText: text || '🎤', lastType: extra.type ?? 'text', lastFromUid: from,
      lastAt: serverTimestamp(), readAt: { [from]: serverTimestamp() },
      unread: { [from]: 0, [to]: increment(1) },
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(doc(db, `chats/${chatId}/messages/${id}`), {
    fromUid: from, type: 'text', text, at: serverTimestamp(), ...extra,
  });
  return batch.commit();
}

test('a chat is opened between matchmakers who share and read by its members', async () => {
  await assertSucceeds(sendBatch(as(B), B, A, 'm0', 'שלום'));
  await assertFails(sendBatch(as(C), C, A, 'x', 'שלום'));
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
  // Each member marks only their own reading, and zeroes only their own count.
  await assertSucceeds(
    setDoc(doc(as(A), `chats/${PAIR}`), {
      readAt: { [A]: serverTimestamp() }, unread: { [A]: 0 }, updatedAt: serverTimestamp(),
    }, { merge: true }),
  );
  await assertFails(
    updateDoc(doc(as(A), `chats/${PAIR}`), {
      [`readAt.${B}`]: serverTimestamp(), updatedAt: serverTimestamp(),
    }),
  );
  // A's own message leaves one unread for B — which only B may clear.
  await assertSucceeds(sendBatch(as(A), A, B, 'm4', 'ענית?'));
  await assertFails(
    updateDoc(doc(as(A), `chats/${PAIR}`), { [`unread.${B}`]: 0, updatedAt: serverTimestamp() }),
  );
  // Nobody inflates the other's count without sending.
  await assertFails(
    updateDoc(doc(as(A), `chats/${PAIR}`), { [`unread.${B}`]: 5, updatedAt: serverTimestamp() }),
  );
});

test('the same send writes again to an existing chat, unread grows by one', async () => {
  await assertSucceeds(sendBatch(as(A), A, B, 'a1', 'שלום'));
  await assertSucceeds(sendBatch(as(A), A, B, 'a2', 'מה שלומך?'));
  let snap;
  await env.withSecurityRulesDisabled(async (ctx) => {
    snap = await getDoc(doc(ctx.firestore(), `chats/${PAIR}`));
  });
  if (snap.data().unread[B] !== 2) throw new Error(`unread ${snap.data().unread[B]}`);
});

test('once a chat exists it stays a chat after sharing stops', async () => {
  await assertSucceeds(sendBatch(as(B), B, A, 'm0', 'שלום'));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `matchmakerShares/${A}_${B}`), { mode: 'none' });
  });
  await assertSucceeds(getDoc(doc(as(A), `chats/${PAIR}`)));
  await assertSucceeds(sendBatch(as(A), A, B, 'm3', 'עדיין כאן'));
});

test('a single and the matchmaker who keeps their card share one chat; a stranger cannot start one', async () => {
  const id = [S, A].sort().join('_');
  await assertSucceeds(sendBatch(as(S), S, A, 'm1', 'היי'));
  await assertSucceeds(sendBatch(as(A), A, S, 'm2', 'שלום'));
  await assertSucceeds(getDoc(doc(as(S), `chats/${id}/messages/m2`)));
  // No card between them, not connected, not in contacts.
  await assertFails(sendBatch(as(S), S, C, 'x', 'היי'));
  // Access revoked later: the conversation goes on.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `cardAccess/${S}_${A}`), { status: 'revoked' });
  });
  await assertSucceeds(sendBatch(as(A), A, S, 'm3', 'עדיין כאן'));
});

test('photos and voice messages carry their file; empty text only with media', async () => {
  await assertSucceeds(
    sendBatch(as(A), A, B, 'v1', '', {
      type: 'voice', media: { path: `chats/${PAIR}/abc123.m4a`, durationMs: 4000, size: 1000, mime: 'audio/mp4' },
    }),
  );
  await assertFails(sendBatch(as(A), A, B, 'v2', '', { type: 'voice' }));
  await assertFails(sendBatch(as(A), A, B, 'v3', ''));
  // A file of another conversation is not this one's.
  await assertFails(
    sendBatch(as(A), A, B, 'v4', '', {
      type: 'image', media: { path: `chats/${A}_${C}/x1.jpg` },
    }),
  );
});

test('"יש לי רעיון בשבילך": only the single answers, once', async () => {
  const id = [S, A].sort().join('_');
  await assertSucceeds(
    sendBatch(as(A), A, S, 'o1', 'יש לי רעיון בשבילך', {
      type: 'ideaOffer', offer: { personId: 'p9', name: 'אורי לוי', summary: '27' },
      ref: { kind: 'card', id: 'p9', ownerUid: A, label: 'אורי לוי' },
    }),
  );
  await assertFails(
    updateDoc(doc(as(A), `chats/${id}/messages/o1`), { answer: 'approved', answeredAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(doc(as(S), `chats/${id}/messages/o1`), {
      answer: 'declined', answerReason: 'לא מתאים לי', answeredAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(as(S), `chats/${id}/messages/o1`), { answer: 'approved', answeredAt: serverTimestamp() }),
  );
});

test('a matchmaker may send a candidate card to a single tied by a card', async () => {
  const path = `sentCards/${A}/to/${S}/cards/s9`;
  await assertSucceeds(setDoc(doc(as(A), path), card('s9')));
  await assertSucceeds(getDoc(doc(as(S), path)));
  await assertFails(setDoc(doc(as(C), `sentCards/${C}/to/${S}/cards/s9`), card('s9')));
});

test('a card sent in a chat is read only by the matchmaker it was sent to', async () => {
  const path = `sentCards/${A}/to/${B}/cards/s1`;
  await assertSucceeds(setDoc(doc(as(A), path), card('s1')));
  await assertSucceeds(getDoc(doc(as(B), path)));
  await assertSucceeds(getDocs(collection(as(B), `sentCards/${A}/to/${B}/cards`)));
  await assertFails(getDoc(doc(as(C), path)));
  // Never to a matchmaker A neither shares with nor knows, never by another.
  await assertFails(setDoc(doc(as(A), `sentCards/${A}/to/${C}/cards/s2`), card('s2')));
  await assertFails(setDoc(doc(as(B), `sentCards/${A}/to/${B}/cards/s3`), card('s3')));
  // The same whitelist as a shared card.
  await assertFails(
    setDoc(doc(as(A), `sentCards/${A}/to/${B}/cards/s4`), card('s4', { phone: '0501234567' })),
  );
});

test('an idea may be offered for a card that was sent, not only shared', async () => {
  await assertSucceeds(setDoc(doc(as(A), `sentCards/${A}/to/${B}/cards/s1`), card('s1')));
  await assertSucceeds(
    setDoc(doc(as(B), 'ideaProposals/y1'), proposal({ target: { personId: 's1', firstName: 'נועה' } })),
  );
  // Sent to B — so C cannot offer anything for it.
  await assertFails(
    setDoc(
      doc(as(C), 'ideaProposals/y2'),
      proposal({ fromUid: C, uids: [C, A], target: { personId: 's1' } }),
    ),
  );
});
