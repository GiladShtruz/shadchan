import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeApp as initializeAdmin,
  deleteApp as deleteAdmin,
  getApp as getAdminApp,
} from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
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
const projectId = 'demo-shadchan';
let db, a, b, owner;
const apps = [];
async function account(label) {
  const app = initializeApp(
    {
      projectId,
      apiKey: 'demo-key',
      authDomain: `${projectId}.firebaseapp.com`,
    },
    label,
  );
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const credential = await createUserWithEmailAndPassword(
    auth,
    `${label}-${Date.now()}@example.com`,
    'test-password-123',
  );
  const functions = getFunctions(app, 'europe-west1');
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  return {
    uid: credential.user.uid,
    call: async (name, data = {}) =>
      (await httpsCallable(functions, name)(data)).data,
  };
}
async function waitFor(fn, what) {
  const end = Date.now() + 30000;
  while (Date.now() < end) {
    const result = await fn();
    if (result) return result;
    await new Promise((r) => setTimeout(r, 200));
  }
  assert.fail(`Timed out: ${what}`);
}
before(async () => {
  initializeAdmin({ projectId, storageBucket: `${projectId}.appspot.com` });
  db = getFirestore();
  a = await account('moshe');
  b = await account('rachel');
  owner = await account('single');
  for (const [user, name] of [
    [a, 'משה'],
    [b, 'רחל'],
  ])
    await db
      .doc(`users/${user.uid}/settings/userFirstName`)
      .set({ k: 'userFirstName', v: JSON.stringify(name) });
});
after(async () => {
  await Promise.all(apps.map(deleteApp));
  await db.terminate();
  await deleteAdmin(getAdminApp());
});
test('separate accounts merge losslessly, preserve consent, deduplicate phones, then split relevant data', async () => {
  const data = {
    [a.uid]: {
      people: {
        p: {
          phone: '0501234567',
          firstName: 'דוד',
          description: 'ראשון',
          photos: [],
        },
        x: { phone: '0502222222', firstName: 'שרה', photos: [] },
      },
      personNotes: { n: { personId: 'p', text: 'הערה של משה' } },
      matches: {
        m: {
          personAId: 'p',
          personBId: 'x',
          reminderDate: '2026-11-01',
          reminderNote: 'רק משה',
        },
      },
    },
    [b.uid]: {
      people: {
        p: {
          phone: '+972501234567',
          firstName: 'דוד',
          description: 'שני',
          photos: [],
        },
        y: { phone: '0503333333', firstName: 'רבקה', photos: [] },
        z: { phone: '0504444444', firstName: 'לא קשור', photos: [] },
      },
      personNotes: { n: { personId: 'p', text: 'הערה של רחל' } },
      matches: {},
    },
  };
  for (const [uid, collections] of Object.entries(data))
    for (const [c, records] of Object.entries(collections))
      for (const [id, record] of Object.entries(records))
        await db.doc(`users/${uid}/${c}/${id}`).set({ id, ...record });
  await db
    .doc(`cardAccess/${owner.uid}_${a.uid}`)
    .set({
      ownerUid: owner.uid,
      matchmakerUid: a.uid,
      status: 'blocked',
      requestedBy: 'owner',
      ownerName: 'רווק',
      matchmakerName: 'משה',
    });
  await db
    .doc(`cardAccess/${owner.uid}_${b.uid}`)
    .set({
      ownerUid: owner.uid,
      matchmakerUid: b.uid,
      status: 'approved',
      requestedBy: 'owner',
      ownerName: 'רווק',
      matchmakerName: 'רחל',
      lookingGranted: true,
    });
  await assert.rejects(a.call('createCoupleInvite', { married: false }));
  const { code } = await a.call('createCoupleInvite', { married: true });
  const preview = await b.call('previewCoupleInvite', { code });
  assert.match(preview.name, /משה/);
  await b.call('acceptCoupleInvite', {
    code,
    married: true,
    confirmMerge: true,
  });
  assert.equal(
    (await db.doc(`memberships/${b.uid}`).get()).get('databaseUid'),
    a.uid,
  );
  await assert.rejects(b.call('createCoupleInvite', { married: true }));
  // A retry of the completed invitation must not remigrate or duplicate data.
  await b.call('acceptCoupleInvite', {
    code,
    married: true,
    confirmMerge: true,
  });
  let people = (await db.collection(`users/${a.uid}/people`).get()).docs.filter(
    (d) => !d.get('_deleted'),
  );
  assert.equal(people.length, 4);
  const shared = people.find((d) => d.get('phone') === '0501234567');
  assert.deepEqual(new Set(shared.get('_sources')), new Set([a.uid, b.uid]));
  assert.match(shared.get('description'), /ראשון[\s\S]*שני/);
  assert.equal(
    (await db.collection(`users/${a.uid}/personNotes`).get()).docs.filter(
      (d) => !d.get('_deleted'),
    ).length,
    2,
  );
  assert.equal(
    (await db.doc(`cardAccess/${owner.uid}_${a.uid}`).get()).get('status'),
    'blocked',
  );
  assert.equal(
    (await db.doc(`cardAccess/${owner.uid}_${b.uid}`).get()).get(
      'lookingGranted',
    ),
    false,
  );
  const x = people.find((d) => d.get('firstName') === 'שרה').id;
  const y = people.find((d) => d.get('firstName') === 'רבקה').id;
  await db
    .doc(`users/${a.uid}/matches/cross`)
    .set({
      id: 'cross',
      personAId: x,
      personBId: y,
      _sources: [a.uid],
      _actorUid: a.uid,
    });
  await db
    .doc(`users/${a.uid}/matchNotes/history`)
    .set({
      id: 'history',
      matchId: 'cross',
      text: 'היסטוריה מלאה',
      _actorUid: b.uid,
    });
  // Simulate a simultaneous duplicate arriving from another device and a late note.
  await db
    .doc(`users/${a.uid}/people/duplicate`)
    .set({
      id: 'duplicate',
      phone: '+972501234567',
      firstName: 'דוד',
      _sources: [b.uid],
      _actorUid: b.uid,
    });
  await db
    .doc(`users/${a.uid}/personNotes/late`)
    .set({
      id: 'late',
      personId: 'duplicate',
      text: 'לא לאבד',
      _actorUid: b.uid,
    });
  await waitFor(async () => {
    const rows = (
      await db.collection(`users/${a.uid}/people`).get()
    ).docs.filter((d) => !d.get('_deleted'));
    return (
      rows.length === 4 &&
      (await db.doc(`users/${a.uid}/personNotes/late`).get()).get(
        'personId',
      ) !== 'duplicate'
    );
  }, 'same-phone deduplication and late references');
  const split = await a.call('previewCoupleSplit');
  assert.equal(split.sides.length, 2);
  await assert.rejects(a.call('splitCoupleWorkspace', { confirmed: false }));
  await a.call('splitCoupleWorkspace', { confirmed: true });
  for (const user of [a, b]) {
    assert.equal((await db.doc(`memberships/${user.uid}`).get()).exists, false);
    assert.equal(
      (await db.doc(`users/${user.uid}/matches/cross`).get()).get('personBId'),
      y,
    );
    assert.equal(
      (await db.doc(`users/${user.uid}/matchNotes/history`).get()).get('text'),
      'היסטוריה מלאה',
    );
  }
  const left = (await db.collection(`users/${a.uid}/people`).get()).docs.filter(
    (d) => !d.get('_deleted'),
  );
  assert.equal(
    left.some((d) => d.get('firstName') === 'לא קשור'),
    false,
  );
  assert.equal(
    (await db.doc(`users/${a.uid}/settings/couple.reminder.${a.uid}__m`).get())
      .exists,
    true,
  );
  assert.equal(
    (await db.doc(`users/${b.uid}/settings/couple.reminder.${a.uid}__m`).get())
      .exists,
    false,
  );
});
function wav(seconds) {
  const rate = 8000,
    length = rate * seconds,
    b = Buffer.alloc(44 + length, 128);
  b.write('RIFF', 0);
  b.writeUInt32LE(36 + length, 4);
  b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate, 28);
  b.writeUInt16LE(1, 32);
  b.writeUInt16LE(8, 34);
  b.write('data', 36);
  b.writeUInt32LE(length, 40);
  return b;
}
test('private text plus audio is verified on server; long audio and video are refused', async () => {
  const bucket = getStorage().bucket();
  const path = `privateLooking/${owner.uid}/short.wav`;
  await bucket.file(path).save(wav(1), { contentType: 'audio/wav' });
  await owner.call('savePrivateLooking', {
    text: 'טקסט פרטי והקלטה יחד',
    audioPath: path,
  });
  const saved = await db.doc(`privateLooking/${owner.uid}`).get();
  assert.equal(saved.get('audioPath'), path);
  assert.equal(saved.get('durationMs'), 1000);
  assert.equal(saved.get('everFilled'), true);
  const long = `privateLooking/${owner.uid}/long.wav`;
  await bucket.file(long).save(wav(601), { contentType: 'audio/wav' });
  await assert.rejects(
    owner.call('savePrivateLooking', { text: 'לא לדרוס', audioPath: long }),
  );
  assert.equal(
    (await db.doc(`privateLooking/${owner.uid}`).get()).get('text'),
    'טקסט פרטי והקלטה יחד',
  );
  await assert.rejects(
    a.call('savePrivateLooking', { text: 'גנוב', audioPath: path }),
  );
  await owner.call('savePrivateLooking', {
    text: 'גרסה מעודכנת',
    audioPath: null,
  });
  assert.equal(
    (await db.doc(`privateLooking/${owner.uid}`).get()).get('audioPath'),
    null,
  );
});
test('either spouse can resume a partially completed merge from immutable source archives', async () => {
  const c = await account('resume-moshe'),
    d = await account('resume-rachel');
  const { code } = await c.call('createCoupleInvite', { married: true });
  const members = [c.uid, d.uid],
    names = { [c.uid]: 'משה', [d.uid]: 'רחל' };
  for (const uid of members)
    await db
      .doc(`memberships/${uid}`)
      .set({
        databaseUid: c.uid,
        members,
        names,
        name: 'משה ורחל',
        state: 'merging',
        operation: code,
      });
  await db
    .doc(`couples/${c.uid}`)
    .set({
      members,
      names,
      name: 'משה ורחל',
      state: 'merging',
      operation: code,
    });
  await db
    .doc(`coupleInvites/${code}`)
    .update({ acceptedBy: d.uid, status: 'merging', processingUntil: 0 });
  for (const uid of members) {
    const root = `coupleArchives/${code}/accounts/${uid}`;
    await db
      .doc(`${root}/people/original`)
      .set({
        id: 'original',
        firstName: uid === c.uid ? 'אחד' : 'שתיים',
        phone: uid === c.uid ? '0505555555' : '0506666666',
        photos: [],
      });
    await db.doc(root).set({ complete: true });
  }
  await db.doc(`users/${c.uid}/people/original`).set({ _deleted: true });
  await c.call('resumeCoupleMigration');
  assert.equal(
    (await db.doc(`memberships/${d.uid}`).get()).get('state'),
    'active',
  );
  assert.equal(
    (await db.collection(`users/${c.uid}/people`).get()).docs.filter(
      (x) => !x.get('_deleted'),
    ).length,
    2,
  );
  await c.call('splitCoupleWorkspace', { confirmed: true });
});

test('WhatsApp Opus is converted for iOS playback and actual video is rejected', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'shadchan-media-test-'));
  const ffmpeg = require('@ffmpeg-installer/ffmpeg').path;
  try {
    const input = join(folder, 'input.wav'),
      opus = join(folder, 'voice.ogg'),
      video = join(folder, 'video.mp4');
    await writeFile(input, wav(1));
    await promisify(execFile)(ffmpeg, [
      '-v',
      'error',
      '-i',
      input,
      '-c:a',
      'libopus',
      opus,
    ]);
    const path = `privateLooking/${owner.uid}/whatsapp.ogg`;
    await getStorage()
      .bucket()
      .file(path)
      .save(await readFile(opus), { contentType: 'audio/ogg' });
    await owner.call('savePrivateLooking', {
      text: 'מוואטסאפ',
      audioPath: path,
    });
    const result = await db.doc(`privateLooking/${owner.uid}`).get();
    assert.match(result.get('audioPath'), /converted_.*[.]m4a$/);
    assert.equal(result.get('text'), 'מוואטסאפ');
    assert.equal(
      (await getStorage().bucket().file(result.get('audioPath')).exists())[0],
      true,
    );
    await promisify(execFile)(ffmpeg, [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=c=black:s=16x16:d=1',
      '-i',
      input,
      '-t',
      '1',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      video,
    ]);
    const videoPath = `privateLooking/${owner.uid}/video.m4a`;
    await getStorage()
      .bucket()
      .file(videoPath)
      .save(await readFile(video), { contentType: 'audio/mp4' });
    await assert.rejects(
      owner.call('savePrivateLooking', { text: 'אסור', audioPath: videoPath }),
    );
    assert.equal(
      (await db.doc(`privateLooking/${owner.uid}`).get()).get('text'),
      'מוואטסאפ',
    );
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});
