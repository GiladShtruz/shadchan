import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

/**
 * **A personal card's photos, for a matchmaker the owner approved — without
 * Storage's cross-service rules.**
 *
 * The app reads card photos from Storage directly, and the `personalCards/*`
 * Storage rule can only answer by reading Firestore (`cardAccess`,
 * `personalCards`, `memberships`) — which needs an IAM role on the Storage
 * service agent and a budget of Firestore reads per evaluation. When either
 * is missing the read is refused, and the matchmaker gets a card with its
 * text and none of its pictures, which is exactly what kept being reported.
 *
 * This callable is the fallback the app takes when the direct read is
 * refused. It decides with **the same rule the card document is read under**
 * (`hasApprovedAccess` in `firestore.rules`): whoever may read the card's text
 * may read its photos, and nobody else. A photo is served only while it is on
 * the card — a photo the owner removed is gone, revocation is immediate (there
 * is no URL to keep), and a deleted card serves nothing.
 */

/** The largest photo returned inline; card photos are far below it. */
export const MAX_PHOTO_BYTES = 8 * 1024 * 1024;

export interface PhotoAccessInput {
  uid: string;
  ownerUid: string;
  path: string;
  card: Record<string, unknown> | undefined;
  /** `memberships/{uid}` of the caller, if they share a database. */
  membership: Record<string, unknown> | undefined;
  /** `cardAccess/{ownerUid}_{databaseUid}` — the caller's own grant row. */
  grant: Record<string, unknown> | undefined;
}

/** Where the caller's grant row lives: their database's uid. */
export function databaseUidOf(
  uid: string,
  membership: Record<string, unknown> | undefined,
): string {
  const databaseUid = membership?.databaseUid;
  return typeof databaseUid === 'string' && databaseUid ? databaseUid : uid;
}

/** A path of exactly `personalCards/{ownerUid}/{file}`, nothing above it. */
export function validPhotoPath(ownerUid: string, path: unknown): path is string {
  if (typeof path !== 'string' || !ownerUid || ownerUid.includes('/')) {
    return false;
  }
  const parts = path.split('/');
  return (
    parts.length === 3 &&
    parts[0] === 'personalCards' &&
    parts[1] === ownerUid &&
    parts[2].length > 0 &&
    parts[2] !== '.' &&
    parts[2] !== '..'
  );
}

/**
 * Whether [input.uid] may receive [input.path]. Mirrors `hasApprovedAccess`
 * + `deleted == false` of the card document's own read rule.
 */
export function mayReadCardPhoto(input: PhotoAccessInput): boolean {
  const { uid, ownerUid, path, card, membership, grant } = input;
  if (!validPhotoPath(ownerUid, path)) return false;
  if (uid === ownerUid) return true;
  if (!card || card.deleted !== false) return false;
  const photos = Array.isArray(card.photoPaths) ? card.photoPaths : [];
  if (!photos.includes(path)) return false;
  if (!grant) return false;
  if (grant.status !== 'approved' || grant.cardGranted === false) return false;
  if (membership) {
    if (membership.state !== undefined && membership.state !== 'active') {
      return false;
    }
    const members = Array.isArray(membership.members) ? membership.members : [];
    const grantees = Array.isArray(grant.granteeUids) ? grant.granteeUids : [];
    return (
      members.includes(uid) &&
      grantees.length === members.length &&
      members.every((m) => grantees.includes(m))
    );
  }
  const grantees = Array.isArray(grant.granteeUids) ? grant.granteeUids : [uid];
  return (
    grant.matchmakerUid === uid && grantees.length === 1 && grantees[0] === uid
  );
}

export const cardPhoto = onCall(
  { region: 'europe-west1', timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid || request.auth?.token.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError('unauthenticated', 'נדרשת התחברות');
    }
    const ownerUid = request.data?.ownerUid;
    const path = request.data?.path;
    if (typeof ownerUid !== 'string' || !validPhotoPath(ownerUid, path)) {
      throw new HttpsError('invalid-argument', 'נתיב לא תקין');
    }
    const db = getFirestore();
    const [cardSnap, membershipSnap] = await Promise.all([
      db.doc(`personalCards/${ownerUid}`).get(),
      db.doc(`memberships/${uid}`).get(),
    ]);
    const membership = membershipSnap.exists ? membershipSnap.data() : undefined;
    const grantSnap = await db
      .doc(`cardAccess/${ownerUid}_${databaseUidOf(uid, membership)}`)
      .get();
    const allowed = mayReadCardPhoto({
      uid,
      ownerUid,
      path,
      card: cardSnap.exists ? cardSnap.data() : undefined,
      membership,
      grant: grantSnap.exists ? grantSnap.data() : undefined,
    });
    if (!allowed) {
      throw new HttpsError('permission-denied', 'אין גישה לכרטיס');
    }
    const file = getStorage().bucket().file(path);
    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError('not-found', 'התמונה לא נמצאה');
    }
    const [metadata] = await file.getMetadata();
    if (Number(metadata.size ?? 0) > MAX_PHOTO_BYTES) {
      throw new HttpsError('failed-precondition', 'התמונה גדולה מדי');
    }
    const [bytes] = await file.download();
    return {
      data: bytes.toString('base64'),
      contentType: metadata.contentType ?? 'image/jpeg',
    };
  },
);
