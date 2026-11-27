/**
 * Sharing cards between matchmakers — the server side.
 *
 * **A trust network, never a public database.** A matchmaker shares cards
 * from their own database with each matchmaker they know separately
 * (`matchmakerShares/{owner}_{reader}`); a shared card is one published view
 * (`networkCards/{owner}_{person}`) that names its `readers`. The rules decide
 * who reads what; this file does only what no phone can do on its own behalf:
 *
 *  - serve a shared card's photos to a matchmaker it is shared with
 *    (`sharedCardPhoto`) — through a callable, never a download URL, so
 *    taking a reader off the card ends the photos;
 *  - tell the other side about an idea offered to them, and its answer —
 *    in the inbox and as small system lines in the pair's chat, never as a
 *    push (only a request to connect is pushed);
 *  - push a chat message to the other side's phones (never a system line);
 *  - take a single's card out of every shared pool the moment the single
 *    withdraws their consent (`shareOnward`) or the grant itself;
 *  - erase all of it with the account.
 */
import { getFirestore, DocumentSnapshot, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { getMessaging } from 'firebase-admin/messaging';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentWritten, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { notify, mutes } from './notices';
import { connectionId } from './matchmaker_shares';

/** The largest photo returned inline. */
export const MAX_SHARED_PHOTO_BYTES = 8 * 1024 * 1024;

/**
 * `sharedCards/{ownerUid}/{personId}/{file}` — or, for a couple space,
 * `partnerCards/{ownerUid}/{personId}/{file}` — and nothing else.
 */
export function validSharedPhotoPath(ownerUid: string, path: unknown): path is string {
  if (typeof path !== 'string' || !ownerUid || ownerUid.includes('/')) return false;
  const parts = path.split('/');
  return (
    parts.length === 4 &&
    (parts[0] === 'sharedCards' || parts[0] === 'partnerCards') &&
    parts[1] === ownerUid &&
    parts.slice(2).every((p) => p.length > 0 && p !== '.' && p !== '..')
  );
}

export interface SharedPhotoAccess {
  uid: string;
  ownerUid: string;
  path: string;
  /**
   * `networkCards/{owner}_{person}` of the photo's card, if any — the card
   * names who may read it.
   */
  card: Record<string, unknown> | undefined;
  /**
   * Whether an idea proposal between the two names this photo's card — the
   * candidate offered or the card it was offered for. Keeps an approved
   * idea's photos reachable after the two disconnect.
   */
  inProposal: boolean;
  /** `partnerships/{a}_{b}` of the two, if any — a couple space. */
  partnership?: Record<string, unknown> | undefined;
  /**
   * `sentCards/{owner}/to/{uid}/cards/{person}` — the card the owner sent
   * this one in a conversation (a matchmaker to a matchmaker, or a candidate
   * to a single). Its own photos, and only those.
   */
  sent?: Record<string, unknown> | undefined;
}

/** Whether [a.uid] may receive [a.path]. */
export function mayReadSharedPhoto(a: SharedPhotoAccess): boolean {
  if (!validSharedPhotoPath(a.ownerUid, a.path)) return false;
  if (a.uid === a.ownerUid) return true;
  const partnerPhoto = a.path.startsWith('partnerCards/');
  // A partner's whole database is open to the other partner while the couple
  // space is active — and only to them.
  if (partnerPhoto) {
    if (a.partnership?.status === 'active') {
      const uids = Array.isArray(a.partnership.uids) ? a.partnership.uids : [];
      if (uids.includes(a.uid) && uids.includes(a.ownerUid)) return true;
    }
    return a.inProposal;
  }
  if (a.card && a.card.ownerUid === a.ownerUid) {
    const readers = Array.isArray(a.card.readers) ? a.card.readers : [];
    if (readers.includes(a.uid)) return true;
  }
  if (a.sent) {
    const paths = Array.isArray(a.sent.photoPaths) ? a.sent.photoPaths : [];
    if (paths.includes(a.path)) return true;
  }
  return a.inProposal;
}

/** Whether a proposal between [ownerUid] and [uid] carries [personId]. */
async function proposalNames(ownerUid: string, uid: string, personId: string): Promise<boolean> {
  const db = getFirestore();
  const [out, inn] = await Promise.all([
    db.collection('ideaProposals').where('fromUid', '==', ownerUid).where('toUid', '==', uid).get(),
    db.collection('ideaProposals').where('fromUid', '==', uid).where('toUid', '==', ownerUid).get(),
  ]);
  // The owner offered this candidate, or the caller offered something for
  // the owner's card.
  return (
    out.docs.some((d) => d.get('candidate.personId') === personId && d.get('status') !== 'withdrawn') ||
    inn.docs.some((d) => d.get('target.personId') === personId && d.get('status') !== 'withdrawn')
  );
}

export const sharedCardPhoto = onCall(
  { region: 'europe-west1', timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid || request.auth?.token.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError('unauthenticated', 'נדרשת התחברות');
    }
    const ownerUid = request.data?.ownerUid;
    const path = request.data?.path;
    if (typeof ownerUid !== 'string' || !validSharedPhotoPath(ownerUid, path)) {
      throw new HttpsError('invalid-argument', 'נתיב לא תקין');
    }
    const db = getFirestore();
    const personId = path.split('/')[2];
    const [card, partnership] = await Promise.all([
      db.doc(`networkCards/${ownerUid}_${personId}`).get(),
      db.doc(`partnerships/${connectionId(uid, ownerUid)}`).get(),
    ]);
    let allowed = mayReadSharedPhoto({
      uid,
      ownerUid,
      path,
      card: card.exists ? card.data() : undefined,
      partnership: partnership.exists ? partnership.data() : undefined,
      inProposal: false,
    });
    if (!allowed && uid !== ownerUid) {
      const sent = await db.doc(`sentCards/${ownerUid}/to/${uid}/cards/${personId}`).get();
      if (sent.exists) {
        allowed = mayReadSharedPhoto({
          uid,
          ownerUid,
          path,
          card: undefined,
          sent: sent.data(),
          inProposal: false,
        });
      }
    }
    if (!allowed && uid !== ownerUid) {
      allowed = mayReadSharedPhoto({
        uid,
        ownerUid,
        path,
        card: undefined,
        inProposal: await proposalNames(ownerUid, uid, personId),
      });
    }
    if (!allowed) throw new HttpsError('permission-denied', 'אין גישה לכרטיס');
    const file = getStorage().bucket().file(path);
    const [exists] = await file.exists();
    if (!exists) throw new HttpsError('not-found', 'התמונה לא נמצאה');
    const [metadata] = await file.getMetadata();
    if (Number(metadata.size ?? 0) > MAX_SHARED_PHOTO_BYTES) {
      throw new HttpsError('failed-precondition', 'התמונה גדולה מדי');
    }
    const [bytes] = await file.download();
    return { data: bytes.toString('base64'), contentType: metadata.contentType ?? 'image/jpeg' };
  },
);

function firstOf(map: unknown): string {
  if (!map || typeof map !== 'object') return '';
  const first = (map as Record<string, unknown>).firstName;
  return typeof first === 'string' ? first.trim() : '';
}

/** The notice an idea proposal carries, by its move. Pure, so it is tested. */
export function proposalNotice(
  was: string | null,
  now: string,
  doc: { fromName: string; toName: string; candidate: unknown; target: unknown; id: string },
): { to: 'from' | 'to'; kind: string; title: string; body: string; push: boolean } | null {
  const candidate = firstOf(doc.candidate) || 'מועמד/ת';
  const target = firstOf(doc.target) || 'החבר/ה שלך';
  if (now === 'pending' && was === null) {
    return {
      to: 'to',
      kind: 'ideaProposal',
      title: `${doc.fromName || 'שדכן/ית'} מציע/ה רעיון`,
      body: `${candidate} ו${target} – לאשר את הרעיון?`,
      // The offer is already in the chat between the two; activity in the
      // network is never pushed — only a request to connect is.
      push: false,
    };
  }
  if (was === null && (now === 'approved' || now === 'opened')) {
    // A couple space: the idea is already open on both phones.
    return {
      to: 'to',
      kind: 'ideaProposalApproved',
      title: `${doc.fromName || 'בן/בת הזוג'} פתח/ה רעיון משותף`,
      body: `${candidate} ו${target} — הרעיון פתוח אצל שניכם`,
      push: false,
    };
  }
  if (was === 'pending' && now === 'approved') {
    return {
      to: 'from',
      kind: 'ideaProposalApproved',
      title: `${doc.toName || 'השדכן/ית'} אישר/ה את הרעיון`,
      body: `${candidate} ו${target} — הרעיון ייפתח כשתחליטו לשאול את שניהם`,
      push: false,
    };
  }
  if (was === 'pending' && now === 'declined') {
    return {
      to: 'from',
      kind: 'ideaProposalDeclined',
      title: `הרעיון ${candidate} ו${target} לא התקדם`,
      body: `${doc.toName || 'השדכן/ית'} החליט/ה לא לפתוח את הרעיון`,
      // Nobody is woken to be told no; it waits quietly on the list.
      push: false,
    };
  }
  return null;
}

/** What a side's own status reads as in the chat — or null for none. */
export function sideEvent(was: string | undefined, now: string | undefined): string | null {
  if (!now || was === now) return null;
  switch (now) {
    case 'unavailable':
      return 'עבר להמתנה';
    case 'dating':
      return 'יוצאים';
    case 'dated':
    case 'rejected':
      return 'הרעיון נסגר';
    case 'married':
      return 'מזל טוב! חתונה';
    case 'idea':
    case 'checking':
      return was === undefined ? null : 'הרעיון חזר להיות פתוח';
    default:
      return null;
  }
}

/** The small system lines a proposal's moves write into the pair's chat. */
export function proposalEvents(
  was: string | null,
  now: string,
  sidesBefore: Record<string, { status?: string }>,
  sidesAfter: Record<string, { status?: string }>,
  names: Record<string, string>,
  pair: string,
): string[] {
  const events: string[] = [];
  if (was !== now) {
    // Between partners an idea opens at once, with no question asked.
    if (was === null && (now === 'approved' || now === 'opened')) events.push(`נפתח רעיון משותף: ${pair}`);
    if (was === 'pending' && now === 'approved') events.push(`הרעיון ${pair} אושר`);
    // Approving opens the idea at once (2026-11-21).
    if (was === 'pending' && now === 'opened') events.push(`הרעיון ${pair} אושר ונפתח`);
    if (was === 'approved' && now === 'opened') events.push(`הרעיון ${pair} נפתח`);
    if (was === 'pending' && now === 'declined') events.push(`הרעיון ${pair} לא אושר`);
    if (was === 'pending' && now === 'withdrawn') events.push(`ההצעה ${pair} בוטלה`);
  }
  for (const uid of Object.keys(sidesAfter ?? {})) {
    const line = sideEvent(sidesBefore?.[uid]?.status, sidesAfter[uid]?.status);
    if (!line) continue;
    const who = (names[uid] ?? '').trim().split(/\s+/)[0];
    events.push(`${pair}: ${line}${who ? ` (אצל ${who})` : ''}`);
  }
  return events;
}

/** Writes [lines] as system events into the one chat of [a] and [b]. */
async function chatEvents(
  a: string,
  b: string,
  names: Record<string, string>,
  lines: string[],
  ref: Record<string, unknown>,
): Promise<void> {
  if (lines.length === 0 || !a || !b) return;
  const db = getFirestore();
  const members = [a, b].sort();
  const chat = db.doc(`chats/${members[0]}_${members[1]}`);
  const snap = await chat.get();
  const batch = db.batch();
  // The conversation's own line, so the list shows it and sorts it — but no
  // unread count: system lines are small and never call for attention.
  batch.set(
    chat,
    {
      members,
      type: 'direct',
      ...(snap.exists ? {} : { names: { [a]: names[a] ?? '', [b]: names[b] ?? '' } }),
      lastText: [...lines[lines.length - 1]].slice(0, 200).join(''),
      lastType: 'system',
      lastFromUid: 'system',
      lastAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
    },
    { merge: true },
  );
  for (const text of lines) {
    batch.set(chat.collection('messages').doc(), {
      fromUid: 'system',
      system: true,
      text,
      ref,
      at: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

export const onIdeaProposalWritten = onDocumentWritten('ideaProposals/{id}', async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  if (!after?.exists) return;
  const was = before?.exists ? (before.get('status') as string) : null;
  const now = after.get('status') as string;
  const fromUid = after.get('fromUid') as string;
  const toUid = after.get('toUid') as string;
  const names: Record<string, string> = {
    [fromUid]: (after.get('fromName') as string) ?? '',
    [toUid]: (after.get('toName') as string) ?? '',
  };
  const pair = `${firstOf(after.get('candidate')) || 'מועמד/ת'} ו${firstOf(after.get('target')) || 'מועמד/ת'}`;
  try {
    await chatEvents(
      fromUid,
      toUid,
      names,
      proposalEvents(
        was,
        now,
        (before?.exists ? before.get('sides') : {}) ?? {},
        after.get('sides') ?? {},
        names,
        pair,
      ),
      { kind: 'proposal', id: event.params.id, label: pair },
    );
  } catch (error) {
    logger.warn('onIdeaProposalWritten: chat events', { error: String(error) });
  }
  if (was === now) return;
  const notice = proposalNotice(was, now, {
    fromName: (after.get('fromName') as string) ?? '',
    toName: (after.get('toName') as string) ?? '',
    candidate: after.get('candidate'),
    target: after.get('target'),
    id: event.params.id,
  });
  if (!notice) return;
  const uid = notice.to === 'to' ? after.get('toUid') : after.get('fromUid');
  await notify(
    uid as string,
    {
      kind: notice.kind,
      title: notice.title,
      body: notice.body,
      route: `/network/proposals/${event.params.id}`,
    },
    notice.push,
    `${notice.kind}_${event.params.id}`,
  );
});

/** What a message says in a push: its words, or what stands for them. */
export function chatPreview(type: unknown, text: string): string {
  if (text.trim().length > 0) return text;
  switch (type) {
    case 'voice':
      return 'הודעה קולית';
    case 'image':
      return 'תמונה';
    case 'card':
      return 'כרטיס';
    case 'idea':
      return 'רעיון';
    case 'ideaOffer':
      return 'יש לי רעיון בשבילך';
    default:
      return 'הודעה חדשה';
  }
}

/** The one conversation id of two accounts: the uids, sorted. */
export function directChatId(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

/**
 * Whether [other] may be written to by somebody who is not tied to them — a
 * card, a share, a partnership, the phone book: only a matchmaker the caller
 * was shown by the app itself, that is somebody who appears in the
 * community (a row on the board that is not hidden).
 */
export function communityExposed(member: Record<string, unknown> | undefined): boolean {
  return member !== undefined && member['hidden'] !== true;
}

/**
 * "צ'אט" from a matchmaker's public page (the leaderboard, the community):
 * opens the conversation with somebody the caller is not tied to, as an
 * ordinary chat — no request and no approval. The rules let a conversation
 * be *created* only between people tied to each other, and are already at
 * Firestore's ten-read limit, so this one case is created here, after the
 * server checked that [otherUid] is shown in the community. The first
 * message is then an ordinary update. Writes nothing when the conversation
 * already exists.
 */
export const openCommunityChat = onCall(async (request) => {
  const uid = request.auth?.uid;
  const provider = (request.auth?.token as { firebase?: { sign_in_provider?: string } } | undefined)
    ?.firebase?.sign_in_provider;
  if (!uid || provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  const otherUid = String((request.data as { otherUid?: unknown } | undefined)?.otherUid ?? '');
  if (!/^[A-Za-z0-9]{10,128}$/.test(otherUid) || otherUid === uid) {
    throw new HttpsError('invalid-argument', 'otherUid');
  }
  const db = getFirestore();
  const chatId = directChatId(uid, otherUid);
  const chat = db.doc(`chats/${chatId}`);
  const existing = await chat.get();
  if (existing.exists) return { chatId, created: false };
  const member = await db.doc(`communityMembers/${otherUid}`).get();
  if (!communityExposed(member.exists ? member.data() : undefined)) {
    throw new HttpsError('permission-denied', 'Not in the community.');
  }
  await db.runTransaction(async (tx) => {
    const again = await tx.get(chat);
    if (again.exists) return;
    tx.create(chat, {
      members: [uid, otherUid].sort(),
      type: 'direct',
      names: {},
      photos: {},
      unread: {},
      readAt: {},
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { chatId, created: true };
});

/** One chat message, pushed to the other members' phones (no inbox row). */
export const onChatMessageCreated = onDocumentCreated(
  'chats/{chatId}/messages/{messageId}',
  async (event) => {
    const message = event.data;
    if (!message) return;
    // A system line (an idea approved, moved to waiting…) is never pushed.
    if (message.get('system') === true) return;
    const db = getFirestore();
    const chat = await db.doc(`chats/${event.params.chatId}`).get();
    if (!chat.exists) return;
    const fromUid = message.get('fromUid') as string;
    const members = ((chat.get('members') as string[]) ?? []).filter((m) => m !== fromUid);
    const names = (chat.get('names') ?? {}) as Record<string, string>;
    const sender = (names[fromUid] ?? '').trim() || 'הודעה חדשה';
    const text = [...chatPreview(message.get('type'), String(message.get('text') ?? ''))]
      .slice(0, 160)
      .join('');
    const tokenDocs = await Promise.all(members.map((m) => db.doc(`fcmTokens/${m}`).get()));
    const tokens = [
      ...new Set(
        tokenDocs.filter((d) => !mutes(d, 'chatMessage')).flatMap((d) => d.get('tokens') ?? []),
      ),
    ] as string[];
    if (tokens.length === 0) return;
    try {
      await getMessaging().sendEachForMulticast({
        tokens,
        notification: { title: sender, body: text },
        data: { kind: 'chatMessage', route: `/chats/${event.params.chatId}` },
        android: { notification: { channelId: 'personal_card', tag: `chat_${event.params.chatId}` } },
        apns: { payload: { aps: { sound: 'default', 'thread-id': `chat_${event.params.chatId}` } } },
      });
    } catch (error) {
      logger.warn('onChatMessageCreated: push failed', { error: String(error) });
    }
  },
);

/**
 * Takes [ownerUid]'s personal card out of the shared pools of [matchmakerUids]
 * — the single withdrew consent, or the grant, or the card.
 */
export async function unshareCardOf(ownerUid: string, matchmakerUids: string[]): Promise<void> {
  const db = getFirestore();
  for (const uid of new Set(matchmakerUids.filter(Boolean))) {
    // Cards sent one by one in a chat leave too.
    const recipients = await db.collection('sentCards').doc(uid).collection('to').listDocuments();
    for (const to of recipients) {
      const sent = await to.collection('cards').where('cardOwnerUid', '==', ownerUid).get();
      for (const doc of sent.docs) await doc.ref.delete();
    }
    const snap = await db
      .collection('networkCards')
      .where('ownerUid', '==', uid)
      .where('cardOwnerUid', '==', ownerUid)
      .get();
    for (const doc of snap.docs) {
      await doc.ref.delete();
      await deletePhotos(uid, (doc.get('personId') as string) ?? '');
    }
  }
}

async function deletePhotos(ownerUid: string, personId: string): Promise<void> {
  if (!personId) return;
  try {
    await getStorage().bucket().deleteFiles({ prefix: `sharedCards/${ownerUid}/${personId}/` });
  } catch (error) {
    logger.warn('network: photos', { ownerUid, personId, error: String(error) });
  }
}

/** Who holds a grant row — the matchmaker, or both halves of a couple. */
export function granteesOf(row: { get(field: string): unknown }): string[] {
  const grantees = row.get('granteeUids');
  const matchmaker = row.get('matchmakerUid');
  return [
    ...(Array.isArray(grantees) ? (grantees as string[]) : []),
    ...(typeof matchmaker === 'string' ? [matchmaker] : []),
  ];
}

/** Whether a grant row still lets the matchmaker show the card onward. */
export function allowsOnward(row: { get(field: string): unknown } | undefined): boolean {
  return !!row && row.get('status') === 'approved' && row.get('shareOnward') === true;
}

/**
 * The single's consent is the switch: when it goes (or the grant does), the
 * card leaves every pool at once. When a matchmaker asks for it, the single
 * is told.
 */
export const onCardAccessShareOnward = onDocumentWritten('cardAccess/{accessId}', async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  const wasAllowed = allowsOnward(before?.exists ? before : undefined);
  const nowAllowed = allowsOnward(after?.exists ? after : undefined);
  const row = (after?.exists ? after : before) as DocumentSnapshot | undefined;
  if (!row?.exists) return;
  if (wasAllowed && !nowAllowed) {
    await unshareCardOf(row.get('ownerUid') as string, granteesOf(row));
  }
  if (
    after?.exists &&
    after.get('shareOnwardRequested') === true &&
    before?.get('shareOnwardRequested') !== true &&
    after.get('shareOnward') !== true
  ) {
    const name = ((after.get('matchmakerName') as string) ?? '').trim() || 'השדכן/ית שלך';
    await notify(
      after.get('ownerUid') as string,
      {
        kind: 'shareOnwardRequest',
        title: `${name} מבקש/ת שתאפשר/י שוב להציג את הכרטיס שלך לשדכנים שהם מכירים`,
        body: 'לא ציבורי ולא בלתי מוגבל — רק שדכנים שמכירים את השדכנים שאישרת, לצפייה בלבד. ההחלטה שלך.',
        route: '/me?section=approved',
      },
      true,
      `shareOnwardRequest_${event.params.accessId}_${after.updateTime?.toMillis() ?? 0}`,
    );
  }
});

/** A deleted personal card leaves every pool it was in. */
export const onPersonalCardDeletedUnshare = onDocumentWritten('personalCards/{uid}', async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  const wasLive = before?.exists && before.get('deleted') === false;
  const gone = !after?.exists || after.get('deleted') === true;
  if (!wasLive || !gone) return;
  const db = getFirestore();
  const rows = await db.collection('cardAccess').where('ownerUid', '==', event.params.uid).get();
  await unshareCardOf(event.params.uid, rows.docs.flatMap((d) => granteesOf(d)));
});

/** Everything [uid] put into the network, for an account that is going away. */
export async function deleteNetworkOf(uid: string): Promise<void> {
  const db = getFirestore();
  await db.recursiveDelete(db.collection('sharedCards').doc(uid));
  await db.recursiveDelete(db.collection('sentCards').doc(uid));
  try {
    await getStorage().bucket().deleteFiles({ prefix: `sharedCards/${uid}/` });
  } catch (error) {
    logger.warn('deleteNetworkOf: photos', { uid, error: String(error) });
  }
  for (const field of ['fromUid', 'toUid']) {
    for (;;) {
      const page = await db.collection('ideaProposals').where(field, '==', uid).limit(300).get();
      if (page.empty) break;
      const batch = db.batch();
      page.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }
  }
  const chats = await db.collection('chats').where('members', 'array-contains', uid).get();
  for (const chat of chats.docs) {
    await db.recursiveDelete(chat.ref);
  }
}

/**
 * A couple space ended: each side's published database is taken down at
 * once, whoever ended it — the rules already refuse every read, this only
 * removes what nobody can see any more. Nothing is deleted from either
 * personal database, and ideas already opened stay with both as history.
 */
export const onPartnershipWritten = onDocumentWritten('partnerships/{id}', async (event) => {
  const after = event.data?.after;
  const before = event.data?.before;
  const ended = !after?.exists || after.get('status') === 'ended';
  const wasActive = before?.exists && before.get('status') === 'active';
  if (!ended || !wasActive) return;
  const uids: string[] = (before.get('uids') as string[]) ?? [];
  for (const uid of uids) await deletePartnerCardsOf(uid);
});

/** Removes `partnerCards/{uid}` — the documents and their photos. */
export async function deletePartnerCardsOf(uid: string): Promise<void> {
  const db = getFirestore();
  const cards = await db.collection(`partnerCards/${uid}/cards`).get();
  for (const d of cards.docs) await d.ref.delete();
  try {
    await getStorage().bucket().deleteFiles({ prefix: `partnerCards/${uid}/` });
  } catch (error) {
    logger.warn('deletePartnerCardsOf: photos', { error: String(error) });
  }
}
