export {
  reconcileCouplePeople,
  reconcileCouplePersonNotes,
  reconcileCouplePersonEvents,
  reconcileCoupleMatches,
  reconcileCoupleMatchNotes,
  reconcileCoupleMatchStatusEvents,
} from './couple_dedup';
export {
  resumeCoupleMigration,
  rollbackCoupleMigration,
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
export { restoreRevokedGrants } from './grant_restore';
export { cardPhoto } from './card_photos';
export {
  sharedCardPhoto,
  onIdeaProposalWritten,
  onChatMessageCreated,
  onCardAccessShareOnward,
  onPersonalCardDeletedUnshare,
  onPartnershipWritten,
} from './network';
import { deleteNetworkOf, deletePartnerCardsOf } from './network';
import { isActiveCard } from './card_activity';
import { initializeApp } from 'firebase-admin/app';
import {
  getFirestore,
  AggregateField,
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
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { isSupportAdminEmail, writeAdminStats } from './admin_stats';
import { sendDueReminders } from './reminders';
import { checkThresholds, dashboard, deleteAnalyticsOf, processBatch, userDetail } from './analytics_store';
import * as functionsV1 from 'firebase-functions/v1';
import { logger } from 'firebase-functions';
import { isHebrewBirthday, israelToday, hebrewMonthKey } from './hebrew_birthday';
import {
  activityChange,
  helperListChanged,
  memberListFieldsChanged,
  patchHelperRows,
  sameFigures,
  stableJson,
} from './read_budget';
import { createHash } from 'node:crypto';

initializeApp();
const db = getFirestore();

// The database is in `eur3`; its triggers are served from europe-west1.
const REGION = 'europe-west1';
setGlobalOptions({ region: REGION, maxInstances: 5 });

import {notify, g, Gender} from './notices';
import { joinedRecently, deleteSharesOf } from './matchmaker_shares';
export { onMatchmakerShareWritten } from './matchmaker_shares';
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

/**
 * Who is asking, said so the owner cannot mistake it: a couple's shared
 * database asks as both of them — "משה ורחל מבקשים גישה לכרטיס שלך" — and
 * approving gives both of them access, never one quietly.
 */
async function requesterLine(row: DocumentSnapshot): Promise<{
  title: string; body: string; who: string; pair: boolean; gender?: Gender;
}> {
  const name = ((row.get('matchmakerName') as string | undefined) ?? '').trim() || 'שדכן/ית';
  const grantees = (row.get('granteeUids') as string[] | undefined) ?? [];
  if (grantees.length === 2) {
    const membership = await db.doc(`memberships/${row.get('matchmakerUid')}`).get();
    const names = (membership.get('names') ?? {}) as Record<string, string>;
    const first = grantees
      .map((uid) => (names[uid] ?? '').trim().split(/\s+/)[0])
      .filter(Boolean);
    const who = first.length === 2 ? `${first[0]} ו${first[1]}` : name;
    return {
      who, pair: true,
      title: `${who} מבקשים גישה לכרטיס שלך`,
      body: 'בקשה משותפת של שני בני הזוג. אישור ייתן גישה לשניהם, למאגר הזוגי שלהם.',
    };
  }
  const gender = row.get('matchmakerGender') as Gender | undefined;
  return {
    who: name, pair: false, gender,
    title: 'בקשת גישה לכרטיס שלך',
    body: g(`${name} {ביקש|ביקשה} גישה לכרטיס שלך`, gender),
  };
}

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
    // Read only when a request is actually being told about.
    let line: Awaited<ReturnType<typeof requesterLine>> | undefined;
    const asking = async () => (line ??= await requesterLine(after));
    if (after.get('cardRequested') === true && before?.get('cardRequested') !== true) {
      const asker = await asking();
      await notify(after.get('ownerUid'), {kind: 'accessRequest', title: asker.title,
        body: asker.body, route: '/me?section=requests'});
    }
    if (
      after.get('lookingRequested') === true &&
      before?.get('lookingRequested') !== true
    ) {
      const asker = await asking();
      await notify(after.get('ownerUid'), {
        kind: 'accessRequest',
        title: 'בקשת גישה ל״מה אני מחפש/ת״',
        body: asker.pair
          ? `${asker.who} מבקשים גישה למידע הפרטי שלך, בשם שניהם`
          : g(`${asker.who} {ביקש|ביקשה} גישה למידע הפרטי שלך`, asker.gender),
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

    if (now === 'pending' && after.get('requestedBy') === 'matchmaker') {
      const asker = await asking();
      await notify(ownerUid, {
        kind: 'accessRequest',
        title: asker.title,
        body: asker.body,
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
  // A friend the matchmaker already keeps by hand: the notice asks the one
  // question that matters to them — join the card to the record they have.
  const kept = phoneHash
    ? (((await db.collection('databaseHashes').doc(recipient).get()).get(
        'hashes',
      ) as string[] | undefined) ?? []).includes(phoneHash)
    : false;
  await notify(
    matchmakerUid,
    {
      kind: 'cardCreated',
      title: kept
        ? g(
            `${fullName(card)} {הוסיף|הוסיפה} כרטיס אישי. רוצה לסנכרן עם הכרטיס הקיים?`,
            gender,
          )
        : g(`${fullName(card)} {הוסיף|הוסיפה} כרטיס אישי`, gender),
      body: kept ? '' : 'אפשר לבקש גישה לפרטים',
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
/**
 * A card that became live recently ([joinedRecently] — the same window as a
 * matchmaker who joined). Only such a card is announced to the owner's
 * contacts: an owner's first contacts upload, or their number arriving,
 * after this shipped must not tell everybody about a card written months ago.
 * A card with no `joinedAt` predates the field, and is old by definition.
 */
function cardIsNews(card: DocumentSnapshot): boolean {
  const joinedAt = card.get('joinedAt');
  return (
    joinedAt instanceof Timestamp &&
    joinedRecently(joinedAt.toMillis(), Date.now())
  );
}

async function announceCard(ownerUid: string): Promise<void> {
  const card = await db.collection('personalCards').doc(ownerUid).get();
  if (!isActiveCard(card.data()) || !cardIsNews(card)) {
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
  // Only the contacts that are in the directory at all ([matchedHashesOf]),
  // not one read per entry of the address book.
  const matched = await matchedHashesOf(ownerUid, contacts);
  for (const entry of await getAllDocs(matched.map((h) => `phoneDirectory/${h}`))) {
    const uid = entry.get('uid') as string | undefined;
    if (entry.exists && entry.get('matchmaker') === true && uid) {
      recipients.add(uid);
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
    // The first list a database ever publishes is where it stands, not news:
    // friends already kept before the update must not raise a notice each.
    if (!event.data?.before?.exists) {
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
    // "X רווקים מנהלים כרטיס" moves only when a card goes live or stops
    // being live — so only then is it counted again (otherwise hourly). It
    // used to be recounted, reading three whole collections, on every write
    // of any card.
    if (isActiveCard(before?.data()) !== isActiveCard(after?.exists ? after.data() : undefined)) {
      await refreshPersonalCardCount();
    }
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
    // Back to a draft (the last photo removed, the text cut under twenty
    // words): off every "חברים שלי שהוסיפו כרטיס אישי" list until it is a
    // card again. Grants already given are left alone.
    if (isActiveCard(before?.data()) && !isActiveCard(after.data()) &&
        before?.get('deleted') === after.get('deleted')) {
      await refreshContactNeighbours(ownerUid);
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
/**
 * The hashes in [ownerUid]'s address book that have a directory entry — the
 * only ones [findHelpers] has to look at.
 *
 * Working this out reads one document per contact (a median of ~1,100, up to
 * ~8,000), and it used to be done on *every* rebuild — several times a
 * session, for the user and for everybody who has their number. It is now
 * kept in `contactMatches/{uid}` (server-only) and worked out again only when
 * the address book's contents changed (`contactsPrint`, a hash of the list).
 * A number that joins or leaves the directory in between is added or removed
 * by `onPhoneDirectoryWritten`.
 */
async function matchedHashesOf(
  ownerUid: string,
  contacts: DocumentSnapshot,
): Promise<string[]> {
  const hashes: string[] = (contacts.get('hashes') as string[] | undefined) ?? [];
  if (hashes.length === 0) return [];
  // The address book's *contents*, not its write time: the app re-sends an
  // unchanged book once a day, and that must not cost a full rescan.
  const contactsPrint = createHash('sha256').update(hashes.join(',')).digest('hex');
  const ref = db.doc(`contactMatches/${ownerUid}`);
  const cached = await ref.get();
  if (cached.exists && cached.get('contactsPrint') === contactsPrint) {
    const kept = (cached.get('hashes') as string[] | undefined) ?? [];
    // Kept in the address book's order, which is the order the lists use.
    const inBook = new Set(hashes);
    return kept.filter((h) => inBook.has(h));
  }
  const matched: string[] = [];
  for (let i = 0; i < hashes.length; i += 100) {
    const entries = await db.getAll(
      ...hashes.slice(i, i + 100).map((h) => db.doc(`phoneDirectory/${h}`)),
    );
    for (const entry of entries) if (entry.exists) matched.push(entry.id);
  }
  await ref.set({
    hashes: matched,
    contactsPrint,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return matched;
}

async function findHelpers(ownerUid: string): Promise<void> {
  const contacts = await db.doc(`contactHashes/${ownerUid}`).get();
  const matched = await matchedHashesOf(ownerUid, contacts);
  const ownBook = new Set<string>((contacts.get('hashes') as string[] | undefined) ?? []);
  const helpers: Record<string, unknown>[] = [], friends: Record<string, unknown>[] = [];

  // Everything about the directory entries is read in batches, not one
  // awaited read at a time (which is what made a run take most of a minute).
  const entries = matched.length === 0 ? [] : await getAllDocs(matched.map((h) => `phoneDirectory/${h}`));
  const candidates: DocumentSnapshot[] = [];
  for (const entry of entries) {
    const uid = entry.get('uid');
    if (!entry.exists || typeof uid !== 'string' || uid === ownerUid) continue;
    if (entry.get('matchmaker') !== true && entry.get('hasCard') !== true) continue;
    candidates.push(entry);
  }
  const uidOf = (entry: DocumentSnapshot) => entry.get('uid') as string;
  const phones = await getAllDocs(candidates.map((e) => `userPhones/${uidOf(e)}`));
  // The entry must still be the one its account published as its own
  // number, or a number could be claimed for somebody else's list.
  const owned = candidates.filter((e, i) => phones[i].get('phoneHash') === e.id);
  const seen = new Set<string>();
  const genuine = owned.filter((e) => !seen.has(uidOf(e)) && seen.add(uidOf(e)));

  // "Saved in each other's phones" — [mutualContacts], with the owner's half
  // read once instead of once per friend (twice, for a matchmaker).
  const ownerHash = await ownerPhoneHashOf(ownerUid);
  const ownerListed = ownerHash
    ? (await db.doc(`phoneDirectory/${ownerHash}`).get()).get('uid') === ownerUid
    : false;
  const theirBooks = ownerListed
    ? await getAllDocs(genuine.map((e) => `contactHashes/${uidOf(e)}`))
    : [];
  const mutualOf = (i: number) =>
    ownerListed && ownBook.has(genuine[i].id) &&
    (((theirBooks[i].get('hashes') as string[] | undefined) ?? []).includes(ownerHash as string));

  const [members, activities] = await Promise.all([
    getAllDocs(genuine.map((e) => `communityMembers/${uidOf(e)}`)),
    getAllDocs(genuine.map((e) => `matchmakerActivity/${uidOf(e)}`)),
  ]);
  const matchmakerIdx = genuine.map((e, i) => (e.get('matchmaker') === true ? i : -1)).filter((i) => i >= 0);
  const memberships = new Map<number, DocumentSnapshot>();
  const membershipDocs = await getAllDocs(matchmakerIdx.map((i) => `memberships/${uidOf(genuine[i])}`));
  matchmakerIdx.forEach((i, k) => memberships.set(i, membershipDocs[k]));
  const singleIdx = genuine
    .map((e, i) => (e.get('hasCard') === true && e.get('announces') !== false && mutualOf(i) ? i : -1))
    .filter((i) => i >= 0);
  const cards = new Map<number, DocumentSnapshot>();
  const cardDocs = await getAllDocs(singleIdx.map((i) => `personalCards/${uidOf(genuine[i])}`));
  singleIdx.forEach((i, k) => cards.set(i, cardDocs[k]));

  genuine.forEach((entry, i) => {
    const uid = uidOf(entry);
    const matchmaker = entry.get('matchmaker') === true;
    const single = entry.get('hasCard') === true && entry.get('announces') !== false;
    const mutual = single ? mutualOf(i) : false;
    if (!matchmaker && !mutual) return;
    const member = members[i];
    const activity = activities[i];
    const row = {uid, name: entry.get('name') ?? '', phoneHash: entry.id,
      photoUrl: member.get('hidden') === false && typeof member.get('photoUrl') === 'string' && member.get('photoUrl').trim() ? member.get('photoUrl') : null,
      databaseCount: activity.get('databaseCount') ?? null,
      lastActiveAt: activity.get('lastActiveAt') ?? null,
      // When they joined as a matchmaker, so the newest friends lead.
      joinedAt: member.get('joinedAt') ?? null};
    if (matchmaker) {
      const membership = memberships.get(i) as DocumentSnapshot;
      helpers.push({...row, name: membership.get('state') === 'active' ? membership.get('name') : row.name,
        recipientUid: membership.get('state') === 'active' ? membership.get('databaseUid') : uid,
        granteeUids: membership.get('state') === 'active' ? membership.get('members') : [uid],
        // Saved in each other's phones — "שדכנים שאני מכיר" puts them first.
        // A flag only: neither side learns anything about the other's
        // address book beyond the one number they already have.
        mutual: mutualOf(i),
        // Whether they still make the community figures public — their
        // couples are shown on the basic profile only then.
        publicFigures: member.exists && member.get('hidden') === false});
    }
    if (mutual && isActiveCard(cards.get(i)?.data())) {
      // Presence only. No candidate details or personal-card photograph.
      friends.push({uid, name: row.name, phoneHash: entry.id});
    }
  });
  const ref = db.doc(`users/${ownerUid}/private/helpers`);
  // `uids` — every account on either list, flat, so the chat rule can ask
  // "do these two know each other?" in one document read instead of the
  // five a phone-book check costs (Firestore stops a rule at ten).
  const uids = [...new Set([
    ...helpers.map((h) => h.uid as string),
    ...friends.map((f) => f.uid as string),
  ])].filter((u) => typeof u === 'string' && u.length > 0).slice(0, 2000);
  // Written only when the list actually moved: every write is a read on each
  // of the owner's phones (they listen to it) and wakes a trigger.
  const stored = await ref.get();
  if (helperListChanged(stored.data(), {helpers, friends, uids})) {
    await ref.set({helpers, friends, uids, updatedAt: FieldValue.serverTimestamp()});
  }
  const now = Date.now();
  const recent = helpers.filter((h) =>
    joinedRecently(h.joinedAt instanceof Timestamp ? h.joinedAt.toMillis() : null, now));
  // Nobody on the list joined in the last week — nothing to announce, and
  // nothing more to read.
  if (recent.length === 0) return;
  await announceJoinedMatchmakers(ownerUid, recent);
  const card = await db.doc(`personalCards/${ownerUid}`).get();
  if (isActiveCard(card.data())) {
    for (const helper of recent) {
      const uid = helper.uid as string;
      // Only a friend who has just joined: everybody who was already here
      // when this shipped is not news, and is on "השדכנים שלי" anyway.
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

/** Every document at [paths], in order, read 100 at a time. */
async function getAllDocs(paths: string[]): Promise<DocumentSnapshot[]> {
  const out: DocumentSnapshot[] = [];
  for (let i = 0; i < paths.length; i += 100) {
    const chunk = paths.slice(i, i + 100);
    if (chunk.length === 0) break;
    out.push(...(await db.getAll(...chunk.map((p) => db.doc(p)))));
  }
  return out;
}

/**
 * "[שם] הצטרף/ה לשדכן. רוצה להתחבר?" — to a matchmaker, about a contact of
 * theirs who has just joined as a matchmaker too.
 *
 * Only about somebody who **joined** recently ([joinedRecently]): a colleague
 * of years whom the owner only now saved in their phone did not join
 * anything, and the first run after this shipped must not announce everybody
 * already there. Once per pair, ever (the inbox row's id), and never when the
 * two are already connected or one has already asked.
 */
async function announceJoinedMatchmakers(
  ownerUid: string,
  helpers: Record<string, unknown>[],
): Promise<void> {
  if (helpers.length === 0) return;
  const ownerIsMatchmaker = (await db.doc(`matchmakerActivity/${ownerUid}`).get()).exists ||
    await (async () => {
      const hash = await ownerPhoneHashOf(ownerUid);
      if (!hash) return false;
      const entry = await db.doc(`phoneDirectory/${hash}`).get();
      return entry.get('uid') === ownerUid && entry.get('matchmaker') === true;
    })();
  if (!ownerIsMatchmaker) return;
  const now = Date.now();
  const ownerJoined = (await db.doc(`communityMembers/${ownerUid}`).get()).get('joinedAt');
  let pushed = 0;
  for (const helper of helpers) {
    const uid = helper.uid as string;
    const joinedAt = helper.joinedAt instanceof Timestamp ? helper.joinedAt.toMillis() : null;
    if (!joinedRecently(joinedAt, now)) continue;
    // Somebody who joined *before* the owner is not news to them.
    if (ownerJoined instanceof Timestamp && joinedAt !== null && ownerJoined.toMillis() > joinedAt) continue;
    if ((await db.doc(`matchmakerShares/${ownerUid}_${uid}`).get()).exists ||
        (await db.doc(`matchmakerShares/${uid}_${ownerUid}`).get()).exists) continue;
    const name = ((helper.name as string | undefined) ?? '').trim() || 'חבר/ה מאנשי הקשר';
    await notify(ownerUid, {kind: 'matchmakerJoined', title: `${name} הצטרף/ה לשדכן`,
      body: 'אפשר לשתף אחד עם השני כרטיסים — אתם מחליטים מה',
      route: `/known-matchmakers/${uid}`}, pushed < 3, `matchmakerJoined_${uid}`);
    pushed++;
  }
}

async function refreshContactNeighbours(uid: string): Promise<void> {
  await findHelpers(uid);
  for (const owner of await ownersWhoSaved(uid)) await findHelpers(owner);
}

/**
 * Everybody who has [uid]'s number in their address book. Ids only:
 * `select()` leaves the (large) hash lists behind — one read each all the
 * same, but none of the bandwidth or the time.
 */
async function ownersWhoSaved(uid: string): Promise<string[]> {
  const hash = await ownerPhoneHashOf(uid);
  if (!hash) return [];
  const owners = await db
    .collection('contactHashes')
    .where('hashes', 'array-contains', hash)
    .select()
    .get();
  return owners.docs.map((d) => d.id).filter((id) => id !== uid);
}

/**
 * Only what other people's lists show from this row — the name's photo,
 * whether the figures are public, and when they joined (which drives the
 * "X הצטרף/ה" notices). The counters change on every publish and nobody's
 * list reads them: that alone used to rebuild everybody's list, and re-read
 * three whole collections, several times per session.
 */
export const onPersonalMemberActivity = onDocumentWritten('communityMembers/{uid}', async event => {
  if (!memberListFieldsChanged(event.data?.before?.data(), event.data?.after?.data())) return;
  await refreshContactNeighbours(event.params.uid);
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
    // Republished with nothing a list shows changed (only `updatedAt`).
    const shown = (d: DocumentSnapshot | undefined) =>
      d?.exists
        ? JSON.stringify(['uid', 'name', 'matchmaker', 'hasCard', 'acceptsRequests', 'announces']
          .map((f) => d.get(f) ?? null))
        : null;
    if (shown(before) === shown(after)) return;
    const owners = await db
      .collection('contactHashes')
      .where('hashes', 'array-contains', event.params.phoneHash)
      .select()
      .get();
    for (const doc of owners.docs) {
      // The number joined or left the directory: the owner's cached list of
      // contacts worth looking at ([matchedHashesOf]) follows it.
      if (!before?.exists || !after?.exists) {
        await db.doc(`contactMatches/${doc.id}`).set(
          {
            hashes: after?.exists
              ? FieldValue.arrayUnion(event.params.phoneHash)
              : FieldValue.arrayRemove(event.params.phoneHash),
          },
          { merge: true },
        );
      }
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
    const ownerUid = event.params.ownerUid;
    // The daily re-send of an unchanged address book: nobody else's list
    // depends on it having been sent again, and its card was announced the
    // first time. Only the owner's own list is refreshed (cheap — its
    // contacts in the directory are cached).
    if (
      event.data?.before?.exists &&
      event.data?.after?.exists &&
      stableJson(event.data.before.get('hashes')) === stableJson(event.data.after.get('hashes'))
    ) {
      await findHelpers(ownerUid);
      return;
    }
    await refreshContactNeighbours(ownerUid);
    await announceCard(ownerUid);
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
    await applyTagDeltas(before, after, 'users');
  },
);

/**
 * The tags a single chose on their own personal card, counted into the same
 * `communityTags/{key}` documents under `cards` — so the console can show how
 * each word of the shared list is used, by matchmakers and by singles. A
 * deleted card counts as no tags. Never who chose them.
 */
export const onPersonalCardTagsWritten = onDocumentWritten(
  'personalCards/{uid}',
  async (event) => {
    const cardTags = (snapshot: DocumentSnapshot | undefined) =>
      snapshot?.exists && snapshot.get('deleted') !== true
        ? tagsOf(snapshot)
        : new Map<string, string>();
    const before = cardTags(event.data?.before);
    const after = cardTags(event.data?.after);
    await applyTagDeltas(before, after, 'cards');
  },
);

/** One more (or one fewer) user of every word that came (or went). */
async function applyTagDeltas(
  before: Map<string, string>,
  after: Map<string, string>,
  field: 'users' | 'cards',
): Promise<void> {
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
      const counts = {
        users: (current.exists ? current.get('users') : 0) ?? 0,
        cards: (current.exists ? current.get('cards') : 0) ?? 0,
      };
      counts[field] = Math.max(0, counts[field] + delta);
      if (counts.users <= 0 && counts.cards <= 0) {
        tx.delete(ref);
      } else {
        tx.set(
          ref,
          {
            label: current.exists ? (current.get('label') ?? label) : label,
            users: counts.users,
            cards: counts.cards,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    });
  }
}

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
    // What the server worked out from that address book (`matchedHashesOf`).
    await db.collection('contactMatches').doc(uid).delete();
    await db.collection('databaseHashes').doc(uid).delete();
    await db.collection('fcmTokens').doc(uid).delete();
    await db.doc(`matchmakerActivity/${uid}`).delete();
    // Every share with another matchmaker, either direction, and the cards
    // this account published or could read.
    await deleteSharesOf(uid);
    // The cards shared with them, ideas offered between them, chats.
    await deleteNetworkOf(uid);
    // A couple space: the database published to the partner, and the tie.
    await deletePartnerCardsOf(uid);
    for (const p of (await db.collection('partnerships').where('uids', 'array-contains', uid).get()).docs)
      await p.ref.delete();
    // Deleting it counts this matchmaker out of every tag word they used.
    await db.collection('tagUsage').doc(uid).delete();
    // The support view of this account's sync (counts and error codes).
    await db.collection('accountHealth').doc(uid).delete();
    // The monitoring metadata about this account (counts and codes only).
    await deleteAnalyticsOf(uid);
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
  await deleteAnalyticsOf(uid);
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
  // A card is live by its text and photos, which no query can test: the
  // cards themselves are read (171 today), once an hour.
  const cards = await db
    .collection('personalCards')
    .select('description', 'photoPaths', 'deleted', 'joinedAt')
    .get();
  const count = cards.docs.filter((d) => isActiveCard(d.data())).length;
  const real = new Date();
  const now = new Date(real.toLocaleString('en-US', {timeZone: 'Asia/Jerusalem'}));
  // Israel's offset now, so a wall-clock moment can be turned into the
  // instant a query compares against.
  const offset = Math.round((now.getTime() - real.getTime()) / 60000) * 60000;
  const sunday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
  const two = (n: number) => String(n).padStart(2, '0');
  const weekKey = `W${sunday.getFullYear()}-${two(sunday.getMonth()+1)}-${two(sunday.getDate())}`;
  const joinedThisWeek = (value: unknown) => value instanceof Timestamp &&
    new Date(value.toDate().toLocaleString('en-US', {timeZone: 'Asia/Jerusalem'})) >= sunday;
  // The calendar month in Israel — "X הצטרפו החודש" on the personal home.
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthKey = `M${monthStart.getFullYear()}-${two(monthStart.getMonth()+1)}`;
  const joinedThisMonth = (value: unknown) => value instanceof Timestamp &&
    new Date(value.toDate().toLocaleString('en-US', {timeZone: 'Asia/Jerusalem'})) >= monthStart;
  const hebrewKey = hebrewMonthKey(now);
  const community = await communityFigures({
    weekKey,
    hebrewKey,
    weekStart: Timestamp.fromMillis(sunday.getTime() - offset),
    joinedThisWeek,
  });
  const totals = {singles: count, weekKey, monthKey,
    newSinglesWeek: cards.docs.filter(d => isActiveCard(d.data()) && joinedThisWeek(d.get('joinedAt'))).length,
    newSinglesMonth: cards.docs.filter(d => isActiveCard(d.data()) && joinedThisMonth(d.get('joinedAt'))).length,
    ...community,
    hebrewMonthKey: hebrewKey};
  const ref = db.doc('publicStats/personalCards');
  const area = db.doc('publicStats/personalArea');
  await db.runTransaction(async (tx) => {
    const [previous, previousArea] = await Promise.all([tx.get(ref), tx.get(area)]);
    if ((previous.get('startedAt') ?? 0) > startedAt) return;
    // The same figures as last hour: nothing is written — each write is a
    // read on every phone that shows the personal home.
    if (previous.get('count') === count && sameFigures(previousArea.data(), totals)) return;
    tx.set(ref, { count, startedAt, updatedAt: FieldValue.serverTimestamp() });
    tx.set(area, {...totals, startedAt, updatedAt: FieldValue.serverTimestamp()});
  });
}

/**
 * The community's figures for the personal home, by aggregate queries — a
 * handful of reads whatever the size of the community, where the old code
 * read every member and every activity row. The sums run on the same
 * composite indexes the app's own community figures use. Should a query be
 * refused (an index missing), the old full read answers instead.
 */
async function communityFigures(args: {
  weekKey: string;
  hebrewKey: string;
  weekStart: Timestamp;
  joinedThisWeek: (value: unknown) => boolean;
}): Promise<{
  newMatchmakersWeek: number;
  activeMatchmakers: number;
  couplesWeek: number;
  engagementsWeek: number;
  matchmakers: number;
  engagementsMonth: number;
}> {
  const members = db.collection('communityMembers');
  const num = (v: unknown) => (typeof v === 'number' ? v : 0);
  try {
    const [all, joined, active, week, month] = await Promise.all([
      members.count().get(),
      members.where('joinedAt', '>=', args.weekStart).count().get(),
      db.collection('matchmakerActivity').where('lastActiveAt', '>=', args.weekStart).count().get(),
      members
        .where('weekKey', '==', args.weekKey)
        .where('weekActions', '>', 0)
        .aggregate({
          couples: AggregateField.sum('weekCouples'),
          engagements: AggregateField.sum('weekEngagements'),
        })
        .get(),
      members
        .where('monthKey', '==', args.hebrewKey)
        .where('monthActions', '>', 0)
        .aggregate({ engagements: AggregateField.sum('monthEngagements') })
        .get(),
    ]);
    return {
      newMatchmakersWeek: joined.data().count,
      activeMatchmakers: active.data().count,
      couplesWeek: num(week.data().couples),
      engagementsWeek: num(week.data().engagements),
      // "186 שדכנים בקהילה" and "3 חתונות נוספו החודש" on the personal home.
      // The month is the Hebrew one, as the members' own counters are keyed.
      matchmakers: all.data().count,
      engagementsMonth: num(month.data().engagements),
    };
  } catch (error) {
    logger.warn('communityFigures: aggregates failed, reading everything', { error: String(error) });
  }
  const docs = (await members.get()).docs;
  const current = docs.filter((d) => d.get('weekKey') === args.weekKey);
  const sum = (field: string) => current.reduce((n, d) => n + num(d.get(field)), 0);
  const activity = await db.collection('matchmakerActivity').get();
  return {
    newMatchmakersWeek: docs.filter((d) => args.joinedThisWeek(d.get('joinedAt'))).length,
    activeMatchmakers: activity.docs.filter((d) => args.joinedThisWeek(d.get('lastActiveAt'))).length,
    couplesWeek: sum('weekCouples'),
    engagementsWeek: sum('weekEngagements'),
    matchmakers: docs.length,
    engagementsMonth: docs
      .filter((d) => d.get('monthKey') === args.hebrewKey)
      .reduce((n, d) => n + num(d.get('monthEngagements')), 0),
  };
}
// `updatePersonalCardCount` (a recount on every write of any card) is gone:
// the hourly run below is the only one. Each recount used to read three whole
// collections. Remove it from the project when deploying (the CLI asks).
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

/**
 * "Last active" and the database size of a matchmaker, as other people's
 * lists show them.
 *
 * **Not a rebuild.** This used to work out, from scratch, the list of the
 * matchmaker *and* of everybody who has their number — one read per contact
 * — and re-read three whole collections, on every write; the app writes here
 * on every open, resume, exit and burst of edits. That was ~90% of the
 * project's reads. Now the matchmaker's own row on each of those lists is
 * updated in place, and only when the size changed or an hour has passed
 * ([activityChange]). The first write ever still builds the lists once.
 */
export const onMatchmakerActivityWritten = onDocumentWritten('matchmakerActivity/{uid}', async event => {
  const uid = event.params.uid;
  const after = event.data?.after;
  switch (activityChange(event.data?.before?.data(), after?.data())) {
    case 'rebuild':
      await refreshContactNeighbours(uid);
      return;
    case 'patch':
      await patchHelperActivity(uid, {
        databaseCount: after?.get('databaseCount') ?? null,
        lastActiveAt: after?.get('lastActiveAt') ?? null,
      });
      return;
    case 'none':
      return;
  }
});

/** [uid]'s row, wherever it is listed, given its new figures. */
async function patchHelperActivity(
  uid: string,
  figures: { databaseCount: unknown; lastActiveAt: unknown },
): Promise<void> {
  for (const owner of await ownersWhoSaved(uid)) {
    const ref = db.doc(`users/${owner}/private/helpers`);
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      const next = patchHelperRows(doc.get('helpers'), uid, figures);
      if (next) tx.update(ref, { helpers: next });
    });
  }
}

/**
 * The administrators' dashboard ("נתונים" in the support console): counts
 * only, twice a day and on demand ("רענון עכשיו"). See `admin_stats.ts`.
 * Each run reads five whole collections, so it was moved from every three
 * hours to every twelve (2026-11-22).
 */
export const refreshAdminStats = onSchedule(
  { schedule: 'every 12 hours', timeoutSeconds: 300, memory: '512MiB' },
  async () => {
    await writeAdminStats(db);
  },
);

/** "רענון עכשיו" in the dashboard — support administrators only. */
export const refreshAdminStatsNow = onCall(
  { timeoutSeconds: 300, memory: '512MiB' },
  async (request) => {
    const token = request.auth?.token as { email?: string; email_verified?: boolean } | undefined;
    if (!token?.email || token.email_verified === false || !(await isSupportAdminEmail(db, token.email))) {
      throw new HttpsError('permission-denied', 'Administrators only.');
    }
    const stats = await writeAdminStats(db);
    return { computedAt: stats.computedAt };
  },
);

/** Reminders pushed once per account rather than by every phone. */
export const sendReminders = onSchedule(
  { schedule: 'every 60 minutes', timeoutSeconds: 300, memory: '512MiB' },
  async () => {
    await sendDueReminders(db);
  },
);

// ---------------------------------------------------------------------------
// Monitoring (2026-11-26): usage, costs, errors, performance. See
// `analytics.ts` for the taxonomy and `analytics_store.ts` for the storage.

/** One batch of usage events from a phone, folded and deleted. */
export const onTelemetryBatch = onDocumentCreated(
  { document: 'telemetryBatches/{batchId}', memory: '256MiB', retry: false },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    try {
      await processBatch(db, event.params.batchId, data);
    } catch (error) {
      logger.error('onTelemetryBatch failed', { batchId: event.params.batchId, error: String(error) });
    }
  },
);

async function requireAdmin(request: { auth?: { token?: unknown } }): Promise<void> {
  const token = request.auth?.token as { email?: string; email_verified?: boolean } | undefined;
  if (!token?.email || token.email_verified === false || !(await isSupportAdminEmail(db, token.email))) {
    throw new HttpsError('permission-denied', 'Administrators only.');
  }
}

/** The monitoring dashboard for one period and segment — administrators only. */
export const adminAnalytics = onCall({ timeoutSeconds: 300, memory: '1GiB' }, async (request) => {
  await requireAdmin(request);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const seg = (d.segment ?? {}) as Record<string, unknown>;
  try {
    return await dashboard(db, {
      from: String(d.from ?? ''),
      to: String(d.to ?? ''),
      force: d.force === true,
      release: typeof d.release === 'string' && d.release ? d.release : undefined,
      segment: {
        platform: typeof seg.platform === 'string' && seg.platform ? seg.platform : undefined,
        version: typeof seg.version === 'string' && seg.version ? seg.version : undefined,
        userType: typeof seg.userType === 'string' && seg.userType ? seg.userType : undefined,
        cohort: seg.cohort === 'new' || seg.cohort === 'veteran' ? seg.cohort : undefined,
      },
    });
  } catch (error) {
    if (String(error).includes('bad-range')) throw new HttpsError('invalid-argument', 'Bad date range.');
    throw error;
  }
});

/** One account's drill-down — administrators only. */
export const adminUserAnalytics = onCall({ timeoutSeconds: 120, memory: '512MiB' }, async (request) => {
  await requireAdmin(request);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const uid = String(d.uid ?? '');
  if (!uid) throw new HttpsError('invalid-argument', 'uid required.');
  try {
    return await userDetail(db, uid, String(d.from ?? ''), String(d.to ?? ''));
  } catch (error) {
    if (String(error).includes('bad-range')) throw new HttpsError('invalid-argument', 'Bad date range.');
    throw error;
  }
});

/** The administrator's thresholds, checked hourly. */
export const checkAnalyticsThresholds = onSchedule(
  { schedule: 'every 60 minutes', timeoutSeconds: 300, memory: '512MiB' },
  async () => {
    await checkThresholds(db);
  },
);
