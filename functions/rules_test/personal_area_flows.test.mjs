import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeApp as adminApp,
  deleteApp as deleteAdmin,
} from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth as adminAuth } from 'firebase-admin/auth';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  getAuth,
  connectAuthEmulator,
  createUserWithEmailAndPassword,
} from 'firebase/auth';
import {
  getFunctions,
  connectFunctionsEmulator,
  httpsCallable,
} from 'firebase/functions';
import { notify } from '../lib/notices.js';
let db, owner, target, stranger, unverified, admin;
const apps = [],
  projectId = 'demo-shadchan';
async function account(label, verified = true) {
  const app = initializeApp(
    { projectId, apiKey: 'demo-key' },
    `personal-${label}`,
  );
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const { user } = await createUserWithEmailAndPassword(
    auth,
    `personal-${label}-${Date.now()}@example.com`,
    'test-password-123',
  );
  if (verified) {
    await adminAuth().updateUser(user.uid, { emailVerified: true });
    await user.getIdToken(true);
  }
  const functions = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  return {
    uid: user.uid,
    email: user.email,
    call: async (name, data = {}) =>
      (await httpsCallable(functions, name)(data)).data,
  };
}
async function waitFor(fn, label) {
  const end = Date.now() + 40000;
  while (Date.now() < end) {
    const result = await fn();
    if (result) return result;
    await new Promise((r) => setTimeout(r, 150));
  }
  assert.fail(`Timed out: ${label}`);
}
const card = (uid, extra = {}) => ({
  ownerUid: uid,
  firstName: 'יעל',
  lastName: 'לוי',
  gender: 'female',
  description: 'א'.repeat(40),
  photoPaths: [],
  deleted: false,
  status: 'available',
  updatedAt: Timestamp.now(),
  ...extra,
});
const rows = async (uid, kind) =>
  (await db.collection(`users/${uid}/inbox`).where('kind', '==', kind).get())
    .docs;
before(async () => {
  admin = adminApp({ projectId, storageBucket: `${projectId}.appspot.com` });
  db = getFirestore();
  owner = await account('owner');
  target = await account('target');
  stranger = await account('stranger');
  unverified = await account('unverified', false);
  await db.doc(`personalCards/${owner.uid}`).set(card(owner.uid));
});
after(async () => {
  await Promise.all(apps.map(deleteApp));
  await db.terminate();
  await deleteAdmin(admin);
});

test('reciprocal discovery and join notifications never reveal a one-way contact or card details', async () => {
  const oh = '1'.repeat(24),
    th = '2'.repeat(24);
  await db
    .doc(`phoneDirectory/${oh}`)
    .set({ uid: owner.uid, name: 'יעל', matchmaker: false, hasCard: true });
  await db
    .doc(`phoneDirectory/${th}`)
    .set({ uid: target.uid, name: 'אורי', matchmaker: true, hasCard: true });
  await db
    .doc(`personalCards/${target.uid}`)
    .set(card(target.uid, { description: 'פרטים שאסור לחשוף'.repeat(4) }));
  await db.doc(`userPhones/${owner.uid}`).set({ phoneHash: oh });
  await db.doc(`userPhones/${target.uid}`).set({ phoneHash: th });
  await db.doc(`contactHashes/${owner.uid}`).set({ hashes: [th] });
  await waitFor(
    async () =>
      (await db.doc(`users/${owner.uid}/private/helpers`).get()).exists,
    'initial discovery',
  );
  assert.equal(
    (await db.doc(`users/${owner.uid}/private/helpers`).get()).get('helpers')
      .length,
    0,
  );
  assert.equal((await rows(owner.uid, 'friendJoined')).length, 0);
  await db.doc(`contactHashes/${target.uid}`).set({ hashes: [oh] });
  const cache = await waitFor(async () => {
    const d = await db.doc(`users/${owner.uid}/private/helpers`).get();
    return d.get('helpers')?.length === 1 && d;
  }, 'reciprocal helpers');
  assert.equal(cache.get('friends').length, 1);
  await db
    .doc(`matchmakerActivity/${target.uid}`)
    .set({ databaseCount: 17, lastActiveAt: Timestamp.now() });
  await waitFor(
    async () =>
      (await db.doc(`users/${owner.uid}/private/helpers`).get()).get(
        'helpers',
      )?.[0]?.databaseCount === 17,
    'actual helper activity metadata',
  );
  assert.deepEqual(Object.keys(cache.get('friends')[0]).sort(), [
    'name',
    'phoneHash',
    'uid',
  ]);
  await waitFor(
    async () => (await rows(owner.uid, 'friendJoined')).length === 1,
    'in-app join notice',
  );
  await db.doc(`contactHashes/${target.uid}`).set({ hashes: [] });
  await waitFor(async () => {
    const d = await db.doc(`users/${owner.uid}/private/helpers`).get();
    return d.get('helpers')?.length === 0 && d.get('friends')?.length === 0;
  }, 'remove one-way relationship');
});

test('an invitation is bound to the verified recipient and cannot be forwarded or replayed after revocation', async () => {
  const invite = await owner.call('createPersonalInvite', {
    email: target.email,
  });
  const token = new URL(invite.url).searchParams.get('personalInvite');
  await assert.rejects(
    stranger.call('redeemPersonalInvite', { token }),
    /חשבון אחר/,
  );
  await assert.rejects(
    unverified.call('redeemPersonalInvite', { token }),
    /מאומת/,
  );
  const result = await target.call('redeemPersonalInvite', { token });
  assert.equal(result.ownerUid, owner.uid);
  const accessRef = db.doc(`cardAccess/${owner.uid}_${target.uid}`);
  const grant = await accessRef.get();
  assert.equal(grant.get('status'), 'approved');
  assert.equal(grant.get('lookingGranted'), false);
  assert.deepEqual(grant.get('granteeUids'), [target.uid]);
  await waitFor(
    async () => (await rows(target.uid, 'accessApproved')).length > 0,
    'access approval notice',
  );
  await accessRef.update({ status: 'revoked', cardGranted: false });
  const retry = await target.call('redeemPersonalInvite', { token });
  assert.equal(retry.alreadyUsed, true);
  assert.equal((await accessRef.get()).get('status'), 'revoked');
  await owner.call('revokePersonalInvite', { id: invite.id });
  await assert.rejects(target.call('redeemPersonalInvite', { token }), /פעילה/);
});

test('expired invitations and paired recipients cannot silently expand access', async () => {
  const expired = await owner.call('createPersonalInvite', {
    email: target.email,
  });
  await db
    .doc(`personalInvites/${expired.id}`)
    .update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await assert.rejects(
    target.call('redeemPersonalInvite', {
      token: new URL(expired.url).searchParams.get('personalInvite'),
    }),
    /פעילה/,
  );
  const invite = await owner.call('createPersonalInvite', {
    email: target.email,
  });
  await db
    .doc(`memberships/${target.uid}`)
    .set({
      databaseUid: target.uid,
      members: [target.uid, stranger.uid],
      state: 'active',
    });
  await assert.rejects(
    target.call('redeemPersonalInvite', {
      token: new URL(invite.url).searchParams.get('personalInvite'),
    }),
    /זוגי/,
  );
  await db.doc(`memberships/${target.uid}`).delete();
});

test('status and card edits are silent; a separate status time survives ordinary edits and review confirmation', async () => {
  const ref = db.doc(`personalCards/${owner.uid}`);
  const before = (await ref.get()).updateTime.toMillis();
  await ref.update({ status: 'busy', updatedAt: Timestamp.now() });
  const statusTime = await waitFor(async () => {
    const t = (await ref.get()).get('statusUpdatedAt');
    return t?.toMillis() > before && t;
  }, 'status timestamp');
  await ref.update({ city: 'ירושלים', updatedAt: Timestamp.now() });
  await waitFor(
    async () =>
      (await db.doc(`users/${owner.uid}/private/cardActivity`).get())
        .get('editedAt')
        ?.toMillis() > statusTime.toMillis(),
    'ordinary edit time',
  );
  assert.equal(
    (await ref.get()).get('statusUpdatedAt').toMillis(),
    statusTime.toMillis(),
  );
  assert.equal((await rows(target.uid, 'cardUpdated')).length, 0);
  assert.equal((await rows(target.uid, 'mazelTov')).length, 0);
  await owner.call('confirmPersonalCardCurrent');
  assert.ok(
    (await db.doc(`users/${owner.uid}/private/cardActivity`).get()).get(
      'reviewedAt',
    ),
  );
  assert.equal(
    (await ref.get()).get('statusUpdatedAt').toMillis(),
    statusTime.toMillis(),
  );
});

test('private wishes edits reset the review clock without changing the public status timestamp', async () => {
  const cardRef = db.doc(`personalCards/${owner.uid}`);
  const status = (await cardRef.get()).get('statusUpdatedAt').toMillis();
  const reviewed = (
    await db.doc(`users/${owner.uid}/private/cardActivity`).get()
  )
    .get('reviewedAt')
    .toMillis();
  await owner.call('savePrivateLooking', {
    text: 'פירוט פרטי לשדכנים בלבד',
    audioPath: null,
  });
  await waitFor(
    async () =>
      (await db.doc(`users/${owner.uid}/private/cardActivity`).get())
        .get('editedAt')
        ?.toMillis() > reviewed,
    'private edit review clock',
  );
  assert.equal((await cardRef.get()).get('statusUpdatedAt').toMillis(), status);
  assert.equal((await cardRef.get()).get('privateLooking'), undefined);
});

test('explicit reminders are atomic, monthly and delivered only to current card grantees', async () => {
  await db
    .doc(`cardAccess/${owner.uid}_${target.uid}`)
    .update({ status: 'approved', cardGranted: true });
  await db
    .doc(`cardAccess/${owner.uid}_${stranger.uid}`)
    .set({
      ownerUid: owner.uid,
      matchmakerUid: stranger.uid,
      status: 'approved',
      cardGranted: false,
      lookingGranted: true,
    });
  const results = await Promise.allSettled([
    owner.call('remindMyMatchmakers'),
    owner.call('remindMyMatchmakers'),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const notices = await waitFor(async () => {
    const n = await rows(target.uid, 'cardUpdated');
    return n.length && n;
  }, 'explicit reminder');
  assert.equal(notices.length, 1);
  assert.match(notices[0].get('title'), /עדכנה את הכרטיס/);
  assert.ok(!JSON.stringify(notices[0].data()).includes('busy'));
  assert.equal((await rows(stranger.uid, 'cardUpdated')).length, 0);
  await assert.rejects(owner.call('remindMyMatchmakers'), /30/);
  await db
    .doc(`users/${owner.uid}/private/cardActivity`)
    .update({ nudgedAt: Timestamp.fromMillis(Date.now() - 31 * 86400000) });
  await owner.call('remindMyMatchmakers');
  await waitFor(
    async () => (await rows(target.uid, 'cardUpdated')).length === 2,
    'cooldown expires',
  );
});

test('admin news integrates with the persistent inbox and supports edits and deletion without duplicate alerts', async () => {
  const ref = db.doc('personalNews/personal-test-news');
  await ref.set({
    title: 'עדכון קהילה',
    text: 'שלום לרווקים',
    imagePath: null,
    published: true,
    notify: true,
    updatedAt: Timestamp.now(),
  });
  const inboxRef = db.doc(
    `users/${owner.uid}/inbox/personalNews_personal-test-news`,
  );
  await waitFor(async () => (await inboxRef.get()).exists, 'admin news inbox');
  await inboxRef.update({ read: true });
  await ref.update({ text: 'טקסט מעודכן', updatedAt: Timestamp.now() });
  await waitFor(
    async () => (await inboxRef.get()).get('body') === 'טקסט מעודכן',
    'edited news',
  );
  assert.equal((await inboxRef.get()).get('read'), true);
  assert.equal((await rows(owner.uid, 'personalNews')).length, 1);
  await ref.delete();
  await waitFor(async () => !(await inboxRef.get()).exists, 'deleted news');
});

test('community totals are computed from actual active cards, with no public candidate roster', async () => {
  const expected = (await db.collection('personalCards').get()).docs.filter(
    (d) =>
      !d.get('deleted') &&
      (d.get('photoPaths')?.length > 0 ||
        [...(d.get('description') ?? '').trim()].length >= 30),
  ).length;
  const stats = await waitFor(async () => {
    const d = await db.doc('publicStats/personalArea').get();
    return d.get('singles') === expected && d;
  }, 'verified community count');
  assert.equal(stats.get('singles'), expected);
  assert.equal(typeof stats.get('weekKey'), 'string');
  assert.equal(stats.get('names'), undefined);
});

test('delayed announcement delivery rechecks publication and uses current text inside its transaction', async () => {
  const newsId = 'stale-delivery-test',
    ref = db.doc(`personalNews/${newsId}`);
  const inbox = db.doc(`users/${owner.uid}/inbox/stale_delivery`);
  const notice = {
    kind: 'personalNews',
    newsId,
    title: 'כותרת ישנה',
    body: 'טקסט ישן',
    route: `/me/news/${newsId}`,
  };
  await ref.set({
    title: 'כותרת עדכנית',
    text: 'תוכן עדכני',
    imagePath: null,
    published: false,
    notify: true,
    updatedAt: Timestamp.now(),
  });
  await notify(owner.uid, notice, false, inbox.id);
  assert.equal((await inbox.get()).exists, false);
  await ref.update({ published: true, updatedAt: Timestamp.now() });
  await notify(owner.uid, notice, false, inbox.id);
  assert.equal((await inbox.get()).get('body'), 'תוכן עדכני');
  await ref.delete();
  await waitFor(
    async () => !(await inbox.get()).exists,
    'remove current inbox entry',
  );
  await notify(owner.uid, notice, false, inbox.id);
  assert.equal((await inbox.get()).exists, false);
});
