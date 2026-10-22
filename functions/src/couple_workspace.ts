import {
  getFirestore,
  FieldValue,
  DocumentReference,
  Timestamp,
} from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import {
  onCall,
  HttpsError,
  CallableRequest,
} from 'firebase-functions/v2/https';
import { randomBytes, createHash } from 'node:crypto';
import {
  Database,
  recordCollections,
  mergeDatabases,
  splitDatabase,
  sharedSetting,
  normalizedPhone,
} from './couple_data';
const options = {
  region: 'europe-west1',
  timeoutSeconds: 540,
  memory: '1GiB' as const,
};
function requireUser(request: { auth?: { uid: string; token: any } }): string {
  if (
    !request.auth ||
    request.auth.token.firebase?.sign_in_provider === 'anonymous'
  )
    throw new HttpsError('unauthenticated', 'נדרשת התחברות');
  return request.auth.uid;
}
async function accountName(uid: string): Promise<string> {
  const settings = await getFirestore()
    .collection(`users/${uid}/settings`)
    .get();
  const values = Object.fromEntries(
    settings.docs.map((d) => {
      try {
        return [d.get('k'), JSON.parse(d.get('v'))];
      } catch {
        return ['', null];
      }
    }),
  );
  return (
    [values.userFirstName, values.userLastName].filter(Boolean).join(' ') ||
    values.userName ||
    'בן/בת הזוג'
  );
}
async function readDatabase(root: DocumentReference): Promise<Database> {
  const result: Database = {};
  for (const c of [...recordCollections, 'settings']) {
    const rows = await root.collection(c).get();
    result[c] = Object.fromEntries(rows.docs.map((d) => [d.id, d.data()]));
  }
  return result;
}
async function writeDatabase(
  root: DocumentReference,
  data: Database,
): Promise<void> {
  const db = getFirestore();
  const writer = db.bulkWriter();
  const writes: Promise<unknown>[] = [];
  for (const [c, records] of Object.entries(data))
    for (const [id, record] of Object.entries(records)) {
      writes.push(
        writer.set(root.collection(c).doc(id), {
          ...record,
          _w: FieldValue.serverTimestamp(),
          _d: 'workspace-migration',
        }),
      );
    }
  await Promise.all([...writes, writer.close()]);
}
function files(data: Database): Set<string> {
  const result = new Set<string>();
  for (const p of Object.values(data.people ?? {}))
    for (const path of p.photos ?? [])
      result.add(`photos/${String(path).split('/').pop()}`);
  for (const n of Object.values(data.personNotes ?? {}))
    if (n.audioFile)
      result.add(`voice/${String(n.audioFile).split('/').pop()}`);
  return result;
}
async function copyFiles(data: Database, from: string, to: string) {
  const bucket = getStorage().bucket();
  for (const file of files(data)) {
    const source = bucket.file(`${from}/${file}`);
    if ((await source.exists())[0])
      await source.copy(bucket.file(`${to}/${file}`));
  }
}
/** Invitations are bearer codes, expire, require two separate authenticated accounts and explicit married consent. */
export const createCoupleInvite = onCall(options, async (request) => {
  const uid = requireUser(request);
  if (request.data?.married !== true)
    throw new HttpsError(
      'failed-precondition',
      'האפשרות מיועדת לזוגות נשואים בלבד',
    );
  const db = getFirestore();
  if ((await db.doc(`memberships/${uid}`).get()).get('databaseUid'))
    throw new HttpsError('already-exists', 'כבר קיים מאגר זוגי');
  const code = randomBytes(16).toString('hex');
  await db
    .doc(`coupleInvites/${code}`)
    .create({
      from: uid,
      name: await accountName(uid),
      expiresAt: Date.now() + 7 * 86400000,
      status: 'pending',
    });
  return { code };
});
export const previewCoupleInvite = onCall(options, async (request) => {
  requireUser(request);
  const code = String(request.data?.code ?? '');
  if (!/^[a-f0-9]{32}$/.test(code))
    throw new HttpsError('invalid-argument', 'קוד הזמנה לא תקין');
  const invite = await getFirestore().doc(`coupleInvites/${code}`).get();
  if (
    !invite.exists ||
    invite.get('expiresAt') < Date.now() ||
    invite.get('status') === 'complete'
  )
    throw new HttpsError('not-found', 'ההזמנה אינה זמינה');
  return { name: invite.get('name') };
});
async function mergeCouple(
  request: CallableRequest,
): Promise<{ databaseUid: string }> {
  const uid = requireUser(request);
  const code = String(request.data?.code ?? '');
  if (
    !/^[a-f0-9]{32}$/.test(code) ||
    request.data?.married !== true ||
    request.data?.confirmMerge !== true
  )
    throw new HttpsError('invalid-argument', 'נדרש אישור לחיבור ולמיזוג');
  const db = getFirestore();
  const inviteRef = db.doc(`coupleInvites/${code}`);
  const invite = await inviteRef.get();
  const primary = invite.get('from');
  if (
    !primary ||
    primary === uid ||
    (invite.get('expiresAt') < Date.now() && invite.get('acceptedBy') !== uid)
  )
    throw new HttpsError('failed-precondition', 'הזמנה לא זמינה');
  if (invite.get('status') === 'complete' && invite.get('acceptedBy') === uid)
    return { databaseUid: primary };
  const names = {
    [primary]: await accountName(primary),
    [uid]: await accountName(uid),
  };
  const members = [primary, uid];
  const name = `${names[primary]} ו${names[uid]}`;
  await db.runTransaction(async (tx) => {
    const current = await tx.get(inviteRef);
    if ((current.get('processingUntil') ?? 0) > Date.now())
      throw new HttpsError(
        'aborted',
        'המיזוג כבר בתהליך. אפשר להמתין ולנסות שוב.',
      );
    const a = await tx.get(db.doc(`memberships/${primary}`));
    const b = await tx.get(db.doc(`memberships/${uid}`));
    for (const m of [a, b])
      if (m.exists && m.get('operation') !== code)
        throw new HttpsError(
          'already-exists',
          'אפשר להשתייך למאגר זוגי אחד בלבד',
        );
    if (current.get('acceptedBy') && current.get('acceptedBy') !== uid)
      throw new HttpsError('already-exists', 'ההזמנה כבר בשימוש');
    for (const member of members)
      tx.set(db.doc(`memberships/${member}`), {
        databaseUid: primary,
        members,
        names,
        name,
        state: 'merging',
        operation: code,
      });
    tx.set(db.doc(`couples/${primary}`), {
      members,
      names,
      name,
      state: 'merging',
      operation: code,
    });
    tx.update(inviteRef, {
      acceptedBy: uid,
      status: 'merging',
      processingUntil: Date.now() + 10 * 60000,
    });
  });
  try {
    // Freeze writes first. Keep immutable source archives for recovery and every conflicting field.
    await db
      .doc(`coupleData/${code}`)
      .set(
        { members, createdAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    await db.doc(`coupleArchives/${code}`).set({ members }, { merge: true });
    const sources = [];
    for (const member of members) {
      const archive = db.doc(`coupleArchives/${code}/accounts/${member}`);
      if (!(await archive.get()).get('complete')) {
        const original = await readDatabase(db.doc(`users/${member}`));
        await writeDatabase(archive, original);
        await archive.set({ complete: true });
      }
      sources.push({ uid: member, data: await readDatabase(archive) });
    }
    const merged = mergeDatabases(sources);
    // Avoid old IDs reappearing. Tombstones keep old/offline clients from recreating records.
    const tombstones: Database = {};
    for (const c of recordCollections)
      tombstones[c] = Object.fromEntries(
        Object.keys(sources[0].data[c]).map((id) => [id, { _deleted: true }]),
      );
    await writeDatabase(db.doc(`users/${primary}`), tombstones);
    const sharedSettings = merged.data.settings;
    delete merged.data.settings;
    await writeDatabase(db.doc(`users/${primary}`), merged.data);
    await writeDatabase(db.doc(`coupleData/${code}`), {
      settings: sharedSettings,
      phoneIndex: Object.fromEntries(
        Object.entries(merged.data.people).flatMap(([id, person]) => {
          const phone = normalizedPhone(person.phone);
          return phone
            ? [
                [
                  createHash('sha256').update(phone).digest('hex'),
                  { personId: id },
                ],
              ]
            : [];
        }),
      ),
    });
    for (const source of sources) {
      await copyFiles(
        source.data,
        `users/${source.uid}`,
        `coupleFiles/${code}`,
      );
      // Preserve personal reminder ownership while remapping the idea/person IDs.
      const settings: Database = { settings: {} };
      for (const [oldId, idea] of Object.entries(source.data.matches ?? {}))
        if (idea.reminderDate) {
          const key = `couple.reminder.${source.uid}__${oldId}`;
          settings.settings[encodeURIComponent(key)] = {
            k: key,
            v: JSON.stringify(
              JSON.stringify({
                reminderDate: idea.reminderDate,
                reminderNote: idea.reminderNote ?? null,
              }),
            ),
          };
        }
      for (const value of Object.values(source.data.settings ?? {}))
        if ((value.k ?? '').startsWith('personReminder')) {
          let key = value.k;
          for (const [oldId, id] of Object.entries(merged.ids[source.uid]))
            if (key.endsWith(`.${oldId}`))
              key = key.slice(0, -oldId.length) + id;
          settings.settings[encodeURIComponent(key)] = { ...value, k: key };
        }
      await writeDatabase(db.doc(`users/${source.uid}`), settings);
    }
    // Individual consent never silently expands to a spouse. Ask again as the named pair.
    const owners = new Map<string, any>();
    for (const member of members) {
      const grants = await db
        .collection('cardAccess')
        .where('matchmakerUid', '==', member)
        .get();
      for (const grant of grants.docs) {
        if (
          grant.get('status') === 'approved' ||
          grant.get('status') === 'pending'
        )
          owners.set(grant.get('ownerUid'), grant.data());
        if (grant.get('status') === 'blocked') continue;
        await grant.ref.update({
          status: 'revoked',
          cardGranted: false,
          lookingGranted: false,
          cardRequested: false, lookingRequested: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    for (const [owner, old] of owners) {
      if (
        (await db.doc(`cardAccess/${owner}_${primary}`).get()).get('status') ===
        'blocked'
      )
        continue;
      await db
        .doc(`cardAccess/${owner}_${primary}`)
        .set({
          ...old,
          ownerUid: owner,
          matchmakerUid: primary,
          matchmakerName: name,
          granteeUids: members,
          status: 'pending',
          requestedBy: 'matchmaker',
          cardGranted: false,
          lookingGranted: false,
          cardRequested: false, lookingRequested: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
    }
    // A paired database has one public score, never two.
    await db.doc(`communityMembers/${uid}`).delete();
    const batch = db.batch();
    for (const member of members)
      batch.update(db.doc(`memberships/${member}`), {
        state: 'active',
        revision: code,
      });
    batch.update(db.doc(`couples/${primary}`), {
      state: 'active',
      possibleDuplicates: merged.possibleDuplicates,
    });
    batch.update(inviteRef, { status: 'complete' });
    batch.set(
      db.doc(`coupleArchives/${code}`),
      { purgeAfter: Timestamp.fromMillis(Date.now() + 30 * 86400000) },
      { merge: true },
    );
    await batch.commit();
    return { databaseUid: primary };
  } finally {
    await inviteRef.update({ processingUntil: 0 });
  }
}
export const acceptCoupleInvite = onCall(options, mergeCouple);
export const resumeCoupleMigration = onCall(options, async (request) => {
  const caller = requireUser(request);
  const membership = await getFirestore().doc(`memberships/${caller}`).get();
  if (membership.get('state') !== 'merging')
    throw new HttpsError('failed-precondition', 'אין מיזוג להשלמה');
  const code = membership.get('operation');
  const invite = await getFirestore().doc(`coupleInvites/${code}`).get();
  const acceptedBy = invite.get('acceptedBy');
  if (!membership.get('members')?.includes(acceptedBy))
    throw new HttpsError('permission-denied', 'הזמנה לא תקינה');
  // Either spouse can resume the same already-consented operation, never a different connection.
  return mergeCouple({
    ...request,
    auth: { ...request.auth!, uid: acceptedBy },
    data: { code, married: true, confirmMerge: true },
  });
});

export const previewCoupleSplit = onCall(options, async (request) => {
  const uid = requireUser(request);
  const membership = await getFirestore().doc(`memberships/${uid}`).get();
  if (!membership.exists)
    throw new HttpsError('failed-precondition', 'אין מאגר זוגי');
  const recovery = getFirestore().doc(
    `coupleArchives/split_${membership.get('operation')}/accounts/shared`,
  );
  const recovering =
    membership.get('state') === 'splitting' &&
    (await recovery.get()).get('complete');
  const data = await readDatabase(
    recovering
      ? recovery
      : getFirestore().doc(`users/${membership.get('databaseUid')}`),
  );
  return {
    sides: (membership.get('members') as string[]).map((member) => {
      const part = splitDatabase(data, member);
      return {
        uid: member,
        name: membership.get('names')[member],
        people: Object.keys(part.people).length,
        ideas: Object.keys(part.matches).length,
      };
    }),
  };
});
export const splitCoupleWorkspace = onCall(options, async (request) => {
  const uid = requireUser(request);
  if (request.data?.confirmed !== true)
    throw new HttpsError('failed-precondition', 'נדרש אישור מפורש');
  const db = getFirestore();
  const membership = await db.doc(`memberships/${uid}`).get();
  if (!membership.exists)
    throw new HttpsError('failed-precondition', 'אין מאגר זוגי');
  const primary = membership.get('databaseUid');
  const members = membership.get('members') as string[];
  const operation = `split_${membership.get('operation')}`;
  await db.runTransaction(async (tx) => {
    const couple = await tx.get(db.doc(`couples/${primary}`));
    if ((couple.get('processingUntil') ?? 0) > Date.now())
      throw new HttpsError('aborted', 'הפיצול כבר בתהליך');
    if (!['active', 'splitting'].includes(couple.get('state')))
      throw new HttpsError('failed-precondition', 'המאגר בתהליך עדכון');
    tx.update(couple.ref, {
      state: 'splitting',
      processingUntil: Date.now() + 10 * 60000,
    });
    for (const member of members)
      tx.update(db.doc(`memberships/${member}`), { state: 'splitting' });
  });
  try {
    const archive = db.doc(`coupleArchives/${operation}/accounts/shared`);
    if (!(await archive.get()).get('complete')) {
      const shared = await readDatabase(db.doc(`users/${primary}`));
      shared.settings = Object.fromEntries(
        (
          await db
            .collection(`coupleData/${membership.get('operation')}/settings`)
            .get()
        ).docs.map((d) => [d.id, d.data()]),
      );
      await writeDatabase(archive, shared);
      await archive.set({ complete: true });
    }
    await db
      .doc(`coupleArchives/${operation}`)
      .set({ members }, { merge: true });
    const original = await readDatabase(archive);
    for (const member of members) {
      const part = splitDatabase(original, member);
      const current = await readDatabase(db.doc(`users/${member}`));
      for (const c of recordCollections)
        for (const id of Object.keys(current[c]))
          if (!part[c][id]) part[c][id] = { _deleted: true };
      for (const setting of Object.values(current.settings)) {
        if (!(setting.k ?? '').startsWith('couple.reminder.')) continue;
        const id = setting.k.substring('couple.reminder.'.length);
        if (!part.matches[id] || part.matches[id]._deleted) continue;
        try {
          Object.assign(part.matches[id], JSON.parse(JSON.parse(setting.v)));
        } catch {
          /* malformed legacy reminder remains in personal settings */
        }
      }
      await writeDatabase(db.doc(`users/${member}`), part);
      await copyFiles(
        part,
        `coupleFiles/${membership.get('operation')}`,
        `users/${member}`,
      );
      // Remove shared settings that refer to the other side's people.
      for (const [id, setting] of Object.entries(current.settings))
        if (sharedSetting(setting.k ?? '') && !part.settings[id])
          await db
            .doc(`users/${member}/settings/${id}`)
            .set({ _deleted: true, _w: FieldValue.serverTimestamp() });
    }
    const grants = await db
      .collection('cardAccess')
      .where('matchmakerUid', '==', primary)
      .get();
    for (const grant of grants.docs)
      if (grant.get('granteeUids')?.length === 2)
        await grant.ref.update({
          status: 'revoked',
          cardGranted: false,
          lookingGranted: false,
          cardRequested: false, lookingRequested: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
    const batch = db.batch();
    for (const member of members) batch.delete(db.doc(`memberships/${member}`));
    batch.update(db.doc(`couples/${primary}`), { state: 'split' });
    batch.set(
      db.doc(`coupleArchives/${operation}`),
      { purgeAfter: Timestamp.fromMillis(Date.now() + 30 * 86400000) },
      { merge: true },
    );
    batch.set(
      db.doc(`coupleData/${membership.get('operation')}`),
      { purgeAfter: Timestamp.fromMillis(Date.now() + 30 * 86400000) },
      { merge: true },
    );
    await batch.commit();
    return { split: true };
  } finally {
    await db.doc(`couples/${primary}`).update({ processingUntil: 0 });
  }
});

export const resolveMatchmaker = onCall(options, async (request) => {
  requireUser(request);
  const uid = request.data?.uid;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid))
    throw new HttpsError('invalid-argument', 'חשבון לא תקין');
  const caller = requireUser(request);
  const db = getFirestore();
  const helpers = await db.doc(`users/${caller}/private/helpers`).get();
  const known = (helpers.get('helpers') ?? []).some(
    (h: { uid: string }) => h.uid === uid,
  );
  const grant = await db.doc(`cardAccess/${caller}_${uid}`).get();
  const phone = await db.doc(`userPhones/${uid}`).get();
  const directory = phone.get('phoneHash')
    ? await db.doc(`phoneDirectory/${phone.get('phoneHash')}`).get()
    : null;
  if (
    !known &&
    !grant.exists &&
    (directory?.get('uid') !== uid || directory?.get('matchmaker') !== true)
  )
    throw new HttpsError('permission-denied', 'השדכן אינו זמין');
  const m = await db.doc(`memberships/${uid}`).get();
  if (m.exists && m.get('state') === 'active')
    return {
      uid: m.get('databaseUid'),
      name: m.get('name'),
      members: m.get('members'),
    };
  return {
    uid,
    name:
      directory?.get('name') ||
      (known
        ? (helpers.get('helpers') as { uid: string; name: string }[]).find(
            (h) => h.uid === uid,
          )?.name
        : '') ||
      grant.get('matchmakerName') ||
      'שדכן',
    members: [uid],
  };
});
