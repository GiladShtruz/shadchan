/**
 * The decisions that keep the server from reading the whole database over
 * and over — pure, so the tests can pin them (`read_budget.test.ts`).
 *
 * **Why this file exists (2026-11-22).** The project was reading ~800,000
 * documents a day for a few dozen active matchmakers. Two triggers did almost
 * all of it: every write of `matchmakerActivity/{uid}` (several per session)
 * and of `communityMembers/{uid}` rebuilt, from scratch, the list of
 * matchmakers in the address book of that user *and of everybody who has
 * their number* (one read per contact, a median of ~1,100 contacts), and then
 * re-read three whole collections for the personal-area figures. Measured:
 * 723 runs a day, 26,000 seconds of compute, ~92% of all function time.
 *
 * The rule now: a write only does work when something another person can see
 * actually changed, and only the rows that show it are touched.
 */

/** A value of a Firestore timestamp or of a plain number, in ms. */
export function millisOf(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return value;
  const v = value as { toMillis?: () => number };
  return typeof v.toMillis === 'function' ? v.toMillis() : null;
}

/** "Last active" moves on a helper row at most this often. */
export const ACTIVITY_PATCH_EVERY_MS = 60 * 60 * 1000;

/**
 * What a write of `matchmakerActivity/{uid}` asks of the server:
 *  - `rebuild` — the first one ever: the account just became a matchmaker
 *    who is active, so its own list (and its friends') is worked out once;
 *  - `patch` — the database size changed, or "last active" moved by an hour
 *    or more: the row this matchmaker has on other people's lists is updated
 *    in place, nothing else;
 *  - `none` — anything else (the same hour again, a deletion).
 */
export function activityChange(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): 'rebuild' | 'patch' | 'none' {
  if (!after) return 'none';
  if (!before) return 'rebuild';
  if ((before.databaseCount ?? null) !== (after.databaseCount ?? null)) {
    return 'patch';
  }
  const was = millisOf(before.lastActiveAt);
  const now = millisOf(after.lastActiveAt);
  if (now === null) return 'none';
  if (was === null || now - was >= ACTIVITY_PATCH_EVERY_MS) return 'patch';
  return 'none';
}

/**
 * The fields of `communityMembers/{uid}` that `findHelpers` copies onto other
 * people's lists. The counters on the same document change on every
 * publish and are read by nobody's list — a change to them alone is no
 * reason to rebuild anything.
 */
export const MEMBER_FIELDS_ON_LISTS = ['hidden', 'photoUrl', 'joinedAt'] as const;

export function memberListFieldsChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): boolean {
  if (!before || !after) return before !== after;
  return MEMBER_FIELDS_ON_LISTS.some(
    (field) => stableJson(before[field]) !== stableJson(after[field]),
  );
}

/**
 * JSON with sorted keys and timestamps as milliseconds — two lists built from
 * the same data compare equal however the SDK happened to shape them.
 */
export function stableJson(value: unknown): string {
  return JSON.stringify(normalise(value));
}

function normalise(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  const ms = typeof value === 'object' ? millisOf(value) : null;
  if (ms !== null) return { $ms: ms };
  if (Array.isArray(value)) return value.map(normalise);
  if (typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(value as object).sort()) {
      out[key] = normalise((value as Record<string, unknown>)[key]);
    }
    return out;
  }
  return value;
}

/**
 * The helper rows with [uid]'s figures replaced, or null when no row is
 * [uid]'s or nothing on it would change (so nothing is written).
 */
export function patchHelperRows(
  helpers: unknown,
  uid: string,
  figures: { databaseCount: unknown; lastActiveAt: unknown },
): Record<string, unknown>[] | null {
  if (!Array.isArray(helpers)) return null;
  let changed = false;
  const next = helpers.map((row) => {
    if (!row || typeof row !== 'object') return row;
    const r = row as Record<string, unknown>;
    if (r.uid !== uid) return r;
    const databaseCount = figures.databaseCount ?? null;
    const lastActiveAt = figures.lastActiveAt ?? null;
    if (
      stableJson(r.databaseCount ?? null) === stableJson(databaseCount) &&
      stableJson(r.lastActiveAt ?? null) === stableJson(lastActiveAt)
    ) {
      return r;
    }
    changed = true;
    return { ...r, databaseCount, lastActiveAt };
  });
  return changed ? (next as Record<string, unknown>[]) : null;
}

/** Whether the list just built differs from the one already stored. */
export function helperListChanged(
  stored: Record<string, unknown> | undefined,
  next: { helpers: unknown; friends: unknown; uids: unknown },
): boolean {
  if (!stored) return true;
  return (
    stableJson(stored.helpers) !== stableJson(next.helpers) ||
    stableJson(stored.friends) !== stableJson(next.friends) ||
    stableJson(stored.uids) !== stableJson(next.uids)
  );
}

/**
 * The personal-area figures without their bookkeeping fields, so a run that
 * found the same numbers writes nothing — every write of
 * `publicStats/personalArea` is a read on every phone listening to it.
 */
export function sameFigures(
  stored: Record<string, unknown> | undefined,
  next: Record<string, unknown>,
): boolean {
  if (!stored) return false;
  const strip = (o: Record<string, unknown>) => {
    const copy: Record<string, unknown> = { ...o };
    delete copy.startedAt;
    delete copy.updatedAt;
    return copy;
  };
  return stableJson(strip(stored)) === stableJson(strip(next));
}
