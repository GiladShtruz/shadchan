// End-to-end server flows of the personal card, against the Firestore and
// Functions emulators — the deployed functions' own code, triggered by the
// same writes the app makes:
//
//   cd functions && npm run test:flows
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const OWNER = 'ownerA';
const MM = 'mmA';
const OWNER_HASH = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const MM_HASH = 'bbbbbbbbbbbbbbbbbbbbbbbb';

let db;

before(() => {
  initializeApp({ projectId: 'demo-shadchan' });
  db = getFirestore();
});

async function waitFor(check, what, timeoutMs = 20000) {
  const started = Date.now();
  for (;;) {
    const value = await check();
    if (value) {
      return value;
    }
    if (Date.now() - started > timeoutMs) {
      assert.fail(`timed out waiting for ${what}`);
    }
    await new Promise((r) => setTimeout(r, 400));
  }
}

async function inbox(uid, kind) {
  const snap = await db.collection('users').doc(uid).collection('inbox').get();
  return snap.docs.map((d) => d.data()).find((d) => d.kind === kind);
}

function card(extra = {}) {
  return {
    ownerUid: OWNER,
    firstName: 'נועה',
    lastName: 'כהן',
    gender: 'female',
    dateOfBirth: '1999-04-07',
    status: 'available',
    deleted: false,
    photoPaths: [],
    description: 'א'.repeat(30),
    updatedAt: new Date(),
    ...extra,
  };
}

test('a reciprocal address book finds the matchmakers in it', async () => {
  await db.collection('phoneDirectory').doc(MM_HASH).set({
    uid: MM,
    name: 'יצחק',
    matchmaker: true,
    hasCard: false,
  });
  await db.doc(`phoneDirectory/${OWNER_HASH}`).set({uid: OWNER, name: 'נועה כהן', matchmaker: false, hasCard: true});
  await db.doc(`userPhones/${MM}`).set({phoneHash: MM_HASH});
  await db.doc(`contactHashes/${MM}`).set({hashes: [OWNER_HASH]});
  await db.collection('userPhones').doc(OWNER).set({ phoneHash: OWNER_HASH });
  await db.collection('contactHashes').doc(OWNER).set({
    hashes: [MM_HASH, 'cccccccccccccccccccccccc'],
  });
  const helpers = await waitFor(async () => {
    const doc = await db
      .collection('users')
      .doc(OWNER)
      .collection('private')
      .doc('helpers')
      .get();
    return doc.exists && doc.data().helpers?.length ? doc.data().helpers : null;
  }, 'helpers');
  assert.deepEqual(helpers.map(({uid, name, phoneHash}) => ({uid, name, phoneHash})), [{ uid: MM, name: 'יצחק', phoneHash: MM_HASH }]);
});

test('a new card is announced to matchmakers in the owner’s contacts, once', async () => {
  await db.collection('personalCards').doc(OWNER).set(card());
  const notice = await waitFor(() => inbox(MM, 'cardCreated'), 'cardCreated');
  assert.equal(notice.title, 'נועה כהן הוסיפה כרטיס אישי');
  assert.equal(notice.body, 'אפשר לבקש גישה לפרטים');
  assert.equal(notice.ownerUid, OWNER);
  assert.equal(notice.ownerPhoneHash, OWNER_HASH);
});

test('a database-only one-way contact is never told that a candidate has joined', async () => {
  const HOLDER = 'mmC';
  await db.collection('databaseHashes').doc(HOLDER).set({hashes: [OWNER_HASH]});
  await new Promise(r => setTimeout(r, 1200));
  assert.equal(await inbox(HOLDER, 'cardCreated'), undefined);
});

test('a request reaches the owner; an approval reaches the matchmaker', async () => {
  const ref = db.collection('cardAccess').doc(`${OWNER}_${MM}`);
  await ref.set({
    ownerUid: OWNER,
    matchmakerUid: MM,
    status: 'pending',
    requestedBy: 'matchmaker',
    ownerName: 'נועה כהן',
    matchmakerName: 'יצחק',
    updatedAt: new Date(),
  });
  const request = await waitFor(() => inbox(OWNER, 'accessRequest'), 'request');
  assert.match(request.body, /יצחק/);
  assert.equal(request.route, '/me?section=requests');

  await ref.update({ status: 'approved', updatedAt: new Date() });
  const approved = await waitFor(() => inbox(MM, 'accessApproved'), 'approved');
  assert.equal(approved.title, 'נועה אישרה לך גישה לכרטיס שלה ❤️');
  assert.equal(approved.route, `/card-friend/${OWNER}`);
});

test('internal status reports remain hidden from the owner', async () => {
  await db.collection('statusReports').add({
    ownerUid: OWNER,
    matchmakerUid: MM,
    matchmakerName: 'יצחק',
    status: 'busy',
    resolution: null,
    createdAt: new Date(),
  });
  await new Promise(r => setTimeout(r, 500));
  assert.equal(await inbox(OWNER, 'statusReport'), undefined);
});

test('owner status changes, including a legacy wedding status, send no automatic alert', async () => {
  const before = (await db.doc(`personalCards/${OWNER}`).get()).updateTime.toMillis();
  await db.collection('personalCards').doc(OWNER).update({status: 'mazelTov'});
  await waitFor(async () => (await db.doc(`personalCards/${OWNER}`).get()).get('statusUpdatedAt')?.toMillis() > before, 'status timestamp');
  await new Promise(r => setTimeout(r, 600));
  assert.equal(await inbox(MM, 'mazelTov'), undefined);
});

test('a declined request is answered gently', async () => {
  const OTHER = 'mmB';
  const ref = db.collection('cardAccess').doc(`${OWNER}_${OTHER}`);
  await ref.set({
    ownerUid: OWNER,
    matchmakerUid: OTHER,
    status: 'pending',
    requestedBy: 'matchmaker',
    ownerName: 'נועה כהן',
    matchmakerName: 'משה',
    updatedAt: new Date(),
  });
  await new Promise((r) => setTimeout(r, 1500));
  await ref.update({ status: 'declined', updatedAt: new Date() });
  const notice = await waitFor(() => inbox(OTHER, 'accessDeclined'), 'declined');
  assert.equal(notice.body, 'הבקשה לגישה לכרטיס של נועה כהן לא אושרה');
});
