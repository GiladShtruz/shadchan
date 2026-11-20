import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

/**
 * Restoring the card permissions the old couple merge took away.
 *
 * Until 2026-11-20 accepting a couple invitation (`acceptCoupleInvite`, step
 * `grants`) set **every** approved grant of both spouses to `revoked`, and
 * opened one pending request in the pair's name instead. Splitting the couple
 * revoked the pair's rows too. Nothing ever put the original approvals back,
 * so a matchmaker who tried the couple database lost access to every card a
 * single had once given them.
 *
 * The new couple space (2026-11-20) never touches a grant, so this repairs the
 * past only. It is idempotent and only ever acts for the caller's own rows.
 */

/** What the pair row says, and what that means for the personal row. */
export type RestoreDecision = 'restore' | 'keep';

/**
 * Whether a personal row the merge revoked should be approved again.
 *
 * Only a row that is `revoked` *and* has a pair row next to it was revoked by
 * the merge — a single who revoked access by hand leaves no pair row behind.
 * The owner's own word on the pair row wins: a block or a decline is kept, and
 * so is a revocation made while the couple was still together (a split never
 * happened then, so it can only have been the owner).
 */
export function restoreDecision(input: {
  personalStatus: string | undefined;
  pairStatus: string | undefined;
  coupleState: string | undefined;
}): RestoreDecision {
  if (input.personalStatus !== 'revoked') return 'keep';
  const pair = input.pairStatus;
  if (pair === undefined) return 'keep';
  if (pair === 'approved' || pair === 'pending') return 'restore';
  if (pair === 'revoked' && input.coupleState !== 'active') return 'restore';
  return 'keep';
}

export const restoreRevokedGrants = onCall(
  { region: 'europe-west1', timeoutSeconds: 120 },
  async (request) => {
    if (
      !request.auth ||
      request.auth.token.firebase?.sign_in_provider === 'anonymous'
    )
      throw new HttpsError('unauthenticated', 'נדרשת התחברות');
    const uid = request.auth.uid;
    const db = getFirestore();
    const couples = await db
      .collection('couples')
      .where('members', 'array-contains', uid)
      .get();
    if (couples.empty) return { restored: 0 };
    const revoked = await db
      .collection('cardAccess')
      .where('matchmakerUid', '==', uid)
      .where('status', '==', 'revoked')
      .get();
    let restored = 0;
    for (const row of revoked.docs) {
      const owner = row.get('ownerUid');
      if (typeof owner !== 'string') continue;
      for (const couple of couples.docs) {
        const pair = await db.doc(`cardAccess/${owner}_${couple.id}`).get();
        if (!pair.exists) continue;
        const decision = restoreDecision({
          personalStatus: row.get('status'),
          pairStatus: pair.get('status'),
          coupleState: couple.get('state'),
        });
        if (decision !== 'restore') continue;
        // Only fields the rules already allow on a grant — a field outside
        // their list would make every later write to this row fail.
        await row.ref.update({
          status: 'approved',
          cardGranted: true,
          cardRequested: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
        // While the couple is still together the rules read the pair's row:
        // a request the merge opened is answered by the single's earlier yes.
        if (couple.get('state') === 'active' && pair.get('status') === 'pending')
          await pair.ref.update({
            status: 'approved',
            cardGranted: true,
            cardRequested: false,
            updatedAt: FieldValue.serverTimestamp(),
          });
        restored++;
        break;
      }
    }
    if (restored > 0) logger.info('restoreRevokedGrants', { uid, restored });
    return { restored };
  },
);
