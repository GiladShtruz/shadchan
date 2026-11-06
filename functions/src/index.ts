export { reconcileCoupleRecord } from './couple_dedup';
export {
  resumeCoupleMigration,
  resolveMatchmaker,
  createCoupleInvite,
  previewCoupleInvite,
  acceptCoupleInvite,
  previewCoupleSplit,
  splitCoupleWorkspace,
} from './couple_workspace';
/**
 * The server side of the personal card.
 *
 * The card itself needs no server logic: its owner writes it, the rules decide
 * who may read it, and every matchmaker's app reads it directly — so a change
 * to a card or to its owner's status reaches everybody with no fan-out here.
 * What does need a server is what no phone can do on its own behalf: telling
 * somebody else that something happened, checking a Hebrew calendar every
 * morning, and tidying up after an account that no longer exists.
 *
 * Every notification is two things written together: a row in the
 * recipient's `users/{uid}/inbox`, which the app lists, and a push to their
 * devices, which may or may not arrive. The inbox is the record; the push is
 * a courtesy.
 */
export { savePrivateLooking } from './private_looking';
import { isActiveCard } from './card_activity';
import { initializeApp } from 'firebase-admin/app';
import {
  getFirestore,
  FieldValue,
  DocumentSnapshot,
  Timestamp,
} from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { setGlobalOptions } from 'firebase-functions/v2';
import {
  onDocumentWritten,
  onDocumentCreated,
} from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as functionsV1 from 'firebase-functions/v1';
import { logger } from 'firebase-functions';
import { isHebrewBirthday, israelToday } from './hebrew_birthday';

initializeApp();
const db = getFirestore();

// The database is in `eur3`; its triggers are served from europe-west1.
const REGION = 'europe-west1';
setGlobalOptions({ region: REGION, maxInstances: 5 });

import {notify, g, Gender} from './notices';
export { createPersonalInvite, redeemPersonalInvite, revokePersonalInvite, confirmPersonalCardCurrent, remindMyMatchmakers, onPersonalNudgeCreated, onPersonalNewsWritten } from './personal_area';
/** Every matchmaker the owner has approved. */
async function approvedMatchmakers(ownerUid: string): Promise<string[]> {
  const snap = await db
    .collection('cardAccess')
    .where('ownerUid', '==', ownerUid)
    .where('status', '==', 'approved')
    .get();
  return snap.docs.filter(d => d.get('cardGranted') !== false).map((d) => d.get('matchmakerUid') as string);
}

function firstName(card: DocumentSnapshot | undefined): string {
  return ((card?.get('firstName') as string | undefined) ?? '').trim();
}

// ---------------------------------------------------------------------------
// Access requests and their answers.
// ---------------------------------------------------------------------------

export const onCardAccessWritten = onDocumentWritten(
  'cardAccess/{accessId}',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) {
      return;
    }
    const was = before?.exists ? (before.get('status') as string) : null;
    const now = after.get('status') as string;
    if (after.get('cardRequested') === true && before?.get('cardRequested') !== true) {
      await notify(after.get('ownerUid'), {kind: 'accessRequest', title: 'בקשת גישה לכרטיס שלך',
        body: `${after.get('matchmakerName')} ביקשו גישה לכרטיס שלך`, route: '/me?section=requests'});
    }
    if (
      after.get('lookingRequested') === true &&
      before?.get('lookingRequested') !== true
    ) {
      await notify(after.get('ownerUid'), {
        kind: 'accessRequest',
        title: 'בקשת גישה ל״מה אני מחפש/ת״',
        body: `${after.get('matchmakerName')} ביקשו גישה למידע הפרטי שלך`,
        route: '/me?section=requests',
      });
    }
    const gainedCard = now === 'approved' && after.get('cardGranted') !== false &&
      !(was === 'approved' && before?.get('cardGranted') !== false);
    const gainedLooking = now === 'approved' && after.get('lookingGranted') === true &&
      !(was === 'approved' && before?.get('lookingGranted') === true);
    if (was === now && !gainedCard && !gainedLooking) return;
    const ownerUid = after.get('ownerUid') as string;
    const matchmakerUid = after.get('matchmakerUid') as string;
    const ownerName = (after.get('ownerName') as string | undefined) ?? '';
    const matchmakerName =
      (after.get('matchmakerName') as string | undefined) ?? '';

    if (now === 'pending' && after.get('requestedBy') === 'matchmaker') {
      await notify(ownerUid, {
        kind: 'accessRequest',
        title: 'בקשת גישה לכרטיס שלך',
        body:
          after.get('granteeUids')?.length === 2
            ? `${matchmakerName} ביקשו ממך גישה לכרטיס שלך`
            : `${matchmakerName} רוצה לקבל גישה לכרטיס שלך`,
        // Straight to the requests on the personal area, not its top.
        route: '/me?section=requests',
      });
      // A matchmaker who joined after the owner's contacts were last read is
      // not on the owner's list of friends yet — and that list is where the
      // owner's phone finds the name they saved this friend under.
      await findHelpers(ownerUid);
    } else if (now === 'approved') {
      // "יצחק אישר גישה לכרטיס שלו" — the owner's first name, in the owner's
      // own grammatical gender, read off their card.
      const card = await db.collection('personalCards').doc(ownerUid).get();
      const ownerGender = card.get('gender') as Gender | undefined;
      const ownerFirst =
        (card.exists ? firstName(card) : '') ||
        ownerName.trim().split(/\s+/)[0] ||
        '';
      const privateOnly = !gainedCard;
      await notify(matchmakerUid, {
        kind: 'accessApproved',
        title: g(privateOnly ? `${ownerFirst} {אישר|אישרה} גישה ל״מה אני מחפש/ת״` : `${ownerFirst} {אישר|אישרה} לך גישה לכרטיס {שלו|שלה} ❤️`, ownerGender),
        body: privateOnly ? 'המידע הפרטי פתוח לעיניך בלבד' : `הכרטיס של ${ownerFirst} מתעדכן אצלך מעכשיו`,
        // Opens that friend's profile in the matchmaker's database.
        route: `/card-friend/${ownerUid}${privateOnly && after.get('ownerPhoneHash') ? '?h='+after.get('ownerPhoneHash') : ''}`,
        ownerUid,
        // Firestore refuses an undefined field, so it is only there when set.
        ...(typeof after.get('ownerPhoneHash') === 'string'
          ? { ownerPhoneHash: after.get('ownerPhoneHash') as string }
          : {}),
      });
    } else if (now === 'declined' && was === 'pending') {
      await notify(matchmakerUid, {
        kind: 'accessDeclined',
        title: 'עדכון על בקשת גישה',
        body: `הבקשה לגישה לכרטיס של ${ownerName} לא אושרה`,
        route: '/reminders',
        ownerUid,
      });
    }
  },
);

// ---------------------------------------------------------------------------
// A card appearing, and a wedding.
// ---------------------------------------------------------------------------

function fullName(card: DocumentSnapshot | undefined): string {
  const last = ((card?.get('lastName') as string | undefined) ?? '').trim();
  return `${firstName(card)} ${last}`.trim();
}

/**
 * "X הוסיף/ה כרטיס אישי" to one matchmaker — once per card, ever, however
 * many ways the server learns they know each other. Only the first few of a
 * burst are pushed; every one lands in the inbox.
 */
async function announceOnce(
  card: DocumentSnapshot,
  ownerUid: string,
  matchmakerUid: string,
  ownerPhoneHash: string | undefined,
  push: boolean,
): Promise<boolean> {
  if (matchmakerUid === ownerUid || !isActiveCard(card.data()) ||
      !await mutualContacts(ownerUid, matchmakerUid)) {
    return false;
  }
  // A card the owner hid from this matchmaker, an owner who takes no
  // requests, or one who chose not to tell anybody ("לעדכן חברים שלך…" off),
  // is never announced.
  const row = await db
    .collection('cardAccess')
    .doc(`${ownerUid}_${matchmakerUid}`)
    .get();
  if (row.exists && row.get('status') === 'blocked') {
    return false;
  }
  const phoneHash = ownerPhoneHash ?? (await ownerPhoneHashOf(ownerUid));
  if (phoneHash) {
    const entry = await db.collection('phoneDirectory').doc(phoneHash).get();
    if (
      entry.exists &&
      (entry.get('acceptsRequests') === false ||
        entry.get('announces') === false)
    ) {
      return false;
    }
  }
  const membership = await db.doc(`memberships/${matchmakerUid}`).get();
  const recipient =
    membership.get('state') === 'active'
      ? membership.get('databaseUid')
      : matchmakerUid;
  const marker = card.ref.collection('announced').doc(recipient);
  const created = await db.runTransaction(async (tx) => {
    if ((await tx.get(marker)).exists) {
      return false;
    }
    tx.set(marker, { at: FieldValue.serverTimestamp() });
    return true;
  });
  if (!created) {
    return false;
  }
  const gender = card.get('gender') as Gender | undefined;
  await notify(
    matchmakerUid,
    {
      kind: 'cardCreated',
      title: g(`${fullName(card)} {הוסיף|הוסיפה} כרטיס אישי`, gender),
      body: 'אפשר לבקש גישה לפרטים',
      route: '/reminders',
      ownerUid,
      ownerPhoneHash,
    },
    push,
  );
  return true;
}

async function ownerPhoneHashOf(ownerUid: string): Promise<string | undefined> {
  const doc = await db.collection('userPhones').doc(ownerUid).get();
  return (doc.get('phoneHash') as string | undefined) || undefined;
}

/**
 * Tells the matchmakers who know the owner that the owner now has a card they
 * may ask for: every matchmaker who keeps the owner in their database (by
 * the hash of the owner's number, from `databaseHashes`), and every
 * matchmaker saved in the owner's own address book.
 */
async function announceCard(ownerUid: string): Promise<void> {
  const card = await db.collection('personalCards').doc(ownerUid).get();
  if (!isActiveCard(card.data())) {
    return;
  }
  const ownerPhoneHash = await ownerPhoneHashOf(ownerUid);
  const recipients = new Set<string>();

  if (ownerPhoneHash) {
    const holders = await db
      .collection('databaseHashes')
      .where('hashes', 'array-contains', ownerPhoneHash)
      .get();
    for (const doc of holders.docs) {
      recipients.add(doc.id);
    }
  }

  const contacts = await db.collection('contactHashes').doc(ownerUid).get();
  const hashes: string[] =
    (contacts.get('hashes') as string[] | undefined) ?? [];
  const refs = hashes.map((h) => db.collection('phoneDirectory').doc(h));
  for (let i = 0; i < refs.length; i += 100) {
    const entries = await db.getAll(...refs.slice(i, i + 100));
    for (const entry of entries) {
      const uid = entry.get('uid') as string | undefined;
      if (entry.exists && entry.get('matchmaker') === true && uid) {
        recipients.add(uid);
      }
    }
  }

  recipients.delete(ownerUid);
  for (const matchmakerUid of recipients) {
    await announceOnce(card, ownerUid, matchmakerUid, ownerPhoneHash, true);
  }
}

/**
 * A matchmaker's database changed: any friend just added who already keeps a
 * card is announced to them, as if the card had been written now.
 */
export const onDatabaseHashesWritten = onDocumentWritten(
  'databaseHashes/{matchmakerUid}',
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) {
      return;
    }
    const matchmakerUid = event.params.matchmakerUid;
    const before = new Set<string>(
      (event.data?.before?.get('hashes') as string[] | undefined) ?? [],
    );
    const added = ((after.get('hashes') as string[] | undefined) ?? [])
      .filter((h) => !before.has(h))
      .slice(0, 3000);
    let pushed = 0;
    for (let i = 0; i < added.length; i += 100) {
      const refs = added
        .slice(i, i + 100)
        .map((h) => db.collection('phoneDirectory').doc(h));
      const entries = await db.getAll(...refs);
      for (const entry of entries) {
        const ownerUid = entry.get('uid') as string | undefined;
        if (!entry.exists || entry.get('hasCard') !== true || !ownerUid) {
          continue;
        }
        const card = await db.collection('personalCards').doc(ownerUid).get();
        if (!isActiveCard(card.data())) {
          continue;
        }
        const told = await announceOnce(
          card,
          ownerUid,
          matchmakerUid,
          entry.id,
          pushed < 3,
        );
        if (told) {
          pushed++;
        }
      }
    }
  },
);

/**
 * The owner's number arrived (or changed) after the card: the matchmakers who
 * keep that number are found now.
 */
export const onUserPhoneWritten = onDocumentWritten(
  'userPhones/{ownerUid}',
  async (event) => {
    const before = event.data?.before?.get('phoneHash');
    const after = event.data?.after?.get('phoneHash');
    if (after && after !== before) {
      await refreshContactNeighbours(event.params.ownerUid);
      await announceCard(event.params.ownerUid);
    }
  },
);

export const onPersonalCardWritten = onDocumentWritten(
  'personalCards/{ownerUid}',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const ownerUid = event.params.ownerUid;
    if (!after?.exists) {
      await refreshContactNeighbours(ownerUid);
      return;
    }
    const ignored = new Set(['updatedAt', 'statusUpdatedAt', 'joinedAt']);
    const changed = Object.keys(after.data() ?? {}).some(key => !ignored.has(key) && JSON.stringify(before?.get(key)) !== JSON.stringify(after.get(key)));
    if (changed) {
      const sourceAt = after.updateTime ?? Timestamp.now();
      await db.runTransaction(async tx => {
        const ref = db.doc(`users/${ownerUid}/private/cardActivity`);
        const [activity, current] = await Promise.all([tx.get(ref), tx.get(after.ref)]);
        if (!activity.get('editedAt') || activity.get('editedAt').toMillis() < sourceAt.toMillis()) tx.set(ref, {editedAt: sourceAt}, {merge: true});
        if (before?.get('status') !== after.get('status') && current.get('status') === after.get('status') &&
            (!current.get('statusUpdatedAt') || current.get('statusUpdatedAt').toMillis() < sourceAt.toMillis())) tx.update(after.ref, {statusUpdatedAt: sourceAt});
      });
    }
    if (before?.get('deleted') !== after.get('deleted')) await refreshContactNeighbours(ownerUid);
    if (!isActiveCard(before?.data()) && isActiveCard(after.data())) {
      await db.runTransaction(async tx => {
        const current = await tx.get(after.ref);
        if (!current.get('joinedAt')) tx.update(after.ref, {joinedAt: FieldValue.serverTimestamp()});
      });
      await refreshContactNeighbours(ownerUid);
      await announceCard(ownerUid);
      return;
    }

  },
);

/**
 * The matchmakers in a card owner's address book — "חברים שיכולים לעזור לי".
 *
 * Worked out here because only the server may read the phone directory as a
 * whole: a client can look a number up, never list it. The answer is written
 * where only the owner can read it.
 */
export async function mutualContacts(a: string, b: string): Promise<boolean> {
  if (a === b) return false;
  const [ap, bp, ac, bc] = await Promise.all([
    db.doc(`userPhones/${a}`).get(), db.doc(`userPhones/${b}`).get(),
    db.doc(`contactHashes/${a}`).get(), db.doc(`contactHashes/${b}`).get(),
  ]);
  const ah = ap.get('phoneHash'), bh = bp.get('phoneHash');
  if (typeof ah !== 'string' || typeof bh !== 'string' ||
      !(ac.get('hashes') ?? []).includes(bh) || !(bc.get('hashes') ?? []).includes(ah)) return false;
  const [ad, bd] = await Promise.all([db.doc(`phoneDirectory/${ah}`).get(), db.doc(`phoneDirectory/${bh}`).get()]);
  return ad.get('uid') === a && bd.get('uid') === b;
}

/**
 * Every matchmaker the owner has saved in their phone, and the single friends
 * with a card who saved the owner back.
 *
 * **The two lists answer two different questions, so they have two rules.**
 * "Which of my contacts matchmake here?" is the owner's own address book
 * read back to them: a matchmaker is somebody who offers to think about
 * friends, the owner already has their number, and the request rule
 * (`inOwnersContacts`) is one-directional for exactly the same reason. It
 * used to demand that the matchmaker had *also* uploaded contacts and saved
 * the owner — so a friend who matchmakes from a database typed by hand, or
 * never let the app read their contacts, was simply missing from the list.
 * Whether a *single* keeps a card is the more private fact, and stays
 * reciprocal ([mutualContacts]).
 */
async function findHelpers(ownerUid: string): Promise<void> {
  const contacts = await db.doc(`contactHashes/${ownerUid}`).get();
  const hashes: string[] = contacts.get('hashes') ?? [];
  const helpers: Record<string, unknown>[] = [], friends: Record<string, unknown>[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < hashes.length; i += 100) {
    const entries = await db.getAll(...hashes.slice(i, i + 100).map(h => db.doc(`phoneDirectory/${h}`)));
    for (const entry of entries) {
      const uid = entry.get('uid');
      if (!entry.exists || typeof uid !== 'string' || uid === ownerUid || seen.has(uid)) continue;
      // The entry must still be the one its account published as its own
      // number, or a number could be claimed for somebody else's list.
      if ((await db.doc(`userPhones/${uid}`).get()).get('phoneHash') !== entry.id) continue;
      seen.add(uid);
      const matchmaker = entry.get('matchmaker') === true;
      const single = entry.get('hasCard') === true && entry.get('announces') !== false;
      if (!matchmaker && !single) continue;
      const mutual = single ? await mutualContacts(ownerUid, uid) : false;
      if (!matchmaker && !mutual) continue;
      const member = await db.doc(`communityMembers/${uid}`).get();
      const activity = await db.doc(`matchmakerActivity/${uid}`).get();
      const row = {uid, name: entry.get('name') ?? '', phoneHash: entry.id,
        photoUrl: member.get('hidden') === false && typeof member.get('photoUrl') === 'string' && member.get('photoUrl').trim() ? member.get('photoUrl') : null,
        databaseCount: activity.get('databaseCount') ?? null,
        lastActiveAt: activity.get('lastActiveAt') ?? null,
        // When they joined as a matchmaker, so the newest friends lead.
        joinedAt: member.get('joinedAt') ?? null};
      if (matchmaker) {
        const membership = await db.doc(`memberships/${uid}`).get();
        helpers.push({...row, name: membership.get('state') === 'active' ? membership.get('name') : row.name,
          recipientUid: membership.get('state') === 'active' ? membership.get('databaseUid') : uid,
          granteeUids: membership.get('state') === 'active' ? membership.get('members') : [uid]});
      }
      if (mutual && isActiveCard((await db.doc(`personalCards/${uid}`).get()).data())) {
        // Presence only. No candidate details or personal-card photograph.
        friends.push({uid, name: row.name, phoneHash: entry.id});
      }
    }
  }
  const ref = db.doc(`users/${ownerUid}/private/helpers`);
  await ref.set({helpers, friends, updatedAt: FieldValue.serverTimestamp()});
  const card = await db.doc(`personalCards/${ownerUid}`).get();
  if (isActiveCard(card.data())) {
    for (const helper of helpers) {
      const uid = helper.uid as string;
      const grant = await db.doc(`cardAccess/${ownerUid}_${uid}`).get();
      if (grant.get('status') === 'approved' || grant.get('status') === 'blocked') continue;
      // Asked as the question it is, in the owner's own grammatical gender.
      // The helper's gender is not known here (and a couple account is two
      // people), so the friend's side is phrased without one.
      await notify(ownerUid, {kind: 'friendJoined', title: `${helper.name} בשדכן!`,
        body: g('רוצה לתת גישה לכרטיס שלך, כדי שיוכלו לחשוב {עליך|עלייך}? ❤️', card.get('gender') as Gender),
        route: `/me?section=helpers&friend=${uid}`}, true, `friendJoined_${uid}`);
    }
  }
}

async function refreshContactNeighbours(uid: string): Promise<void> {
  await findHelpers(uid);
  const hash = await ownerPhoneHashOf(uid);
  if (!hash) return;
  const owners = await db.collection('contactHashes').where('hashes', 'array-contains', hash).get();
  for (const owner of owners.docs) if (owner.id !== uid) await findHelpers(owner.id);
}

export const onPersonalMemberActivity = onDocumentWritten('communityMembers/{uid}', async event => {
  await refreshContactNeighbours(event.params.uid);
  await refreshPersonalCardCount();
});

/**
 * A matchmaker's number reached the directory (or left it, or they renamed
 * themselves): every card owner who has that number saved gets their list of
 * friends who can help worked out again.
 *
 * Without this the list only moved when the *owner's* address book did, so a
 * matchmaker who had the app long before and only now added "המספר שלי" was
 * missing from it until the owner's contacts happened to be uploaded again.
 */
export const onPhoneDirectoryWritten = onDocumentWritten(
  'phoneDirectory/{phoneHash}',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const wasUid =
      before?.exists && before.get('matchmaker') === true
        ? (before.get('uid') as string | undefined)
        : undefined;
    const nowUid =
      after?.exists && after.get('matchmaker') === true
        ? (after.get('uid') as string | undefined)
        : undefined;
    if (!before?.exists && !after?.exists) return;
    const owners = await db
      .collection('contactHashes')
      .where('hashes', 'array-contains', event.params.phoneHash)
      .get();
    for (const doc of owners.docs) {
      if (doc.id !== nowUid && doc.id !== wasUid) {
        await findHelpers(doc.id);
      }
    }
  },
);

/**
 * An address book uploaded (or refreshed) works out who can help, and still
 * announces a card created before it.
 */
export const onContactHashesWritten = onDocumentWritten(
  'contactHashes/{ownerUid}',
  async (event) => {
    await refreshContactNeighbours(event.params.ownerUid);
    await announceCard(event.params.ownerUid);
  },
);

// ---------------------------------------------------------------------------
// "השראה מהקהילה" — how many matchmakers use each tag word
// ---------------------------------------------------------------------------

/** Words that name a circle — an institution, a unit, a workplace. */
const CIRCLE_WORDS = [
  'ישיבה',
  'ישיבת',
  'מדרשה',
  'מדרשת',
  'אולפנה',
  'אולפנת',
  'מכינה',
  'מכינת',
  'סמינר',
  'כולל',
  'קהילה',
  'קהילת',
  'בית כנסת',
  'גרעין',
  'יחידה',
  'יחידת',
  'גדוד',
  'חטיבה',
  'חטיבת',
  'סיירת',
  'שייטת',
  'מקום עבודה',
  'מהעבודה',
  'משרד',
  'אוניברסיטה',
  'אוניברסיטת',
  'מכללה',
  'מכללת',
  'תיכון',
  'בית ספר',
  'אולפן',
  'סניף',
  'שבט',
  'מחזור',
  'שכונה',
  'שכונת',
  'בני עקיבא',
  'עזרא',
];

/**
 * The same filter the app runs before publishing, run again here: a second
 * chance to keep a personal circle out of the shared words. Places are
 * filtered on the phone, which knows the matchmaker's own cities.
 */
function shareableTag(tag: string): boolean {
  const value = tag.trim();
  if (value.length < 2 || value.length > 24) return false;
  if (/\d/.test(value)) return false;
  if (/(^|\s)(חבר|חברה|חברים|חברות|מכרים|מכר|מכרה)\s+(מ|של|מה)/.test(value)) {
    return false;
  }
  return !CIRCLE_WORDS.some((word) => value.includes(word));
}

/** The document id two spellings of one word share. */
function tagKey(tag: string): string {
  return tag
    .replace(/"/g, '״')
    .replace(/'/g, '׳')
    .replace(/[״׳"'\-_./\s]/g, '')
    .toLowerCase()
    .slice(0, 60);
}

function tagsOf(snapshot: DocumentSnapshot | undefined): Map<string, string> {
  const tags = new Map<string, string>();
  const raw = snapshot?.exists ? snapshot.get('tags') : undefined;
  if (Array.isArray(raw)) {
    for (const item of raw.slice(0, 200)) {
      if (typeof item === 'string' && shareableTag(item)) {
        const key = tagKey(item);
        if (key.length >= 2 && !tags.has(key)) tags.set(key, item.trim());
      }
    }
  }
  return tags;
}

/**
 * `tagUsage/{uid}` changed: every word it gained counts one more matchmaker,
 * every word it lost one fewer. Only the count and the word are kept — never
 * who uses it.
 */
export const onTagUsageWritten = onDocumentWritten(
  'tagUsage/{uid}',
  async (event) => {
    const before = tagsOf(event.data?.before);
    const after = tagsOf(event.data?.after);
    const changes: Array<[string, string, number]> = [];
    for (const [key, label] of after) {
      if (!before.has(key)) changes.push([key, label, 1]);
    }
    for (const [key, label] of before) {
      if (!after.has(key)) changes.push([key, label, -1]);
    }
    for (const [key, label, delta] of changes) {
      const ref = db.collection('communityTags').doc(key);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref);
        const users =
          ((current.exists ? current.get('users') : 0) ?? 0) + delta;
        if (users <= 0) {
          tx.delete(ref);
        } else {
          tx.set(
            ref,
            {
              label: current.exists ? (current.get('label') ?? label) : label,
              users,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      });
    }
  },
);

// ---------------------------------------------------------------------------
// "Yitzchak marked you busy — is that right?"
// ---------------------------------------------------------------------------

export const onStatusReportCreated = onDocumentCreated(
  'statusReports/{reportId}',
  async () => {
    // Retained as a no-op while older builds retire: internal status changes never reach the owner.
  },
);

// ---------------------------------------------------------------------------
// Hebrew birthdays, every morning.
// ---------------------------------------------------------------------------

export const hebrewBirthdays = onSchedule(
  { schedule: '30 8 * * *', timeZone: 'Asia/Jerusalem' },
  async () => {
    const today = israelToday();
    const cards = await db
      .collection('personalCards')
      .where('deleted', '==', false)
      .get();
    let sent = 0;
    for (const card of cards.docs) {
      const born = card.get('dateOfBirth') as string | null | undefined;
      if (!born || !isHebrewBirthday(born, today)) {
        continue;
      }
      const name = firstName(card);
      for (const matchmakerUid of await approvedMatchmakers(card.id)) {
        await notify(matchmakerUid, {
          kind: 'birthday',
          title: `היום יום ההולדת של ${name} 🎂`,
          body: 'אפשר לשלוח ברכה בוואטסאפ',
          route: '/reminders',
          ownerUid: card.id,
        });
        sent += 1;
      }
    }
    logger.info('hebrewBirthdays', { cards: cards.size, sent });
  },
);

// ---------------------------------------------------------------------------
// Account deletion.
// ---------------------------------------------------------------------------

async function deleteQuery(
  collection: string,
  field: string,
  uid: string,
): Promise<void> {
  for (;;) {
    const page = await db
      .collection(collection)
      .where(field, '==', uid)
      .limit(300)
      .get();
    if (page.empty) {
      return;
    }
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

/**
 * Everything the personal card put on the server under this account, when
 * the account itself is deleted. The rules never let a client delete a card
 * document (a deleted card is only a flag, so it can be restored), and a
 * matchmaker can never delete a block — so erasing them is the server's job.
 */
export const onAccountDeleted = functionsV1
  .region(REGION)
  .auth.user()
  .onDelete(async (user) => {
    const uid = user.uid;
    const cardRef = db.collection('personalCards').doc(uid);
    await db.recursiveDelete(cardRef);
    await db.doc(`privateLooking/${uid}`).delete();
    await getStorage()
      .bucket()
      .deleteFiles({ prefix: `privateLooking/${uid}/` });
    await deleteQuery('cardAccess', 'ownerUid', uid);
    await deleteQuery('cardAccess', 'matchmakerUid', uid);
    await deleteQuery('personalInvites', 'ownerUid', uid);
    await deleteQuery('personalInvites', 'consumedBy', uid);
    await deleteQuery('personalNudges', 'ownerUid', uid);
    await deleteQuery('statusReports', 'ownerUid', uid);
    await deleteQuery('statusReports', 'matchmakerUid', uid);
    await deleteQuery('phoneDirectory', 'uid', uid);
    await db.collection('userPhones').doc(uid).delete();
    await db.collection('contactHashes').doc(uid).delete();
    await db.collection('databaseHashes').doc(uid).delete();
    await db.collection('fcmTokens').doc(uid).delete();
    await db.doc(`matchmakerActivity/${uid}`).delete();
    // Deleting it counts this matchmaker out of every tag word they used.
    await db.collection('tagUsage').doc(uid).delete();
    // The support view of this account's sync (counts and error codes).
    await db.collection('accountHealth').doc(uid).delete();
    await db.recursiveDelete(
      db.collection('users').doc(uid).collection('inbox'),
    );
    await db.recursiveDelete(
      db.collection('users').doc(uid).collection('private'),
    );
    try {
      await getStorage()
        .bucket()
        .deleteFiles({ prefix: `personalCards/${uid}/` });
    } catch (error) {
      logger.warn('onAccountDeleted: photos', { uid, error: String(error) });
    }
    logger.info('onAccountDeleted', { uid });
  });

/**
 * The end of an account's 30 days of grace.
 *
 * Deleting an account in the app does not delete it: it writes
 * `users/{uid}.deletion` with a `purgeAfter` date and signs out, and signing
 * back in before then offers to restore everything. This runs once a day and
 * finishes the job for every account whose date has passed — the database,
 * its photos and recordings, what it published to the community, and finally
 * the Authentication user itself, whose deletion runs [onAccountDeleted] for
 * everything the personal card left behind.
 *
 * Apple sign-in was already revoked when the deletion was requested, while a
 * fresh authorisation code was in hand; there is no way to do it from here.
 */
export const purgeDeletedAccounts = onSchedule(
  { schedule: '15 3 * * *', timeZone: 'Asia/Jerusalem', timeoutSeconds: 540 },
  async () => {
    const due = await db
      .collection('users')
      .where('deletion.purgeAfter', '<=', Timestamp.now())
      .limit(50)
      .get();
    let purged = 0;
    for (const account of due.docs) {
      const uid = account.id;
      try {
        await purgeAccount(uid);
        purged += 1;
      } catch (error) {
        logger.error('purgeDeletedAccounts', { uid, error: String(error) });
      }
    }
    logger.info('purgeDeletedAccounts', { due: due.size, purged });
  },
);

async function purgeAccount(uid: string): Promise<void> {
  if ((await db.doc(`memberships/${uid}`).get()).exists) {
    throw new Error('Split the couple workspace before purging an account');
  }
  const bucket = getStorage().bucket();
  await bucket.deleteFiles({ prefix: `users/${uid}/` });
  await bucket.deleteFiles({ prefix: `communityMembers/${uid}/` });
  await db.collection('communityMembers').doc(uid).delete();
  await deleteQuery('communityEngagements', 'authorUid', uid);
  await deleteQuery('tips', 'authorUid', uid);
  await deleteQuery('communityMazelTov', 'fromUid', uid);
  await deleteQuery('communityMazelTov', 'toUid', uid);
  await db.collection('accountHealth').doc(uid).delete();
  // The whole tree under users/{uid}: every record, tombstone, setting,
  // the inbox and the deletion marker itself.
  await db.recursiveDelete(db.collection('users').doc(uid));
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    // Already gone — deleted from the app during the grace period.
    if ((error as { code?: string }).code !== 'auth/user-not-found') {
      throw error;
    }
  }
}

/** Aggregate includes legacy cards as well. Never exposes a person's identity. */
async function refreshPersonalCardCount(): Promise<void> {
  const startedAt = Date.now();
  const cards = await db
    .collection('personalCards')
    .select('description', 'photoPaths', 'deleted', 'joinedAt')
    .get();
  const count = cards.docs.filter((d) => isActiveCard(d.data())).length;
  const now = new Date(new Date().toLocaleString('en-US', {timeZone: 'Asia/Jerusalem'}));
  const sunday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
  const two = (n: number) => String(n).padStart(2, '0');
  const weekKey = `W${sunday.getFullYear()}-${two(sunday.getMonth()+1)}-${two(sunday.getDate())}`;
  const members = await db.collection('communityMembers').get();
  const current = members.docs.filter(d => d.get('weekKey') === weekKey);
  const sum = (field: string) => current.reduce((n, d) => n + (typeof d.get(field) === 'number' ? d.get(field) : 0), 0);
  const joinedThisWeek = (value: unknown) => value instanceof Timestamp &&
    new Date(value.toDate().toLocaleString('en-US', {timeZone: 'Asia/Jerusalem'})) >= sunday;
  const activity = await db.collection('matchmakerActivity').get();
  // The calendar month in Israel — "X הצטרפו החודש" on the personal home.
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthKey = `M${monthStart.getFullYear()}-${two(monthStart.getMonth()+1)}`;
  const joinedThisMonth = (value: unknown) => value instanceof Timestamp &&
    new Date(value.toDate().toLocaleString('en-US', {timeZone: 'Asia/Jerusalem'})) >= monthStart;
  const totals = {singles: count, weekKey, monthKey,
    newSinglesWeek: cards.docs.filter(d => isActiveCard(d.data()) && joinedThisWeek(d.get('joinedAt'))).length,
    newSinglesMonth: cards.docs.filter(d => isActiveCard(d.data()) && joinedThisMonth(d.get('joinedAt'))).length,
    newMatchmakersWeek: members.docs.filter(d => joinedThisWeek(d.get('joinedAt'))).length,
    activeMatchmakers: activity.docs.filter(d => joinedThisWeek(d.get('lastActiveAt'))).length,
    couplesWeek: sum('weekCouples'), engagementsWeek: sum('weekEngagements')};
  const ref = db.doc('publicStats/personalCards');
  await db.runTransaction(async (tx) => {
    const previous = await tx.get(ref);
    if ((previous.get('startedAt') ?? 0) > startedAt) return;
    tx.set(ref, { count, startedAt, updatedAt: FieldValue.serverTimestamp() });
    tx.set(db.doc('publicStats/personalArea'), {...totals, startedAt, updatedAt: FieldValue.serverTimestamp()});
  });
}
export const updatePersonalCardCount = onDocumentWritten(
  'personalCards/{uid}',
  async () => refreshPersonalCardCount(),
);
export const refreshPersonalCardCommunity = onSchedule(
  { schedule: 'every 60 minutes' },
  refreshPersonalCardCount,
);

/** Recovery snapshots and closed workspace files have a bounded retention window. */
export const purgeWorkspaceRecovery = onSchedule(
  { schedule: '45 3 * * *', timeoutSeconds: 540 },
  async () => {
    for (const collection of ['coupleArchives', 'coupleData']) {
      const expired = await db
        .collection(collection)
        .where('purgeAfter', '<=', Timestamp.now())
        .limit(100)
        .get();
      for (const doc of expired.docs) {
        if (collection === 'coupleData')
          await getStorage()
            .bucket()
            .deleteFiles({ prefix: `coupleFiles/${doc.id}/` });
        await db.recursiveDelete(doc.ref);
      }
    }
  },
);

/** Invitations expire without removing access already explicitly granted. */
export const purgeExpiredPersonalInvites = onSchedule({schedule: '20 4 * * *', timeZone: 'Asia/Jerusalem'}, async () => {
  const expired = await db.collection('personalInvites').where('expiresAt', '<=', Timestamp.now()).limit(500).get();
  const oldOutbox = await db.collection('personalNudges').where('createdAt', '<=', Timestamp.fromMillis(Date.now() - 60 * 86400000)).limit(500).get();
  const writer = db.bulkWriter();
  for (const doc of [...expired.docs, ...oldOutbox.docs]) writer.delete(doc.ref);
  await writer.close();
});

export const onMatchmakerActivityWritten = onDocumentWritten('matchmakerActivity/{uid}', async event => {
  await refreshContactNeighbours(event.params.uid);
  await refreshPersonalCardCount();
});
