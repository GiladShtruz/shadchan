/**
 * Sharing between two matchmakers (2026-11-20) — the server side.
 *
 * **One direction, one pair, one decision.** `matchmakerShares/{owner}_{reader}`
 * says what [owner] shares with [reader] — the whole database, friends picked
 * one by one, or everything except some — or nothing ("none"); [reader] may
 * only ask ("requested"). Matchmakers who know each other from the phone book
 * see each other without any request; a share is the only thing that is
 * ever decided, and it is decided for one matchmaker at a time.
 *
 * Replaces the mutual `matchmakerConnections` model, which was deleted
 * without a migration.
 *
 * What only the server does here:
 *  - tell the other side, once, about a new share, a request, or a share
 *    that stopped — the three moves worth a push;
 *  - make a stop take effect at once even if the owner's phone never gets
 *    to rewrite its cards: the reader is taken off every `networkCards` row
 *    of that owner (a card nobody reads any more is removed);
 *  - erase all of it with the account.
 */
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { notify } from './notices';

/** A sorted pair id — still used for a couple space's `partnerships`. */
export function connectionId(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

/** How a recently joined matchmaker is announced to the contacts who have them. */
export const JOINED_NOTICE_WINDOW_DAYS = 7;

/** Whether a matchmaker joined recently enough to be announced. */
export function joinedRecently(
  joinedAtMillis: number | null | undefined,
  nowMillis: number,
): boolean {
  if (typeof joinedAtMillis !== 'number') return false;
  const age = nowMillis - joinedAtMillis;
  return age >= -60 * 1000 && age <= JOINED_NOTICE_WINDOW_DAYS * 86400000;
}

const ACTIVE = new Set(['all', 'selected', 'allExcept']);

/** Whether [mode] shares anything. */
export function isActiveShare(mode: unknown): boolean {
  return typeof mode === 'string' && ACTIVE.has(mode);
}

export interface ShareNotice {
  to: 'owner' | 'reader';
  kind: 'shareRequest' | 'shareOpened' | 'shareStopped';
  title: string;
  body: string;
}

/**
 * The one notice a move of a share row carries, or null. Pure, so it is
 * tested. A change between two active modes (all → selected) says nothing:
 * the reader simply sees what they see.
 */
export function shareNotice(
  was: string | null,
  now: string | null,
  ownerName: string,
  readerName: string,
): ShareNotice | null {
  const owner = ownerName.trim() || 'שדכן/ית';
  const reader = readerName.trim() || 'שדכן/ית';
  if (now === 'requested' && was !== 'requested') {
    return {
      to: 'owner',
      kind: 'shareRequest',
      title: `${reader} מבקש/ת שתשתף/י איתו/ה כרטיסים`,
      body: 'את/ה מחליט/ה מה לשתף — כל המאגר, אנשים נבחרים או כלום',
    };
  }
  if (isActiveShare(now) && !isActiveShare(was)) {
    return {
      to: 'reader',
      kind: 'shareOpened',
      title: `${owner} פתח/ה איתך שיתוף כרטיסים`,
      body: 'הכרטיסים זמינים לך לצפייה · רוצה לשתף בחזרה?',
    };
  }
  if (isActiveShare(was) && !isActiveShare(now)) {
    return {
      to: 'reader',
      kind: 'shareStopped',
      title: `${owner} הפסיק/ה לשתף איתך כרטיסים`,
      body: 'רעיונות שכבר נפתחו נשארים אצלך',
    };
  }
  return null;
}

/** Takes [readerUid] off every card [ownerUid] publishes. */
export async function revokeReader(ownerUid: string, readerUid: string): Promise<void> {
  const db = getFirestore();
  for (;;) {
    const page = await db
      .collection('networkCards')
      .where('ownerUid', '==', ownerUid)
      .where('readers', 'array-contains', readerUid)
      .limit(300)
      .get();
    if (page.empty) return;
    const batch = db.batch();
    for (const d of page.docs) {
      const readers = ((d.get('readers') as string[]) ?? []).filter((r) => r !== readerUid);
      if (readers.length === 0) batch.delete(d.ref);
      else batch.update(d.ref, { readers: FieldValue.arrayRemove(readerUid) });
    }
    await batch.commit();
  }
}

export const onMatchmakerShareWritten = onDocumentWritten(
  'matchmakerShares/{shareId}',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const row = after?.exists ? after : before;
    if (!row?.exists) return;
    const ownerUid = row.get('ownerUid') as string;
    const readerUid = row.get('readerUid') as string;
    if (typeof ownerUid !== 'string' || typeof readerUid !== 'string') return;
    const was = before?.exists ? (before.get('mode') as string) : null;
    const now = after?.exists ? (after.get('mode') as string) : null;
    if (was === now) return;
    if (isActiveShare(was) && !isActiveShare(now)) {
      try {
        await revokeReader(ownerUid, readerUid);
      } catch (error) {
        logger.warn('onMatchmakerShareWritten: revoke', { error: String(error) });
      }
    }
    const notice = shareNotice(
      was,
      now,
      (row.get('ownerName') as string) ?? '',
      (row.get('readerName') as string) ?? '',
    );
    if (!notice) return;
    const to = notice.to === 'owner' ? ownerUid : readerUid;
    const other = notice.to === 'owner' ? readerUid : ownerUid;
    const version = after?.updateTime?.toMillis() ?? Date.now();
    await notify(
      to,
      {
        kind: notice.kind,
        title: notice.title,
        body: notice.body,
        route: `/known-matchmakers/${other}`,
      },
      true,
      `${notice.kind}_${event.params.shareId}_${version}`,
    );
  },
);

/** Every share [uid] is part of, for an account that is going away. */
export async function deleteSharesOf(uid: string): Promise<void> {
  const db = getFirestore();
  for (;;) {
    const page = await db
      .collection('matchmakerShares')
      .where('uids', 'array-contains', uid)
      .limit(300)
      .get();
    if (page.empty) break;
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  for (;;) {
    const page = await db.collection('networkCards').where('ownerUid', '==', uid).limit(300).get();
    if (page.empty) break;
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  for (;;) {
    const page = await db
      .collection('networkCards')
      .where('readers', 'array-contains', uid)
      .limit(300)
      .get();
    if (page.empty) break;
    const batch = db.batch();
    page.docs.forEach((d) => batch.update(d.ref, { readers: FieldValue.arrayRemove(uid) }));
    await batch.commit();
  }
}
