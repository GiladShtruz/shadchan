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
import { initializeApp } from 'firebase-admin/app';
import {
  getFirestore,
  FieldValue,
  DocumentSnapshot,
} from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
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

type Gender = 'male' | 'female' | 'unknown';

interface Notice {
  kind: string;
  title: string;
  body: string;
  route: string;
  ownerUid?: string;
  /** Lets the matchmaker's app find the friend in its own database. */
  ownerPhoneHash?: string;
}

/** `{male|female}` → the right form for [gender]; masculine when unknown. */
function g(template: string, gender: Gender | undefined): string {
  return template.replace(/\{([^|{}]*)\|([^|{}]*)\}/g, (_m, male, female) =>
    gender === 'female' ? female : male,
  );
}

const STATUS_LABELS: Record<string, string> = {
  available: 'פנוי',
  busy: 'תפוס',
  onBreak: 'בהפסקה',
  mazelTov: 'מזל טוב',
};

/** Writes the inbox row and pushes to every device of [uid]. */
async function notify(
  uid: string,
  notice: Notice,
  push = true,
): Promise<void> {
  await db
    .collection('users')
    .doc(uid)
    .collection('inbox')
    .add({
      ...notice,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });

  if (!push) {
    return;
  }
  const tokensDoc = await db.collection('fcmTokens').doc(uid).get();
  const tokens: string[] = (tokensDoc.get('tokens') as string[] | undefined) ?? [];
  if (tokens.length === 0) {
    return;
  }
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: notice.title, body: notice.body },
    data: {
      kind: notice.kind,
      route: notice.route,
      ownerUid: notice.ownerUid ?? '',
      ownerPhoneHash: notice.ownerPhoneHash ?? '',
    },
    android: { notification: { channelId: 'personal_card' } },
    apns: { payload: { aps: { sound: 'default' } } },
  });
  // Tokens the service says are gone are taken off the list, so a phone that
  // was reset stops costing a failed send on every notice.
  const dead: string[] = [];
  response.responses.forEach((r, i) => {
    const code = r.error?.code ?? '';
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      dead.push(tokens[i]);
    }
  });
  if (dead.length > 0) {
    await tokensDoc.ref.update({ tokens: FieldValue.arrayRemove(...dead) });
  }
}

/** Every matchmaker the owner has approved. */
async function approvedMatchmakers(ownerUid: string): Promise<string[]> {
  const snap = await db
    .collection('cardAccess')
    .where('ownerUid', '==', ownerUid)
    .where('status', '==', 'approved')
    .get();
  return snap.docs.map((d) => d.get('matchmakerUid') as string);
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
    if (was === now) {
      return;
    }
    const ownerUid = after.get('ownerUid') as string;
    const matchmakerUid = after.get('matchmakerUid') as string;
    const ownerName = (after.get('ownerName') as string | undefined) ?? '';
    const matchmakerName =
      (after.get('matchmakerName') as string | undefined) ?? '';

    if (now === 'pending' && after.get('requestedBy') === 'matchmaker') {
      await notify(ownerUid, {
        kind: 'accessRequest',
        title: 'בקשת גישה לכרטיס שלך',
        body: `${matchmakerName} רוצה לקבל גישה לכרטיס שלך`,
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
      await notify(matchmakerUid, {
        kind: 'accessApproved',
        title: g(
          `${ownerFirst} {אישר|אישרה} גישה לכרטיס {שלו|שלה}`,
          ownerGender,
        ),
        body: `הכרטיס של ${ownerFirst} מתעדכן אצלך מעכשיו`,
        // Opens that friend's profile in the matchmaker's database.
        route: `/card-friend/${ownerUid}`,
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
  if (matchmakerUid === ownerUid) {
    return false;
  }
  const marker = card.ref.collection('announced').doc(matchmakerUid);
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
  if (!card.exists || card.get('deleted') === true) {
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
  const hashes: string[] = (contacts.get('hashes') as string[] | undefined) ?? [];
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
        if (!card.exists || card.get('deleted') === true) {
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
      return;
    }
    if (!before?.exists) {
      await announceCard(ownerUid);
      return;
    }
    const wasStatus = before.get('status') as string;
    const status = after.get('status') as string;
    if (
      status === 'mazelTov' &&
      wasStatus !== 'mazelTov' &&
      after.get('deleted') !== true
    ) {
      const name = firstName(after);
      const gender = after.get('gender') as Gender | undefined;
      for (const matchmakerUid of await approvedMatchmakers(ownerUid)) {
        await notify(matchmakerUid, {
          kind: 'mazelTov',
          title: g(`${name} {התחתן|התחתנה} 🎉`, gender),
          body: 'אפשר לשלוח מזל טוב בוואטסאפ',
          route: '/reminders',
          ownerUid,
        });
      }
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
async function findHelpers(ownerUid: string): Promise<void> {
  const contacts = await db.collection('contactHashes').doc(ownerUid).get();
  const hashes: string[] = (contacts.get('hashes') as string[] | undefined) ?? [];
  const helpers: { uid: string; name: string; phoneHash: string }[] = [];
  const seen = new Set<string>();
  const refs = hashes.map((h) => db.collection('phoneDirectory').doc(h));
  for (let i = 0; i < refs.length; i += 100) {
    const entries = await db.getAll(...refs.slice(i, i + 100));
    for (const entry of entries) {
      const uid = entry.get('uid') as string | undefined;
      if (
        !entry.exists ||
        entry.get('matchmaker') !== true ||
        !uid ||
        uid === ownerUid ||
        seen.has(uid)
      ) {
        continue;
      }
      seen.add(uid);
      // The hash lets the owner's phone show the name *they* saved this
      // friend under; the directory name is only the fallback.
      helpers.push({
        uid,
        name: (entry.get('name') as string) ?? '',
        phoneHash: entry.id,
      });
    }
  }
  helpers.sort((a, b) => a.name.localeCompare(b.name, 'he'));
  await db
    .collection('users')
    .doc(ownerUid)
    .collection('private')
    .doc('helpers')
    .set({ helpers, updatedAt: FieldValue.serverTimestamp() });
}

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
    const sameName = before?.get('name') === after?.get('name');
    if (wasUid === nowUid && (!nowUid || sameName)) {
      return;
    }
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
    if (event.data?.after?.exists) {
      await findHelpers(event.params.ownerUid);
      await announceCard(event.params.ownerUid);
    }
  },
);

// ---------------------------------------------------------------------------
// "השראה מהקהילה" — how many matchmakers use each tag word
// ---------------------------------------------------------------------------

/** Words that name a circle — an institution, a unit, a workplace. */
const CIRCLE_WORDS = [
  'ישיבה', 'ישיבת', 'מדרשה', 'מדרשת', 'אולפנה', 'אולפנת', 'מכינה', 'מכינת',
  'סמינר', 'כולל', 'קהילה', 'קהילת', 'בית כנסת', 'גרעין', 'יחידה', 'יחידת',
  'גדוד', 'חטיבה', 'חטיבת', 'סיירת', 'שייטת', 'מקום עבודה', 'מהעבודה',
  'משרד', 'אוניברסיטה', 'אוניברסיטת', 'מכללה', 'מכללת', 'תיכון', 'בית ספר',
  'אולפן', 'סניף', 'שבט', 'מחזור', 'שכונה', 'שכונת', 'בני עקיבא', 'עזרא',
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
        const users = ((current.exists ? current.get('users') : 0) ?? 0) + delta;
        if (users <= 0) {
          tx.delete(ref);
        } else {
          tx.set(
            ref,
            {
              label: current.exists ? current.get('label') ?? label : label,
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
  async (event) => {
    const report = event.data;
    if (!report) {
      return;
    }
    const label = STATUS_LABELS[report.get('status') as string] ?? '';
    await notify(report.get('ownerUid') as string, {
      kind: 'statusReport',
      title: 'עדכון סטטוס לאישור',
      body: `${report.get('matchmakerName') ?? ''} עדכן אצלו שהסטטוס שלך הוא ‘${label}’. זה נכון?`,
      route: '/me',
    });
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
    await deleteQuery('cardAccess', 'ownerUid', uid);
    await deleteQuery('cardAccess', 'matchmakerUid', uid);
    await deleteQuery('statusReports', 'ownerUid', uid);
    await deleteQuery('statusReports', 'matchmakerUid', uid);
    await deleteQuery('phoneDirectory', 'uid', uid);
    await db.collection('userPhones').doc(uid).delete();
    await db.collection('contactHashes').doc(uid).delete();
    await db.collection('databaseHashes').doc(uid).delete();
    await db.collection('fcmTokens').doc(uid).delete();
    // Deleting it counts this matchmaker out of every tag word they used.
    await db.collection('tagUsage').doc(uid).delete();
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
