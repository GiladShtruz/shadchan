// Security rules for the personal card, run against the Firestore emulator:
//
//   cd functions && npm run test:rules
//
// Every access decision about a card is the server's (spec item 110), so the
// rules are tested as the thing they are — not through the app.
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
  collection,
  getDocs,
  serverTimestamp,
} from 'firebase/firestore';

const OWNER = 'owner1';
const MM = 'mm1';
const STRANGER = 'stranger1';
const OWNER_HASH = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const MM_HASH = 'bbbbbbbbbbbbbbbbbbbbbbbb';

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

function card(extra = {}) {
  return {
    ownerUid: OWNER,
    firstName: 'דניאל',
    lastName: 'לוי',
    gender: 'male',
    dateOfBirth: '1999-04-07',
    religiousLevel: 'datiLeumi',
    religiousLevelOther: null,
    city: null,
    description: 'אוהב טיולים',
    heightCm: null,
    maritalStatus: 'single',
    region: 'center',
    preferredMinAge: null,
    preferredMaxAge: null,
    preferredMinHeightCm: null,
    preferredMaxHeightCm: null,
    preferredRegions: [],
    preferredMaritalStatuses: [],
    preferredReligiousLevels: [],
    preferredReligiousLevelOtherLabels: [],
    photoPaths: [],
    status: 'available',
    deleted: false,
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

function access(status, extra = {}) {
  return {
    ownerUid: OWNER,
    matchmakerUid: MM,
    status,
    requestedBy: 'matchmaker',
    ownerName: 'דניאל לוי',
    matchmakerName: 'יצחק',
    ownerPhoneHash: OWNER_HASH,
    ownerPhone: null,
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

async function seed(fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

async function seedCardAndContacts({ inContacts }) {
  await seed(async (db) => {
    await setDoc(doc(db, 'personalCards', OWNER), { ...card(), updatedAt: new Date() });
    await setDoc(doc(db, 'userPhones', MM), { phoneHash: MM_HASH });
    await setDoc(doc(db, 'phoneDirectory', MM_HASH), {
      uid: MM,
      name: 'יצחק',
      matchmaker: true,
      hasCard: false,
    });
    await setDoc(doc(db, 'contactHashes', OWNER), {
      hashes: inContacts ? [MM_HASH, 'cccccccccccccccccccccccc'] : ['cccccccccccccccccccccccc'],
    });
  });
}

const accessId = `${OWNER}_${MM}`;

test('the owner writes their card; nobody else can', async () => {
  await assertSucceeds(setDoc(doc(as(OWNER), 'personalCards', OWNER), card()));
  await assertFails(setDoc(doc(as(MM), 'personalCards', OWNER), card()));
});

test('a field outside the whitelist is refused', async () => {
  await assertFails(
    setDoc(doc(as(OWNER), 'personalCards', OWNER), card({ phone: '0501234567' })),
  );
  await assertFails(
    setDoc(doc(as(OWNER), 'personalCards', OWNER), card({ notes: 'פרטי' })),
  );
});

test('an anonymous account can do nothing with cards', async () => {
  const anon = env
    .authenticatedContext(OWNER, { firebase: { sign_in_provider: 'anonymous' } })
    .firestore();
  await assertFails(setDoc(doc(anon, 'personalCards', OWNER), card()));
});

test('a card cannot be deleted by a client — only flagged', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertFails(deleteDoc(doc(as(OWNER), 'personalCards', OWNER)));
});

test('only an approved matchmaker reads the card, and not once deleted', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertFails(getDoc(doc(as(MM), 'personalCards', OWNER)));

  await seed((db) =>
    setDoc(doc(db, 'cardAccess', accessId), { ...access('approved'), updatedAt: new Date() }),
  );
  await assertSucceeds(getDoc(doc(as(MM), 'personalCards', OWNER)));
  await assertFails(getDoc(doc(as(STRANGER), 'personalCards', OWNER)));

  await seed((db) => updateDoc(doc(db, 'personalCards', OWNER), { deleted: true }));
  await assertFails(getDoc(doc(as(MM), 'personalCards', OWNER)));
});

test('a matchmaker not in the owner’s contacts cannot ask', async () => {
  await seedCardAndContacts({ inContacts: false });
  await assertFails(setDoc(doc(as(MM), 'cardAccess', accessId), access('pending')));
});

test('a matchmaker in the owner’s contacts can ask — and only ask', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertSucceeds(setDoc(doc(as(MM), 'cardAccess', accessId), access('pending')));
  // Approving their own request is the owner's to do.
  await assertFails(setDoc(doc(as(MM), 'cardAccess', accessId), access('approved')));
  await assertSucceeds(setDoc(doc(as(OWNER), 'cardAccess', accessId), access('approved')));
});

test('a matchmaker cannot create an approved row for themselves', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertFails(setDoc(doc(as(MM), 'cardAccess', accessId), access('approved')));
});

test('after "not now" the matchmaker may ask again; after a block, never', async () => {
  await seedCardAndContacts({ inContacts: true });
  await seed((db) =>
    setDoc(doc(db, 'cardAccess', accessId), { ...access('declined'), updatedAt: new Date() }),
  );
  await assertSucceeds(setDoc(doc(as(MM), 'cardAccess', accessId), access('pending')));

  await seed((db) =>
    setDoc(doc(db, 'cardAccess', accessId), { ...access('blocked'), updatedAt: new Date() }),
  );
  await assertFails(setDoc(doc(as(MM), 'cardAccess', accessId), access('pending')));
  // Deleting the block would lift it.
  await assertFails(deleteDoc(doc(as(MM), 'cardAccess', accessId)));
  await assertSucceeds(deleteDoc(doc(as(OWNER), 'cardAccess', accessId)));
});

test('a phone hash cannot be borrowed from somebody else’s entry', async () => {
  await seedCardAndContacts({ inContacts: true });
  // A stranger points their own phone record at the matchmaker's hash.
  await seed((db) => setDoc(doc(db, 'userPhones', STRANGER), { phoneHash: MM_HASH }));
  await assertFails(
    setDoc(
      doc(as(STRANGER), 'cardAccess', `${OWNER}_${STRANGER}`),
      access('pending', { matchmakerUid: STRANGER }),
    ),
  );
  // And cannot take over the entry itself.
  await assertFails(
    setDoc(doc(as(STRANGER), 'phoneDirectory', MM_HASH), {
      uid: STRANGER,
      name: 'x',
      matchmaker: true,
      hasCard: false,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('the phone directory can be looked up, never listed', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertSucceeds(getDoc(doc(as(STRANGER), 'phoneDirectory', MM_HASH)));
  await assertFails(getDocs(collection(as(STRANGER), 'phoneDirectory')));
});

test('an owner’s address book is theirs alone', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertFails(getDoc(doc(as(MM), 'contactHashes', OWNER)));
  await assertSucceeds(getDoc(doc(as(OWNER), 'contactHashes', OWNER)));
});

test('a matchmaker’s database hashes are written by them and read by nobody else', async () => {
  const mine = doc(as(MM), 'databaseHashes', MM);
  await assertSucceeds(setDoc(mine, { hashes: ['a', 'b'], updatedAt: new Date() }));
  await assertSucceeds(getDoc(mine));
  await assertFails(getDoc(doc(as(OWNER), 'databaseHashes', MM)));
  await assertFails(
    setDoc(doc(as(OWNER), 'databaseHashes', MM), { hashes: [], updatedAt: new Date() }),
  );
  await assertFails(setDoc(mine, { hashes: [], names: ['x'], updatedAt: new Date() }));
});

test('only an approved matchmaker may report a status, only the owner answers', async () => {
  await seedCardAndContacts({ inContacts: true });
  const report = {
    ownerUid: OWNER,
    matchmakerUid: MM,
    matchmakerName: 'יצחק',
    status: 'busy',
    resolution: null,
    createdAt: serverTimestamp(),
  };
  await assertFails(setDoc(doc(as(MM), 'statusReports', 'r1'), report));
  await seed((db) =>
    setDoc(doc(db, 'cardAccess', accessId), { ...access('approved'), updatedAt: new Date() }),
  );
  await assertSucceeds(setDoc(doc(as(MM), 'statusReports', 'r1'), report));
  await assertFails(updateDoc(doc(as(MM), 'statusReports', 'r1'), { resolution: 'confirmed' }));
  await assertSucceeds(updateDoc(doc(as(OWNER), 'statusReports', 'r1'), { resolution: 'confirmed' }));
});

test('the inbox is written by the server only', async () => {
  await assertFails(
    setDoc(doc(as(OWNER), 'users', OWNER, 'inbox', 'n1'), { title: 'x' }),
  );
});
