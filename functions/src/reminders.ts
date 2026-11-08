/**
 * Reminders from the server — one push per account, whichever phone it is on.
 *
 * A reminder used to be scheduled on every phone separately, so a matchmaker
 * signed in on a phone and a tablet heard it twice, and handling it on one did
 * not stop the other. The reminder itself already lives in the account (an
 * idea's `reminderDate`, a friend's `personReminder.{id}` setting), so the
 * server can do it once:
 *
 * * **Every hour**, for each account with a push token, the reminders that came
 *   due in the last few hours are collected.
 * * **One push per reminder, or one summary** when more than three came due
 *   together ("יש לך 5 תזכורות שכדאי לחזור אליהן") — never a wall of them.
 * * **Never a backlog.** Only reminders due within the last [WINDOW_HOURS]
 *   are pushed. Somebody back after two months, a migration, a bug fix — none
 *   of them releases a queue of old pushes; the overdue ones wait, silently,
 *   on the notifications page.
 * * **Each reminder once.** What was pushed is remembered per account
 *   (`users/{uid}/private/reminderPushes`), keyed by the reminder and its due
 *   moment: a reminder moved to a new date is a new reminder; the same one is
 *   never sent twice.
 * * **No names in the push.** The text is generic; the person or idea is on
 *   the notifications page and opens from the push itself. A push travels
 *   through Google and Apple, and the database's people stay out of it.
 *
 * Phones that receive these stop scheduling their own (see
 * `NotificationService.serverDelivers` in the app). Paired (couple) databases
 * keep the phone-side reminders for now.
 */
import { Firestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

export const WINDOW_HOURS = 3;
const SUMMARY_ABOVE = 3;
const HOUR = 60 * 60 * 1000;

export interface DueReminder {
  key: string;
  kind: 'idea' | 'friend';
  targetId: string;
  dueAt: number;
}

/**
 * An idea's `reminderDate` is the phone's local time written without an
 * offset ("2026-12-08T10:00:00.000"). Read as Israel time — the app's users
 * are there, and a reminder an hour off is worse than one read the way it
 * was written.
 */
export function israelLocalToUtc(iso: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/.exec(iso);
  if (!m) return null;
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(iso)) {
    const parsed = Date.parse(iso);
    return Number.isNaN(parsed) ? null : parsed;
  }
  const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] ?? 0));
  // Israel's offset at that moment (2h winter, 3h summer).
  const shown = new Date(asUtc).toLocaleString('en-US', { timeZone: 'Asia/Jerusalem', hour12: false });
  const sm = /(\d+)\/(\d+)\/(\d+), (\d+):(\d+):(\d+)/.exec(shown);
  if (!sm) return asUtc;
  const hour = +sm[4] === 24 ? 0 : +sm[4];
  const local = Date.UTC(+sm[3], +sm[1] - 1, +sm[2], hour, +sm[5], +sm[6]);
  return asUtc - (local - asUtc);
}

/** Which of [candidates] to push now: due in the window and not sent yet. */
export function pickDue(
  candidates: DueReminder[],
  alreadySent: Record<string, number>,
  now: number,
): DueReminder[] {
  return candidates
    .filter((r) => r.dueAt <= now && r.dueAt > now - WINDOW_HOURS * HOUR)
    .filter((r) => alreadySent[r.key] === undefined)
    .sort((a, b) => a.dueAt - b.dueAt);
}

/** What the push says — never who it is about. */
export function pushText(due: DueReminder[]): { title: string; body: string; route: string } {
  if (due.length > SUMMARY_ABOVE) {
    return {
      title: `יש לך ${due.length} תזכורות שכדאי לחזור אליהן`,
      body: 'הפרטים מחכים בעמוד ההתראות',
      route: '/reminders',
    };
  }
  const first = due[0];
  return first.kind === 'idea'
    ? { title: 'הגיע הזמן לחזור לרעיון', body: 'לחיצה פותחת אותו', route: `/matches/${first.targetId}` }
    : { title: 'תזכורת על חבר מהמאגר', body: 'לחיצה פותחת את הפרופיל', route: `/people/${first.targetId}` };
}

async function remindersOf(db: Firestore, uid: string, now: number): Promise<DueReminder[]> {
  const user = db.collection('users').doc(uid);
  const out: DueReminder[] = [];
  // Ideas: a string range on the stored local time, with a day of slack on
  // each side for the offset; the exact cut is made after parsing.
  const fmt = (t: number) => new Date(t).toISOString().slice(0, 19);
  const ideas = await user
    .collection('matches')
    .where('reminderDate', '>=', fmt(now - WINDOW_HOURS * HOUR - 26 * HOUR))
    .where('reminderDate', '<=', fmt(now + 26 * HOUR))
    .get();
  for (const doc of ideas.docs) {
    if (doc.get('_deleted') === true) continue;
    const raw = doc.get('reminderDate');
    const dueAt = typeof raw === 'string' ? israelLocalToUtc(raw) : null;
    if (dueAt === null) continue;
    out.push({ key: `idea:${doc.id}:${dueAt}`, kind: 'idea', targetId: doc.id, dueAt });
  }
  // Friends: `personReminder.{id}` settings, the value the due time in ms.
  const friends = await user
    .collection('settings')
    .where('k', '>=', 'personReminder.')
    .where('k', '<=', 'personReminder.')
    .get();
  for (const doc of friends.docs) {
    if (doc.get('_deleted') === true) continue;
    const key = doc.get('k');
    let dueAt: unknown;
    try {
      dueAt = JSON.parse(doc.get('v'));
    } catch {
      continue;
    }
    if (typeof key !== 'string' || typeof dueAt !== 'number') continue;
    const personId = key.substring('personReminder.'.length);
    out.push({ key: `friend:${personId}:${dueAt}`, kind: 'friend', targetId: personId, dueAt });
  }
  return out;
}

export async function sendDueReminders(db: Firestore, now = Date.now()): Promise<number> {
  // Tells the app it may stop scheduling its own (it keeps them until this
  // has run at least once).
  await db.doc('publicStats/serverReminders').set({ active: true, lastRunAt: now }, { merge: true });

  const tokenDocs = await db.collection('fcmTokens').get();
  let pushed = 0;
  for (const tokenDoc of tokenDocs.docs) {
    try {
      pushed += await remindAccount(db, tokenDoc, now);
    } catch (error) {
      // One account's failure must not cost everybody else their reminder.
      console.warn('sendDueReminders: account failed', tokenDoc.id, error);
    }
  }
  return pushed;
}

async function remindAccount(
  db: Firestore,
  tokenDoc: FirebaseFirestore.QueryDocumentSnapshot,
  now: number,
): Promise<number> {
  let pushed = 0;
  {
    const uid = tokenDoc.id;
    const tokens: string[] = tokenDoc.get('tokens') ?? [];
    if (tokens.length === 0) return 0;
    // Couple databases are not under users/{uid}; their phones keep their own.
    const membership = await db.doc(`memberships/${uid}`).get();
    if (membership.get('state') === 'active') return 0;

    const ledgerRef = db.doc(`users/${uid}/private/reminderPushes`);
    const ledger = await ledgerRef.get();
    const sent: Record<string, number> = ledger.get('sent') ?? {};
    const due = pickDue(await remindersOf(db, uid, now), sent, now);
    if (due.length === 0) return 0;

    // More than three at once are one summary; otherwise one push each.
    const batches: DueReminder[][] = due.length > SUMMARY_ABOVE ? [due] : due.map((r) => [r]);
    const dead = new Set<string>();
    for (const batch of batches) {
      const text = pushText(batch);
      const single = batch.length === 1 ? batch[0] : null;
      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: { title: text.title, body: text.body },
        data: { kind: 'reminder', route: text.route },
        android: {
          notification: {
            channelId: single?.kind === 'friend' ? 'person_reminders' : 'match_reminders',
          },
        },
        apns: { payload: { aps: { sound: 'default' } } },
      });
      pushed++;
      response.responses.forEach((r, i) => {
        const code = r.error?.code ?? '';
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          dead.add(tokens[i]);
        }
      });
    }

    // Remember what went, and forget anything older than a week.
    const keep: Record<string, number> = {};
    for (const [key, at] of Object.entries(sent)) {
      if (at > now - 7 * 24 * HOUR) keep[key] = at;
    }
    for (const r of due) keep[r.key] = now;
    await ledgerRef.set({ sent: keep, updatedAt: FieldValue.serverTimestamp() });

    if (dead.size > 0) {
      await tokenDoc.ref.update({ tokens: FieldValue.arrayRemove(...dead) });
    }
  }
  return pushed;
}
