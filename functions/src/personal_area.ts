import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import {
  onCall,
  HttpsError,
  CallableRequest,
} from 'firebase-functions/v2/https';
import {
  onDocumentCreated,
  onDocumentWritten,
} from 'firebase-functions/v2/firestore';
import { randomBytes, createHash } from 'node:crypto';
import { isActiveCard } from './card_activity';
import { notify, g, Gender } from './notices';
const options = { region: 'europe-west1' };
const hash = (s: string) => createHash('sha256').update(s).digest('hex');
function user(r: CallableRequest): string {
  if (!r.auth || r.auth.token.firebase?.sign_in_provider === 'anonymous')
    throw new HttpsError('unauthenticated', 'נדרשת התחברות');
  return r.auth.uid;
}
export const createPersonalInvite = onCall(options, async (r) => {
  const uid = user(r),
    db = getFirestore();
  const email =
    typeof r.data?.email === 'string' ? r.data.email.trim().toLowerCase() : '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254)
    throw new HttpsError('invalid-argument', 'יש להזין את האימייל של החבר');
  const card = await db.doc(`personalCards/${uid}`).get();
  if (!isActiveCard(card.data()))
    throw new HttpsError('failed-precondition', 'יש ליצור כרטיס פעיל קודם');
  const token = randomBytes(32).toString('hex'),
    id = hash(token);
  await db
    .doc(`personalInvites/${id}`)
    .create({
      ownerUid: uid,
      recipientEmailHash: hash(email),
      recipientEmail: email,
      state: 'pending',
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 30 * 86400000),
    });
  return {
    id,
    url: `https://shadchan-gilad.web.app/join?from=${uid}&name=${encodeURIComponent(card.get('firstName') ?? '')}&personalInvite=${token}&role=matchmaker`,
  };
});
export const revokePersonalInvite = onCall(options, async (r) => {
  const uid = user(r),
    db = getFirestore(),
    id = r.data?.id;
  if (typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id))
    throw new HttpsError('invalid-argument', 'הזמנה לא תקינה');
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`personalInvites/${id}`),
      invite = await tx.get(ref);
    if (invite.get('ownerUid') !== uid)
      throw new HttpsError('permission-denied', 'הזמנה לא זמינה');
    tx.update(ref, { state: 'revoked' });
    const recipient = invite.get('consumedBy');
    if (typeof recipient === 'string')
      tx.set(
        db.doc(`cardAccess/${uid}_${recipient}`),
        {
          status: 'revoked',
          cardGranted: false,
          lookingGranted: false,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  });
  return { revoked: true };
});
export const redeemPersonalInvite = onCall(options, async (r) => {
  const uid = user(r),
    db = getFirestore(),
    token = r.data?.token;
  const email = String(r.auth?.token.email ?? '')
    .trim()
    .toLowerCase();
  const name =
    (typeof r.data?.name === 'string'
      ? r.data.name.trim().slice(0, 100)
      : '') ||
    String(r.auth?.token.name ?? '')
      .trim()
      .slice(0, 100) ||
    'חבר שהוזמן אישית';
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token))
    throw new HttpsError('invalid-argument', 'הזמנה לא תקינה');
  if (r.auth?.token.email_verified !== true || !email)
    throw new HttpsError(
      'failed-precondition',
      'יש להתחבר עם האימייל המאומת שאליו נשלחה ההזמנה',
    );
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`personalInvites/${hash(token)}`),
      invite = await tx.get(ref);
    if (!invite.exists || invite.get('recipientEmailHash') !== hash(email))
      throw new HttpsError('permission-denied', 'ההזמנה מיועדת לחשבון אחר');
    const owner = invite.get('ownerUid');
    if (
      owner === uid ||
      invite.get('state') === 'revoked' ||
      invite.get('expiresAt').toMillis() < Date.now()
    )
      throw new HttpsError('failed-precondition', 'ההזמנה אינה פעילה');
    if (invite.get('state') === 'consumed') {
      if (invite.get('consumedBy') !== uid)
        throw new HttpsError('permission-denied', 'ההזמנה כבר מומשה');
      return { ownerUid: owner, alreadyUsed: true };
    }
    const [membership, card, phone, oldGrant] = await Promise.all([
      tx.get(db.doc(`memberships/${uid}`)),
      tx.get(db.doc(`personalCards/${owner}`)),
      tx.get(db.doc(`userPhones/${owner}`)),
      tx.get(db.doc(`cardAccess/${owner}_${uid}`)),
    ]);
    if (membership.exists)
      throw new HttpsError(
        'failed-precondition',
        'לחשבון זוגי נדרש אישור נפרד לשני בני הזוג',
      );
    if (!isActiveCard(card.data()) || oldGrant.get('status') === 'blocked')
      throw new HttpsError('failed-precondition', 'הכרטיס אינו זמין');
    tx.set(db.doc(`cardAccess/${owner}_${uid}`), {
      ownerUid: owner,
      matchmakerUid: uid,
      granteeUids: [uid],
      status: 'approved',
      requestedBy: 'owner',
      invited: true,
      ownerName:
        `${card.get('firstName') ?? ''} ${card.get('lastName') ?? ''}`.trim(),
      ownerPhoneHash: phone.get('phoneHash') ?? null,
      matchmakerName: name,
      cardGranted: true,
      lookingGranted: oldGrant.get('lookingGranted') === true,
      cardRequested: false,
      lookingRequested: false,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(ref, {
      state: 'consumed',
      consumedBy: uid,
      consumedAt: FieldValue.serverTimestamp(),
    });
    return { ownerUid: owner, alreadyUsed: false };
  });
});
export const confirmPersonalCardCurrent = onCall(options, async (r) => {
  const uid = user(r),
    db = getFirestore();
  if (!isActiveCard((await db.doc(`personalCards/${uid}`).get()).data()))
    throw new HttpsError('failed-precondition', 'אין כרטיס פעיל');
  await db
    .doc(`users/${uid}/private/cardActivity`)
    .set({ reviewedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { confirmed: true };
});
export const remindMyMatchmakers = onCall(options, async (r) => {
  const uid = user(r),
    db = getFirestore(),
    id = randomBytes(16).toString('hex');
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`users/${uid}/private/cardActivity`);
    const [activity, card] = await Promise.all([
      tx.get(ref),
      tx.get(db.doc(`personalCards/${uid}`)),
    ]);
    if (!isActiveCard(card.data()))
      throw new HttpsError('failed-precondition', 'אין כרטיס פעיל');
    const last = activity.get('nudgedAt') as Timestamp | undefined;
    if (last && Date.now() - last.toMillis() < 30 * 86400000)
      throw new HttpsError(
        'resource-exhausted',
        'אפשר לעדכן את החברים פעם ב־30 יום',
      );
    tx.set(ref, { nudgedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.create(db.doc(`personalNudges/${id}`), {
      ownerUid: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { sent: true };
});
export const onPersonalNudgeCreated = onDocumentCreated(
  { document: 'personalNudges/{id}', retry: true },
  async (event) => {
    const owner = event.data?.get('ownerUid');
    if (!owner) return;
    const db = getFirestore(),
      card = await db.doc(`personalCards/${owner}`).get();
    if (!isActiveCard(card.data())) return;
    const grants = await db
      .collection('cardAccess')
      .where('ownerUid', '==', owner)
      .where('status', '==', 'approved')
      .get();
    for (const grant of grants.docs) {
      if (grant.get('cardGranted') === false) continue;
      await notify(
        grant.get('matchmakerUid'),
        {
          kind: 'cardUpdated',
          title: g(
            `${card.get('firstName')} {עדכן|עדכנה} את הכרטיס {שלו|שלה}`,
            card.get('gender') as Gender,
          ),
          body: g(
            'אולי הגיע הזמן לחשוב {עליו|עליה} שוב? ❤️',
            card.get('gender') as Gender,
          ),
          route: `/card-friend/${owner}`,
          ownerUid: owner,
        },
        true,
        `cardUpdated_${event.params.id}`,
      );
    }
  },
);
export const onPersonalNewsWritten = onDocumentWritten(
  {
    document: 'personalNews/{id}',
    timeoutSeconds: 540,
    memory: '512MiB',
    retry: true,
  },
  async (event) => {
    const before = event.data?.before,
      db = getFirestore();
    const current = await db.doc(`personalNews/${event.params.id}`).get();
    const after = current.exists ? current : undefined;
    const rowId = `personalNews_${event.params.id}`;
    const oldRows = await db
      .collectionGroup('inbox')
      .where('newsId', '==', event.params.id)
      .get();
    for (let start = 0; start < oldRows.docs.length; start += 25) {
      await Promise.all(
        oldRows.docs.slice(start, start + 25).map((row) =>
          db.runTransaction(async (tx) => {
            const [liveNews, liveRow] = await Promise.all([
              tx.get(current.ref),
              tx.get(row.ref),
            ]);
            if (!liveRow.exists) return;
            if (
              !liveNews.exists ||
              liveNews.get('published') !== true ||
              liveNews.get('notify') !== true
            ) {
              tx.delete(row.ref);
            } else {
              tx.update(row.ref, {
                title: liveNews.get('title'),
                body: liveNews.get('text'),
              });
            }
          }),
        ),
      );
    }
    if (
      before?.get('imagePath') &&
      before.get('imagePath') !== after?.get('imagePath')
    )
      await getStorage()
        .bucket()
        .file(before.get('imagePath'))
        .delete({ ignoreNotFound: true });
    if (
      !after?.exists ||
      after.get('published') !== true ||
      after.get('notify') !== true
    )
      return;
    const cards = await db.collection('personalCards').get();
    for (let start = 0; start < cards.docs.length; start += 25) {
      await Promise.all(
        cards.docs.slice(start, start + 25).map(async (card) => {
          if (!isActiveCard(card.data())) return;
          await notify(
            card.id,
            {
              kind: 'personalNews',
              title: after.get('title'),
              body: after.get('text'),
              route: `/me/news/${event.params.id}`,
              newsId: event.params.id,
            },
            true,
            rowId,
          );
        }),
      );
    }
  },
);
