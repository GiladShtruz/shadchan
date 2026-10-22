import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { createHash } from 'node:crypto';
import { mergeRecord, normalizedPhone, recordCollections } from './couple_data';

/** Serializes same-phone additions from two offline devices; aliases keep late notes/ideas attached. */
export const reconcileCoupleRecord = onDocumentWritten(
  { document: 'users/{uid}/{collection}/{id}', region: 'europe-west1' },
  async (event) => {
    const { uid, collection, id } = event.params;
    if (!(recordCollections as readonly string[]).includes(collection)) return;
    const db = getFirestore();
    const membership = await db.doc(`memberships/${uid}`).get();
    if (
      membership.get('databaseUid') !== uid ||
      membership.get('state') !== 'active'
    )
      return;
    const after = event.data?.after;
    if (!after?.exists || after.get('_deleted')) return;
    const root = db.doc(`users/${uid}`);
    const workspace = membership.get('operation');
    if (collection !== 'people') {
      const patch: Record<string, unknown> = {};
      for (const field of [
        'personId',
        'personAId',
        'personBId',
        'relatedPersonId',
      ]) {
        const old = after.get(field);
        if (!old) continue;
        const alias = await db
          .doc(`coupleData/${workspace}/personAliases/${old}`)
          .get();
        if (alias.exists) patch[field] = alias.get('personId');
      }
      if (Object.keys(patch).length)
        await after.ref.update({ ...patch, _w: FieldValue.serverTimestamp() });
      return;
    }
    const phone = normalizedPhone(after.get('phone'));
    if (!phone) return;
    const key = createHash('sha256').update(phone).digest('hex');
    const index = db.doc(`coupleData/${workspace}/phoneIndex/${key}`);
    const canonical = await db.runTransaction(async (tx) => {
      const entry = await tx.get(index);
      const current = await tx.get(after.ref);
      if (!current.exists || current.get('_deleted')) return null;
      const targetId = entry.get('personId');
      if (!targetId || targetId === id) {
        tx.set(index, { personId: id });
        return null;
      }
      const target = await tx.get(root.collection('people').doc(targetId));
      if (
        !target.exists ||
        target.get('_deleted') ||
        normalizedPhone(target.get('phone')) !== phone
      ) {
        tx.set(index, { personId: id });
        return null;
      }
      tx.set(target.ref, {
        ...mergeRecord(target.data()!, current.data()!),
        id: targetId,
        _w: FieldValue.serverTimestamp(),
      });
      tx.set(current.ref, { _deleted: true, _w: FieldValue.serverTimestamp() });
      tx.set(db.doc(`coupleData/${workspace}/personAliases/${id}`), {
        personId: targetId,
      });
      return targetId as string;
    });
    if (!canonical) return;
    for (const c of recordCollections.filter((c) => c !== 'people'))
      for (const field of [
        'personId',
        'personAId',
        'personBId',
        'relatedPersonId',
      ]) {
        const rows = await root.collection(c).where(field, '==', id).get();
        const writer = db.bulkWriter();
        const updates = rows.docs.map((d) =>
          writer.update(d.ref, {
            [field]: canonical,
            _w: FieldValue.serverTimestamp(),
          }),
        );
        await Promise.all([...updates, writer.close()]);
      }
  },
);
