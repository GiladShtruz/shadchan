/**
 * Connections between matchmakers who already know each other
 * ("שדכנים שאני מכיר").
 *
 * **Contacts are the layer of trust.** Nobody can find a matchmaker they do
 * not already have saved in their phone: the list on the screen is the
 * server's reading of the owner's own address book (`findHelpers`), and the
 * rules let a matchmaker ask to connect only with somebody in their contacts.
 * There is no directory of strangers to browse.
 *
 * **A connection is mutual and shares nothing.** One side asks, the other
 * approves; until then nothing exists between them. Approved, it is a row
 * with two uids and two names — no card, no friend, no figure from either
 * database travels because of it. Later features (passing a card between
 * matchmakers, thinking together) will build on the row; this stage is only
 * the row.
 *
 * One document per pair, `matchmakerConnections/{a}_{b}` with the two uids
 * sorted, so two matchmakers who ask each other at the same moment land on
 * the same document and the second simply sees a request waiting for them.
 */
import { getFirestore, DocumentSnapshot } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { notify } from './notices';

/** The document id for a pair, whichever of the two asks. */
export function connectionId(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

/** How a recently joined matchmaker is announced to the contacts who have them. */
export const JOINED_NOTICE_WINDOW_DAYS = 7;

/**
 * Whether a matchmaker who has just appeared on [ownerUid]'s list is worth a
 * "[שם] הצטרף לשדכן" notice: they joined the community recently (an old
 * colleague the owner only now saved in their phone did not "join"), and the
 * two are not already connected or asking.
 */
export function joinedRecently(
  joinedAtMillis: number | null | undefined,
  nowMillis: number,
): boolean {
  if (typeof joinedAtMillis !== 'number') return false;
  const age = nowMillis - joinedAtMillis;
  return age >= -60 * 1000 && age <= JOINED_NOTICE_WINDOW_DAYS * 86400000;
}

function nameOf(doc: DocumentSnapshot, uid: string): string {
  const names = doc.get('names');
  const name =
    names && typeof names === 'object' ? (names as Record<string, unknown>)[uid] : '';
  return typeof name === 'string' ? name.trim() : '';
}

/**
 * The two notices a connection carries: a request reaches the side asked,
 * an approval reaches the side who asked. A decline says nothing to anybody —
 * the requester's own screen shows it quietly, and nobody is told "no".
 */
export const onMatchmakerConnectionWritten = onDocumentWritten(
  'matchmakerConnections/{pairId}',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) return;
    const was = before?.exists ? (before.get('status') as string) : null;
    const now = after.get('status') as string;
    const fromUid = after.get('fromUid') as string;
    const toUid = after.get('toUid') as string;
    if (typeof fromUid !== 'string' || typeof toUid !== 'string') return;
    const version = after.updateTime?.toMillis() ?? 0;
    const sameRequest =
      was === 'pending' && before?.get('fromUid') === fromUid;
    if (now === 'pending' && !sameRequest) {
      const from = nameOf(after, fromUid) || 'שדכן/ית';
      await notify(
        toUid,
        {
          kind: 'connectionRequest',
          title: `${from} רוצה להתחבר אליך בשדכן`,
          body: 'חיבור בין שדכנים שמכירים — בלי לשתף את המאגר',
          route: `/known-matchmakers/${fromUid}`,
        },
        true,
        // One row per write: a second request after a "לא עכשיו" is a new
        // one, a retried delivery of the same write is not.
        `connectionRequest_${event.params.pairId}_${version}`,
      );
    } else if (now === 'approved' && was === 'pending') {
      const to = nameOf(after, toUid) || 'השדכן/ית';
      await notify(
        fromUid,
        {
          kind: 'connectionApproved',
          title: `${to} אישר/ה את החיבור ביניכם`,
          body: 'אתם מחוברים עכשיו בשדכן',
          route: `/known-matchmakers/${toUid}`,
        },
        true,
        `connectionApproved_${event.params.pairId}_${version}`,
      );
    }
  },
);

/** Every connection [uid] is part of, for an account that is going away. */
export async function deleteConnectionsOf(uid: string): Promise<void> {
  const db = getFirestore();
  for (;;) {
    const page = await db
      .collection('matchmakerConnections')
      .where('uids', 'array-contains', uid)
      .limit(300)
      .get();
    if (page.empty) return;
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}
