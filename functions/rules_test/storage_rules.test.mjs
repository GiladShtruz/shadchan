import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';
let env,
  serial = 0;
const owner = 'audio-owner',
  mm = 'audio-mm',
  spouse = 'audio-spouse';
const as = (uid) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } });
const seed = (fn) => env.withSecurityRulesDisabled((c) => fn(c.firestore()));
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shadchan',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
});
after(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
});
async function audio() {
  const path = `privateLooking/${owner}/file-${++serial}.m4a`;
  await assertSucceeds(
    uploadBytes(ref(as(owner).storage(), path), new Uint8Array([1, 2, 3]), {
      contentType: 'audio/mp4',
    }),
  );
  await seed(async (db) => {
    await setDoc(doc(db, 'personalCards', owner), { deleted: false });
    await setDoc(doc(db, 'privateLooking', owner), {
      audioPath: path,
      text: 'פרטי',
    });
    await setDoc(doc(db, 'cardAccess', `${owner}_${mm}`), {
      ownerUid: owner,
      matchmakerUid: mm,
      status: 'approved',
      cardGranted: true,
      lookingGranted: false,
    });
  });
  return path;
}
test('a card grant cannot download private audio; private revocation is immediate', async () => {
  const path = await audio();
  await assertFails(getBytes(ref(as(mm).storage(), path)));
  await seed((db) =>
    updateDoc(doc(db, 'cardAccess', `${owner}_${mm}`), {
      lookingGranted: true,
      cardGranted: false,
    }),
  );
  await assertSucceeds(getBytes(ref(as(mm).storage(), path)));
  await seed((db) =>
    updateDoc(doc(db, 'cardAccess', `${owner}_${mm}`), {
      lookingGranted: false,
    }),
  );
  await assertFails(getBytes(ref(as(mm).storage(), path)));
  await assertSucceeds(getBytes(ref(as(owner).storage(), path)));
});
test('verified audio is immutable and only its current version is readable', async () => {
  const path = await audio();
  await assertFails(
    uploadBytes(ref(as(owner).storage(), path), new Uint8Array([4, 5, 6]), {
      contentType: 'audio/mp4',
    }),
  );
  await seed(async (db) => {
    await updateDoc(doc(db, 'cardAccess', `${owner}_${mm}`), {
      lookingGranted: true,
    });
    await updateDoc(doc(db, 'privateLooking', owner), {
      audioPath: 'privateLooking/other.m4a',
    });
  });
  await assertFails(getBytes(ref(as(mm).storage(), path)));
});
test('a spouse needs explicit named joint consent for private audio', async () => {
  const path = await audio();
  await seed(async (db) => {
    for (const uid of [mm, spouse])
      await setDoc(doc(db, 'memberships', uid), {
        databaseUid: mm,
        members: [mm, spouse],
        state: 'active',
      });
    await updateDoc(doc(db, 'cardAccess', `${owner}_${mm}`), {
      lookingGranted: true,
    });
  });
  await assertFails(getBytes(ref(as(spouse).storage(), path)));
  await seed((db) =>
    updateDoc(doc(db, 'cardAccess', `${owner}_${mm}`), {
      granteeUids: [mm, spouse],
    }),
  );
  await assertSucceeds(getBytes(ref(as(spouse).storage(), path)));
});
test('a new pairing cannot read the previous pairing files', async () => {
  const operation = `pair-${++serial}`,
    path = `coupleFiles/${operation}/voice/file.m4a`;
  await seed(async (db) => {
    for (const uid of [mm, spouse])
      await setDoc(doc(db, 'memberships', uid), {
        databaseUid: mm,
        members: [mm, spouse],
        operation,
        state: 'active',
      });
  });
  await assertSucceeds(
    uploadBytes(ref(as(mm).storage(), path), new Uint8Array([1, 2, 3]), {
      contentType: 'audio/mp4',
    }),
  );
  await assertSucceeds(getBytes(ref(as(spouse).storage(), path)));
  await seed((db) =>
    updateDoc(doc(db, 'memberships', spouse), { operation: 'different-pair' }),
  );
  await assertFails(getBytes(ref(as(spouse).storage(), path)));
});
