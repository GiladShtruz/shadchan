import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { isActiveCard } from './card_activity';
export type Gender = 'male' | 'female' | 'unknown';

export interface Notice {
  kind: string;
  newsId?: string;
  title: string;
  body: string;
  route: string;
  ownerUid?: string;
  /** Lets the matchmaker's app find the friend in its own database. */
  ownerPhoneHash?: string;
}

/** `{male|female}` → the right form for [gender]; masculine when unknown. */
export function g(template: string, gender: Gender | undefined): string {
  return template.replace(/\{([^|{}]*)\|([^|{}]*)\}/g, (_m, male, female) =>
    gender === 'female' ? female : male,
  );
}

/**
 * The notices worth a push to the phone: the personal card's own events. The
 * rest (a decline, a wedding, a birthday, a status report) wait quietly on the
 * notifications page. Reminders are pushed by the phone itself.
 */
const PUSHED_KINDS = new Set([
  'cardCreated',
  'accessApproved',
  'accessRequest',
  'friendJoined',
  'cardUpdated',
  'personalNews',
]);

/** Writes the inbox row and pushes to every device of [uid]. */
export async function notify(
  uid: string,
  notice: Notice,
  push = true,
  id?: string,
): Promise<void> {
  const db = getFirestore();
  const membership = [
    'cardUpdated',
    'accessApproved',
    'accessDeclined',
    'mazelTov',
    'birthday',
  ].includes(notice.kind)
    ? await db.doc(`memberships/${uid}`).get()
    : null;
  const paired = membership?.get('state') === 'active';
  const needsGrant =
    !!notice.ownerUid &&
    ['accessApproved', 'cardUpdated', 'birthday', 'mazelTov'].includes(
      notice.kind,
    );
  const inbox = paired
    ? db
        .collection('coupleData')
        .doc(membership!.get('operation'))
        .collection('inbox')
    : db.collection('users').doc(uid).collection('inbox');
  const row = id ? inbox.doc(id) : inbox.doc();
  const written = await db.runTransaction(async (tx) => {
    let message = notice;
    // A delayed fan-out must not resurrect a deleted/unpublished announcement.
    if (notice.kind === 'personalNews' && notice.newsId) {
      const [news, card] = await Promise.all([
        tx.get(db.doc(`personalNews/${notice.newsId}`)),
        tx.get(db.doc(`personalCards/${uid}`)),
      ]);
      if (
        !news.exists ||
        news.get('published') !== true ||
        news.get('notify') !== true ||
        !isActiveCard(card.data())
      )
        return false;
      message = { ...notice, title: news.get('title'), body: news.get('text') };
    }
    if (needsGrant) {
      const [grant, liveMembership] = await Promise.all([
        tx.get(db.doc(`cardAccess/${notice.ownerUid}_${uid}`)),
        tx.get(db.doc(`memberships/${uid}`)),
      ]);
      const livePaired = liveMembership.get('state') === 'active';
      if (
        livePaired !== paired ||
        (paired &&
          liveMembership.get('operation') !== membership!.get('operation'))
      )
        return false;
      if (grant.get('status') !== 'approved') return false;
      if (
        notice.kind === 'accessApproved'
          ? grant.get('cardGranted') === false &&
            grant.get('lookingGranted') !== true
          : grant.get('cardGranted') === false
      )
        return false;
      const recipients = grant.get('granteeUids') ?? [uid];
      if (
        paired
          ? JSON.stringify(recipients) !==
            JSON.stringify(liveMembership.get('members'))
          : JSON.stringify(recipients) !== JSON.stringify([uid])
      )
        return false;
    }
    if (id && (await tx.get(row)).exists) return false;
    tx.set(row, {
      ...message,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    return message;
  });
  if (!written) return;
  notice = written;

  if (!push || !PUSHED_KINDS.has(notice.kind)) {
    return;
  }
  const recipients = paired ? (membership!.get('members') as string[]) : [uid];
  const tokenDocs = await Promise.all(
    recipients.map((id) => db.doc(`fcmTokens/${id}`).get()),
  );
  const tokens: string[] = [
    ...new Set(tokenDocs.flatMap((d) => d.get('tokens') ?? [])),
  ];
  if (tokens.length === 0) {
    return;
  }
  // The icon's number while the app is closed: the server's unread notices.
  // The app puts it right (reminders included) the next time it is open.
  let unread = 1;
  try {
    const counted = await inbox.where('read', '==', false).count().get();
    unread = Math.max(1, counted.data().count);
  } catch (error) {
    console.warn('notify: unread count failed', error);
  }
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: notice.title,
      body: [...notice.body].slice(0, 180).join(''),
    },
    data: {
      kind: notice.kind,
      route: notice.route,
      ownerUid: notice.ownerUid ?? '',
      ownerPhoneHash: notice.ownerPhoneHash ?? '',
      // A tapped push marks its own row read.
      inboxId: paired ? `couple:${row.id}` : row.id,
    },
    android: {
      notification: { channelId: 'personal_card', notificationCount: unread },
    },
    apns: { payload: { aps: { sound: 'default', badge: unread } } },
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
    await Promise.all(
      tokenDocs
        .filter((d) => d.exists)
        .map((d) => d.ref.update({ tokens: FieldValue.arrayRemove(...dead) })),
    );
  }
}
