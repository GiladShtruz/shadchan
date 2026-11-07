// Security rules for the personal card, run against the Firestore emulator:
//
//   cd functions && npm run test:rules
//
// Every access decision about a card is the server's (spec item 110), so the
// rules are tested as the thing they are — not through the app.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
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
  onSnapshot,
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

// A live card needs a photo and twenty words of text.
const TWENTY_WORDS = Array.from({ length: 20 }, (_, i) => `מילה${i}`).join(' ');

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
    description: TWENTY_WORDS,
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
    photoPaths: [`personalCards/${OWNER}/one.jpg`],
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
    await setDoc(doc(db, 'userPhones', OWNER), { phoneHash: OWNER_HASH });
    await setDoc(doc(db, 'phoneDirectory', OWNER_HASH), { uid: OWNER, name: 'דניאל', matchmaker: false, hasCard: true });
    await setDoc(doc(db, 'contactHashes', MM), { hashes: [OWNER_HASH] });
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

test('a request may say the matchmaker’s gender, and only as male or female', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertFails(
    setDoc(doc(as(MM), 'cardAccess', accessId), access('pending', { matchmakerGender: 'x' })),
  );
  await assertSucceeds(
    setDoc(doc(as(MM), 'cardAccess', accessId), access('pending', { matchmakerGender: 'female' })),
  );
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

test('an owner who takes no requests cannot be asked — but can still grant', async () => {
  await seedCardAndContacts({ inContacts: true });
  // The owner publishes their own entry with requests switched off.
  await seed((db) => setDoc(doc(db, 'userPhones', OWNER), { phoneHash: OWNER_HASH }));
  await assertSucceeds(
    setDoc(doc(as(OWNER), 'phoneDirectory', OWNER_HASH), {
      uid: OWNER,
      name: 'דניאל לוי',
      matchmaker: false,
      hasCard: true,
      acceptsRequests: false,
      announces: false,
      updatedAt: serverTimestamp(),
    }),
  );
  // The announce switch is a boolean, like every flag on the entry.
  await assertFails(
    updateDoc(doc(as(OWNER), 'phoneDirectory', OWNER_HASH), {
      announces: 'no',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(setDoc(doc(as(MM), 'cardAccess', accessId), access('pending')));
  await assertSucceeds(
    setDoc(
      doc(as(OWNER), 'cardAccess', accessId),
      access('approved', { requestedBy: 'owner' }),
    ),
  );

  // Switched back on, asking works again.
  await assertSucceeds(
    updateDoc(doc(as(OWNER), 'phoneDirectory', OWNER_HASH), {
      acceptsRequests: true,
      updatedAt: serverTimestamp(),
    }),
  );
  await seed((db) =>
    setDoc(doc(db, 'cardAccess', accessId), { ...access('declined'), updatedAt: new Date() }),
  );
  await assertSucceeds(setDoc(doc(as(MM), 'cardAccess', accessId), access('pending')));
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

test('the directory reveals presence only to reciprocal contacts, never as a list', async () => {
  await seedCardAndContacts({ inContacts: true });
  await assertFails(getDoc(doc(as(STRANGER), 'phoneDirectory', MM_HASH)));
  await assertSucceeds(getDoc(doc(as(OWNER), 'phoneDirectory', MM_HASH)));
  await seed(db => updateDoc(doc(db, 'contactHashes', MM), {hashes: []}));
  await assertFails(getDoc(doc(as(OWNER), 'phoneDirectory', MM_HASH)));
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

test('matchmaker status changes never generate reports for the single', async () => {
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
  await assertFails(setDoc(doc(as(MM), 'statusReports', 'r1'), report));
  await seed(db => setDoc(doc(db, 'statusReports', 'r1'), {...report, createdAt:new Date()}));
  await assertFails(updateDoc(doc(as(MM), 'statusReports', 'r1'), { resolution: 'confirmed' }));
  await assertSucceeds(updateDoc(doc(as(OWNER), 'statusReports', 'r1'), { resolution: 'confirmed' }));
});

test('the inbox is written by the server only', async () => {
  await assertFails(
    setDoc(doc(as(OWNER), 'users', OWNER, 'inbox', 'n1'), { title: 'x' }),
  );
});

test('drafts cannot be requested; a photo and twenty words activate a card', async () => {
  await seedCardAndContacts({inContacts:true});
  const nineteen = TWENTY_WORDS.split(' ').slice(1).join(' ');
  const drafts = [
    { description: '', photoPaths: [] },
    { description: ' '.repeat(50), photoPaths: ['p'] },
    { description: nineteen, photoPaths: ['p'] },
    { description: TWENTY_WORDS, photoPaths: [] },
    { description: 'א'.repeat(300), photoPaths: ['p'] },
  ];
  for (const draft of drafts) {
    await seed(db => updateDoc(doc(db,'personalCards',OWNER),draft));
    await assertFails(setDoc(doc(as(MM),'cardAccess',accessId),access('pending')));
  }
  await seed(db => updateDoc(doc(db,'personalCards',OWNER),{description:TWENTY_WORDS,photoPaths:['p']}));
  await assertSucceeds(setDoc(doc(as(MM),'cardAccess',accessId),access('pending')));
});
test('four photos allowed, five forbidden; cannot forge activation', async () => {
  await assertSucceeds(setDoc(doc(as(OWNER),'personalCards',OWNER),card({photoPaths:['a','b','c','d']})));
  await assertFails(updateDoc(doc(as(OWNER),'personalCards',OWNER),{photoPaths:['a','b','c','d','e']}));
  await assertFails(updateDoc(doc(as(OWNER),'personalCards',OWNER),{active:true}));
});
test('card and private-looking grants are independent and owner controlled', async () => {
  await seedCardAndContacts({inContacts:true});
  await seed(async db => {
    await setDoc(doc(db,'privateLooking',OWNER),{text:'פרטי',audioPath:null});
    await setDoc(doc(db,'cardAccess',accessId),{...access('approved'),updatedAt:new Date()});
    await setDoc(doc(db,'users',MM,'personNotes','n'),{text:'של השדכן'});
  });
  await assertSucceeds(getDoc(doc(as(MM),'personalCards',OWNER)));
  await assertFails(getDoc(doc(as(MM),'privateLooking',OWNER)));
  await assertFails(updateDoc(doc(as(MM),'cardAccess',accessId),{lookingGranted:true,updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(as(MM),'cardAccess',accessId),{lookingRequested:true,updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(as(OWNER),'cardAccess',accessId),{lookingGranted:true,cardGranted:false,lookingRequested:false,updatedAt:serverTimestamp()}));
  await assertSucceeds(getDoc(doc(as(MM),'privateLooking',OWNER)));
  await assertFails(getDoc(doc(as(MM),'personalCards',OWNER)));
  await assertFails(updateDoc(doc(as(OWNER),'users',MM,'personNotes','n'),{text:'נמחק'}));
  await assertSucceeds(updateDoc(doc(as(OWNER),'cardAccess',accessId),{lookingGranted:false,updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(as(MM),'privateLooking',OWNER)));
  await assertSucceeds(getDoc(doc(as(MM),'users',MM,'personNotes','n')));
});
test('couples share records, never private settings or address books', async () => {
  await seed(async db => {
    for (const uid of ['a','b']) await setDoc(doc(db,'memberships',uid),{databaseUid:'a',members:['a','b'],state:'active'});
    await setDoc(doc(db,'users','a','people','p'),{firstName:'דוד'});
    await setDoc(doc(db,'users','a','settings','private'),{k:'personalCard.person',v:'secret'});
    await setDoc(doc(db,'contactHashes','a'),{hashes:['secret']});
  });
  await assertSucceeds(getDoc(doc(as('b'),'users','a','people','p')));
  await assertFails(getDoc(doc(as('b'),'users','a','settings','private')));
  await assertFails(getDoc(doc(as('b'),'contactHashes','a')));
  await assertFails(setDoc(doc(as('b'),'memberships','b'),{databaseUid:'stranger'}));
  await assertFails(setDoc(doc(as('b'),'users','b','people','new'),{firstName:'private copy'}));
  await assertSucceeds(setDoc(doc(as('b'),'users','a','people','new'),{firstName:'shared',_actorUid:'b'}));
  await assertFails(setDoc(doc(as('b'),'users','a','people','new'),{firstName:'forged',_actorUid:'a'}));
});
test('spouse never inherits individual consent', async () => {
  await seed(async db => {
    await setDoc(doc(db,'personalCards',OWNER),{...card(),updatedAt:new Date()});
    await setDoc(doc(db,'privateLooking',OWNER),{text:'פרטי'});
    for(const uid of [MM,'spouse']) await setDoc(doc(db,'memberships',uid),{databaseUid:MM,members:[MM,'spouse'],state:'active'});
    await setDoc(doc(db,'cardAccess',accessId),{...access('approved'),lookingGranted:true,updatedAt:new Date()});
  });
  await assertFails(getDoc(doc(as('spouse'),'personalCards',OWNER)));
  await assertFails(getDoc(doc(as('spouse'),'privateLooking',OWNER)));
  await assertSucceeds(updateDoc(doc(as(OWNER),'cardAccess',accessId),{granteeUids:[MM,'spouse'],updatedAt:serverTimestamp()}));
  await assertSucceeds(getDoc(doc(as('spouse'),'personalCards',OWNER)));
  await assertSucceeds(getDoc(doc(as('spouse'),'privateLooking',OWNER)));
});
test('shared settings and notices are isolated by pairing, including a later marriage',async()=>{
 await seed(async db=>{
  for(const uid of['a','b']) await setDoc(doc(db,'memberships',uid),{databaseUid:'a',members:['a','b'],operation:'old-pair',state:'active'});
  await setDoc(doc(db,'coupleData','old-pair','settings','board'),{k:'home.board',v:'"old"'});
  await setDoc(doc(db,'coupleData','old-pair','inbox','notice'),{read:false,body:'private joint notice'});
  await setDoc(doc(db,'coupleData','new-pair','settings','board'),{k:'home.board',v:'"new"'});
 });
 await assertSucceeds(getDoc(doc(as('b'),'coupleData','old-pair','settings','board')));
 await assertSucceeds(updateDoc(doc(as('b'),'coupleData','old-pair','inbox','notice'),{read:true}));
 await assertFails(updateDoc(doc(as('b'),'coupleData','old-pair','inbox','notice'),{body:'forged'}));
 await assertFails(getDoc(doc(as('b'),'coupleData','new-pair','settings','board')));
 await seed(db=>setDoc(doc(db,'memberships','a'),{databaseUid:'a',members:['a','c'],operation:'new-pair',state:'active'}));
 await assertFails(getDoc(doc(as('a'),'coupleData','old-pair','settings','board')));
 await assertSucceeds(getDoc(doc(as('a'),'coupleData','new-pair','settings','board')));
});
test('requesting the card while private access is approved preserves private consent',async()=>{
 await seedCardAndContacts({inContacts:true});
 await seed(async db=>{
  await setDoc(doc(db,'privateLooking',OWNER),{text:'פרטי'});
  await setDoc(doc(db,'cardAccess',accessId),{...access('approved'),cardGranted:false,lookingGranted:true,updatedAt:new Date()});
 });
 await assertSucceeds(updateDoc(doc(as(MM),'cardAccess',accessId),{cardRequested:true,updatedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(doc(as(MM),'privateLooking',OWNER)));
 await assertFails(getDoc(doc(as(MM),'personalCards',OWNER)));
 await assertSucceeds(updateDoc(doc(as(OWNER),'cardAccess',accessId),{cardRequested:false,updatedAt:serverTimestamp()}));
 await assertSucceeds(getDoc(doc(as(MM),'privateLooking',OWNER)));
});
test('community tips still work independently of personal cards',async()=>{
 await assertSucceeds(setDoc(doc(as(MM),'tips','tip-regression'),{authorUid:MM,authorName:'יצחק',status:'pending',text:'טיפ מועיל',createdAt:serverTimestamp()}));
});

// The goal shown on home is shared configuration, never a member-owned score.
function weeklyGoal(extra = {}) {
  return { metric: 'ideas', target: 200, title: 'השבוע מחברים יחד',
    updatedAt: serverTimestamp(), ...extra };
}
function goalAdmin(verified = true) {
  return env.authenticatedContext('goal-admin', {
    email: 'yitz292@gmail.com', email_verified: verified,
    firebase: { sign_in_provider: 'password' },
  }).firestore();
}

test('weekly goal: a verified admin publishes, members read and receive live edits', async () => {
  const adminRef = doc(goalAdmin(), 'communityGoals/weekly');
  const memberRef = doc(as(MM), 'communityGoals/weekly');
  await assertSucceeds(setDoc(adminRef, weeklyGoal()));
  assert.equal((await assertSucceeds(getDoc(memberRef))).data().target, 200);
  const received = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { unsubscribe(); reject(new Error('No live goal update')); }, 10000);
    const unsubscribe = onSnapshot(memberRef, snapshot => {
      if (snapshot.data()?.target === 350) {
        clearTimeout(timeout); unsubscribe(); resolve();
      }
    }, error => { clearTimeout(timeout); reject(error); });
  });
  await assertSucceeds(setDoc(adminRef, weeklyGoal({ target: 350, metric: 'friends' })));
  await received;
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'communityGoals/weekly')));
  await assertFails(setDoc(memberRef, weeklyGoal()));
  await assertFails(deleteDoc(memberRef));
  await assertFails(deleteDoc(adminRef));
});

test('weekly goal: delegated admins can edit; unverified and ordinary accounts cannot', async () => {
  await seed(db => setDoc(doc(db, 'supportAdmins/reviewer@example.com'), {}));
  const reviewer = env.authenticatedContext('reviewer', {
    email: 'reviewer@example.com', email_verified: true,
  }).firestore();
  await assertSucceeds(setDoc(doc(reviewer, 'communityGoals/weekly'), weeklyGoal()));
  await assertFails(setDoc(doc(goalAdmin(false), 'communityGoals/weekly'), weeklyGoal()));
  await assertFails(setDoc(doc(as(STRANGER), 'communityGoals/weekly'), weeklyGoal()));
  await assertFails(setDoc(doc(goalAdmin(), 'communityGoals/another'), weeklyGoal()));
});

test('weekly goal: validates target, metric, heading, timestamp and field whitelist', async () => {
  const ref = doc(goalAdmin(), 'communityGoals/weekly');
  for (const extra of [
    { target: 0 }, { target: -1 }, { target: 1.5 }, { target: 1000001 },
    { target: '200' }, { metric: 'unknown' }, { title: 'א'.repeat(101) },
    { title: 42 }, { updatedAt: null }, { privateData: 'no' },
  ]) await assertFails(setDoc(ref, weeklyGoal(extra)));
  await assertSucceeds(setDoc(ref, weeklyGoal({ target: 1, title: '' })));
  await assertSucceeds(setDoc(ref, weeklyGoal({ target: 1000000, metric: 'couples' })));
});

test('personal news: only verified admins publish; members cannot read drafts or write content', async () => {
  const published = {title: 'חדשות בקהילה', text: 'טקסט בלבד', imagePath: null, published: true, notify: true, updatedAt: serverTimestamp()};
  const adminRef = doc(goalAdmin(), 'personalNews/news-one');
  await assertSucceeds(setDoc(adminRef, published));
  await assertSucceeds(getDoc(doc(as(OWNER), 'personalNews/news-one')));
  await assertFails(setDoc(doc(as(OWNER), 'personalNews/forged'), published));
  await assertFails(setDoc(doc(goalAdmin(false), 'personalNews/unverified'), published));
  for (const extra of [{title: ''}, {text: 'א'.repeat(4001)}, {imagePath: 'personalCards/someone/private.jpg'}, {notify: 'yes'}, {secret: 'no'}])
    await assertFails(setDoc(adminRef, {...published, ...extra}));
  await assertSucceeds(setDoc(adminRef, {...published, published: false}));
  await assertFails(getDoc(doc(as(OWNER), 'personalNews/news-one')));
  await assertSucceeds(getDoc(adminRef));
  await assertSucceeds(deleteDoc(adminRef));
});

test('personal card status and join timestamps are server-owned; aggregate numbers reveal no roster', async () => {
  await seedCardAndContacts({inContacts: true});
  const ref = doc(as(OWNER), 'personalCards', OWNER);
  await assertFails(updateDoc(ref, {statusUpdatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {joinedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(ref, {status: 'busy', updatedAt: serverTimestamp()}));
  await assertFails(getDocs(collection(as(STRANGER), 'personalCards')));
  await seed(db => setDoc(doc(db, 'publicStats/personalArea'), {singles: 1}));
  await assertSucceeds(getDoc(doc(as(STRANGER), 'publicStats/personalArea')));
  await assertFails(setDoc(doc(as(STRANGER), 'publicStats/personalArea'), {singles: 999}));
});

test('invites, reminders and discovery caches are server-owned and account private', async () => {
  await seed(async db => {
    await setDoc(doc(db, 'personalInvites/one'), {ownerUid: OWNER, recipientEmail: 'friend@example.com'});
    await setDoc(doc(db, `users/${OWNER}/private/cardActivity`), {nudgedAt: new Date()});
    await setDoc(doc(db, `users/${OWNER}/private/helpers`), {helpers: []});
  });
  await assertSucceeds(getDoc(doc(as(OWNER), 'personalInvites/one')));
  await assertFails(getDoc(doc(as(STRANGER), 'personalInvites/one')));
  await assertFails(setDoc(doc(as(OWNER), 'personalInvites/forged'), {ownerUid: OWNER}));
  await assertFails(setDoc(doc(as(OWNER), 'personalNudges/forged'), {ownerUid: OWNER}));
  await assertSucceeds(getDoc(doc(as(OWNER), `users/${OWNER}/private/cardActivity`)));
  await assertFails(updateDoc(doc(as(OWNER), `users/${OWNER}/private/cardActivity`), {nudgedAt: null}));
  await assertFails(getDoc(doc(as(STRANGER), `users/${OWNER}/private/helpers`)));
  await assertFails(setDoc(doc(as(OWNER), `users/${OWNER}/private/helpers`), {helpers: ['forged']}));
});

test('matchmaker activity is exact owner-written metadata, readable by current card owners only', async () => {
  const mine = doc(as(MM), `matchmakerActivity/${MM}`);
  await assertSucceeds(setDoc(mine, {databaseCount: 17, lastActiveAt: serverTimestamp()}));
  await assertFails(setDoc(mine, {databaseCount: -1, lastActiveAt: serverTimestamp()}));
  await assertFails(getDoc(doc(as(STRANGER), `matchmakerActivity/${MM}`)));
  await seed(db => setDoc(doc(db, 'cardAccess', accessId), {...access('approved'), updatedAt: new Date()}));
  await assertSucceeds(getDoc(doc(as(OWNER), `matchmakerActivity/${MM}`)));
  await seed(db => updateDoc(doc(db, 'cardAccess', accessId), {status: 'revoked'}));
  await assertFails(getDoc(doc(as(OWNER), `matchmakerActivity/${MM}`)));
});

test('account health: written by the account, read by it and by support only', async () => {
  const report = {
    uid: OWNER,
    email: 'owner@example.com',
    emailVerified: true,
    providers: ['password'],
    createdAt: '2026-10-06T00:00:00.000Z',
    updatedAt: serverTimestamp(),
    devices: { d1: { counts: { people: 3 }, log: ['x verify ok'] } },
  };
  await assertSucceeds(setDoc(doc(as(OWNER), `accountHealth/${OWNER}`), report));
  await assertSucceeds(getDoc(doc(as(OWNER), `accountHealth/${OWNER}`)));
  // Another account can neither read nor write it, nor forge its own uid.
  await assertFails(getDoc(doc(as(STRANGER), `accountHealth/${OWNER}`)));
  await assertFails(setDoc(doc(as(STRANGER), `accountHealth/${OWNER}`), report));
  await assertFails(
    setDoc(doc(as(STRANGER), `accountHealth/${STRANGER}`), report),
  );
  // Nothing beyond the whitelist — no record contents can be smuggled in.
  await assertFails(
    setDoc(doc(as(OWNER), `accountHealth/${OWNER}`), { ...report, people: [] }),
  );
  // An anonymous session cannot report.
  const anonymous = env
    .authenticatedContext(OWNER, { firebase: { sign_in_provider: 'anonymous' } })
    .firestore();
  await assertFails(setDoc(doc(anonymous, `accountHealth/${OWNER}`), report));
  // Support reads it, and only with a verified address.
  const support = env
    .authenticatedContext('support', {
      email: 'yitz292@gmail.com',
      email_verified: true,
      firebase: { sign_in_provider: 'google.com' },
    })
    .firestore();
  await assertSucceeds(getDoc(doc(support, `accountHealth/${OWNER}`)));
  const unverified = env
    .authenticatedContext('support2', {
      email: 'yitz292@gmail.com',
      email_verified: false,
      firebase: { sign_in_provider: 'password' },
    })
    .firestore();
  await assertFails(getDoc(doc(unverified, `accountHealth/${OWNER}`)));
  await assertFails(setDoc(doc(support, `accountHealth/${OWNER}`), report));
});

test('sync conflicts are kept under the account, readable by it alone', async () => {
  const conflict = {
    collection: 'people',
    recordId: 'p1',
    lostSide: 'local',
    device: 'd1',
    kept: { city: 'צפת' },
    lost: { city: 'בני ברק' },
    at: serverTimestamp(),
  };
  await assertSucceeds(
    setDoc(doc(as(OWNER), `users/${OWNER}/syncConflicts/c1`), conflict),
  );
  await assertSucceeds(getDoc(doc(as(OWNER), `users/${OWNER}/syncConflicts/c1`)));
  await assertFails(getDoc(doc(as(STRANGER), `users/${OWNER}/syncConflicts/c1`)));
  await assertFails(
    setDoc(doc(as(STRANGER), `users/${OWNER}/syncConflicts/c2`), conflict),
  );
  await assertFails(
    updateDoc(doc(as(OWNER), `users/${OWNER}/syncConflicts/c1`), { lostSide: 'remote' }),
  );
  await assertFails(
    setDoc(doc(as(OWNER), `users/${OWNER}/syncConflicts/c3`), { ...conflict, extra: 1 }),
  );
});
