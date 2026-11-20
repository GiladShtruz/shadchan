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
import { logger } from 'firebase-functions';
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
/**
 * Copies a database's photos and recordings between two Storage folders —
 * sixteen at a time, and never one already there. One at a time, a large
 * database ran past the function's nine minutes, the merge was killed
 * halfway, and both accounts were left "merging" with nobody to finish it.
 */
async function copyFiles(data: Database, from: string, to: string) {
  const bucket = getStorage().bucket();
  const list = [...files(data)];
  let next = 0;
  async function worker(): Promise<void> {
    while (next < list.length) {
      const file = list[next++];
      const target = bucket.file(`${to}/${file}`);
      if ((await target.exists())[0]) continue;
      const source = bucket.file(`${from}/${file}`);
      if ((await source.exists())[0]) await source.copy(target);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(16, list.length) }, () => worker()),
  );
}

// --- Pairing progress, its log, and the way back -----------------------------
//
// A couple's merge runs for minutes on the server, and a phone may lose its
// connection, be closed, or the function itself be stopped at its time limit
// at any moment in it. So every step is written down on the invite (`step`)
// and in its log (`coupleInvites/{code}/log`), and **a merge that cannot
// finish is undone, not left half-way**: both accounts are restored from the
// immutable archives taken before anything was written, and both go back to
// their own databases.

/** The steps of a merge, in order. */
export const MERGE_STEPS = [
  'claimed',
  'archived',
  'merged',
  'files',
  'settings',
  'grants',
  'active',
] as const;

export function stepIndex(step: unknown): number {
  return MERGE_STEPS.indexOf(step as (typeof MERGE_STEPS)[number]);
}

/**
 * Whether a merge stopped at [step] can still be undone completely. Until the
 * card permissions are touched, everything the merge wrote is in the two
 * account trees, and the archives hold what they were before.
 */
export function canRollBack(step: unknown): boolean {
  return stepIndex(step) < stepIndex('grants');
}

/** After this many starts of one merge, it is undone rather than retried. */
export const MAX_MERGE_ATTEMPTS = 3;

/**
 * What to write so that a tree reads exactly as [archive] did: every archived
 * document as it was, and a tombstone for every live document the archive
 * did not have. Pure, so it is tested.
 */
export function restorePlan(current: Database, archive: Database): Database {
  const out: Database = {};
  for (const c of [...recordCollections, 'settings']) {
    out[c] = {};
    for (const [id, record] of Object.entries(archive[c] ?? {}))
      out[c][id] = record;
    for (const [id, record] of Object.entries(current[c] ?? {}))
      if (!archive[c]?.[id] && record?._deleted !== true)
        out[c][id] = { _deleted: true };
  }
  return out;
}

/** An error reduced to a code and a short line — never a record. */
function errorLine(error: unknown): string {
  const e = error as { code?: unknown; message?: unknown };
  const code = typeof e?.code === 'string' ? e.code : '';
  const message = typeof e?.message === 'string' ? e.message : String(error);
  return `${code ? `${code}: ` : ''}${message}`.slice(0, 300);
}

/** Records [step] on the invite and appends it to the invite's log. */
async function mark(
  code: string,
  step: string,
  extra: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  const inviteRef = db.doc(`coupleInvites/${code}`);
  try {
    await inviteRef.collection('log').add({
      step,
      at: FieldValue.serverTimestamp(),
      ...extra,
    });
    if (stepIndex(step) >= 0)
      await inviteRef.update({ step, stepAt: FieldValue.serverTimestamp() });
  } catch (error) {
    logger.warn('couple: log failed', { code, step, error: String(error) });
  }
  logger.info('couple', { code, step, ...extra });
}

/**
 * Undoes a merge that did not finish: both account trees as they were in the
 * archives, both memberships gone, and the invite open again so the couple can
 * simply try once more. Never after the card permissions were touched.
 */
async function rollbackMerge(code: string, reason: string): Promise<void> {
  const db = getFirestore();
  const inviteRef = db.doc(`coupleInvites/${code}`);
  const invite = await inviteRef.get();
  const step = invite.get('step');
  if (!canRollBack(step))
    throw new HttpsError(
      'failed-precondition',
      'החיבור כבר הגיע לשלב ההרשאות ואפשר רק להשלים אותו',
    );
  await mark(code, 'rollingBack', { reason, fromStep: step ?? null });
  const members = [invite.get('from'), invite.get('acceptedBy')].filter(
    (m): m is string => typeof m === 'string' && m.length > 0,
  );
  for (const member of members) {
    const archive = db.doc(`coupleArchives/${code}/accounts/${member}`);
    // Nothing is written to an account's tree before both archives are
    // complete, so an account without one was never touched.
    if (!(await archive.get()).get('complete')) continue;
    await writeDatabase(
      db.doc(`users/${member}`),
      restorePlan(
        await readDatabase(db.doc(`users/${member}`)),
        await readDatabase(archive),
      ),
    );
  }
  const batch = db.batch();
  for (const member of members) {
    const membership = await db.doc(`memberships/${member}`).get();
    if (membership.exists && membership.get('operation') === code)
      batch.delete(membership.ref);
  }
  const primary = invite.get('from');
  if (typeof primary === 'string') {
    const couple = await db.doc(`couples/${primary}`).get();
    if (couple.exists && couple.get('operation') === code)
      batch.delete(couple.ref);
  }
  batch.update(inviteRef, {
    status: 'pending',
    acceptedBy: FieldValue.delete(),
    step: 'rolledBack',
    attempts: 0,
    processingUntil: 0,
    rolledBackAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  await mark(code, 'rolledBack');
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
      attempts: FieldValue.increment(1),
    });
  });
  // Where an earlier attempt got to: the steps behind it are not repeated.
  const done = stepIndex(invite.get('step'));
  if (done >= 0)
    await mark(code, 'resumed', { by: uid, from: MERGE_STEPS[done] });
  else await mark(code, 'claimed', { by: uid });
  let failedAt: string = done >= 0 ? MERGE_STEPS[done] : 'claimed';
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
    await mark(code, 'archived');
    failedAt = 'archived';
    const merged = mergeDatabases(sources);
    // The inviting account's tree becomes the shared one, ids and all. Only an
    // id that did not survive the merge (folded into the same person on the
    // other side) gets a tombstone, so an old or offline phone cannot bring
    // it back. Ids that survive are simply rewritten with the merged record.
    const tombstones: Database = {};
    for (const c of recordCollections)
      tombstones[c] = Object.fromEntries(
        Object.keys(sources[0].data[c])
          .filter((id) => !merged.data[c][id])
          .map((id) => [id, { _deleted: true }]),
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
    await mark(code, 'merged');
    failedAt = 'merged';
    if (done < stepIndex('files'))
      for (const source of sources)
        await copyFiles(
          source.data,
          `users/${source.uid}`,
          `coupleFiles/${code}`,
        );
    await mark(code, 'files');
    failedAt = 'files';
    for (const source of sources) {
      // Preserve personal reminder ownership while remapping the idea/person IDs.
      const settings: Database = { settings: {} };
      const matchIds = merged.recordIds[source.uid].matches ?? {};
      for (const [oldId, idea] of Object.entries(source.data.matches ?? {}))
        if (idea.reminderDate && matchIds[oldId]) {
          const key = `couple.reminder.${matchIds[oldId]}`;
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
      // The account's own card in the database ("own-personal-card"): its
      // record may have been renamed for the other side's, so the personal
      // pointer moves with it — otherwise this phone would adopt the spouse's
      // card record as its own and overwrite it.
      let mirror = 'own-personal-card';
      for (const value of Object.values(source.data.settings ?? {}))
        if (value.k === 'personalCard.mirrorId') {
          try {
            const id = JSON.parse(value.v);
            if (typeof id === 'string' && id) mirror = id;
          } catch {
            /* keep the default */
          }
        }
      const mirrorTo = merged.ids[source.uid][mirror];
      if (mirrorTo) {
        settings.settings[encodeURIComponent('personalCard.mirrorId')] = {
          k: 'personalCard.mirrorId',
          v: JSON.stringify(mirrorTo),
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
    await mark(code, 'settings');
    failedAt = 'settings';
    // From here on the card permissions change, which the archives do not
    // hold: a merge that fails after this point is completed, never undone.
    await mark(code, 'grants');
    failedAt = 'grants';
    // **Every grant stays exactly as it was** (2026-11-20). This step used
    // to revoke every approval both spouses held and ask the singles again in
    // the pair's name — and nothing ever gave the approvals back, which is
    // how matchmakers lost access to cards they had been given. A single's
    // grant to a matchmaker now also covers that matchmaker's partner, view
    // only (see the couple space); the pair's row is written approved
    // wherever either spouse already had the single's yes.
    const owners = new Map<string, any>();
    for (const member of members) {
      const grants = await db
        .collection('cardAccess')
        .where('matchmakerUid', '==', member)
        .where('status', '==', 'approved')
        .get();
      for (const grant of grants.docs)
        if (grant.get('cardGranted') !== false)
          owners.set(grant.get('ownerUid'), grant.data());
    }
    for (const [owner, old] of owners) {
      const pairRef = db.doc(`cardAccess/${owner}_${primary}`);
      const pairStatus = (await pairRef.get()).get('status');
      if (pairStatus === 'blocked' || pairStatus === 'declined') continue;
      await pairRef.set({
        ...old,
        ownerUid: owner,
        matchmakerUid: primary,
        matchmakerName: name,
        granteeUids: members,
        status: 'approved',
        cardGranted: true,
        lookingGranted: false,
        cardRequested: false,
        lookingRequested: false,
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
    await mark(code, 'active');
    return { databaseUid: primary };
  } catch (error) {
    await mark(code, 'error', { failedAt, error: errorLine(error) });
    if (!canRollBack(failedAt)) throw error;
    // Not finished, and still entirely undoable: both accounts go back to
    // their own databases, and the invite can be used again.
    try {
      await rollbackMerge(code, `failed at ${failedAt}`);
    } catch (rollbackError) {
      await mark(code, 'rollbackFailed', { error: errorLine(rollbackError) });
      throw error;
    }
    throw new HttpsError(
      'aborted',
      'החיבור הזוגי לא הושלם, ושני החשבונות הוחזרו למאגרים הקודמים. אפשר לנסות שוב.',
      { rolledBack: true, failedAt },
    );
  } finally {
    await inviteRef.update({ processingUntil: 0 });
  }
}
export const acceptCoupleInvite = onCall(options, mergeCouple);
/**
 * Takes the lease on [code]'s invite for a rollback — refused while a merge
 * of it is still running.
 */
async function leaseForRollback(code: string): Promise<void> {
  const db = getFirestore();
  const inviteRef = db.doc(`coupleInvites/${code}`);
  await db.runTransaction(async (tx) => {
    const invite = await tx.get(inviteRef);
    if ((invite.get('processingUntil') ?? 0) > Date.now())
      throw new HttpsError(
        'aborted',
        'המיזוג עדיין רץ בשרת. אפשר להמתין כמה דקות ולנסות שוב.',
      );
    tx.update(inviteRef, { processingUntil: Date.now() + 10 * 60000 });
  });
}

export const resumeCoupleMigration = onCall(options, async (request) => {
  const caller = requireUser(request);
  const membership = await getFirestore().doc(`memberships/${caller}`).get();
  if (membership.get('state') !== 'merging')
    throw new HttpsError('failed-precondition', 'אין מיזוג להשלמה');
  const code = membership.get('operation');
  const inviteRef = getFirestore().doc(`coupleInvites/${code}`);
  const invite = await inviteRef.get();
  const acceptedBy = invite.get('acceptedBy');
  if (!membership.get('members')?.includes(acceptedBy))
    throw new HttpsError('permission-denied', 'הזמנה לא תקינה');
  // A merge that was stopped again and again (the function's time limit) is
  // undone rather than retried for ever.
  if (
    (invite.get('attempts') ?? 0) >= MAX_MERGE_ATTEMPTS &&
    canRollBack(invite.get('step'))
  ) {
    await leaseForRollback(code);
    try {
      await rollbackMerge(code, 'too many attempts');
    } finally {
      await inviteRef.update({ processingUntil: 0 });
    }
    return { rolledBack: true };
  }
  // Either spouse can resume the same already-consented operation, never a different connection.
  return mergeCouple({
    ...request,
    auth: { ...request.auth!, uid: acceptedBy },
    data: { code, married: true, confirmMerge: true },
  });
});

/**
 * "ביטול החיבור": either spouse undoes a merge that has not finished — both
 * accounts back to their own databases, nothing lost.
 */
export const rollbackCoupleMigration = onCall(options, async (request) => {
  const caller = requireUser(request);
  const membership = await getFirestore().doc(`memberships/${caller}`).get();
  if (membership.get('state') !== 'merging')
    throw new HttpsError('failed-precondition', 'אין חיבור שלא הושלם');
  const code = membership.get('operation');
  const inviteRef = getFirestore().doc(`coupleInvites/${code}`);
  await leaseForRollback(code);
  try {
    await rollbackMerge(code, `cancelled by ${caller}`);
  } finally {
    await inviteRef.update({ processingUntil: 0 });
  }
  return { rolledBack: true };
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
