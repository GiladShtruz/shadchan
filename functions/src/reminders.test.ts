import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DueReminder, israelLocalToUtc, pickDue, pushText, WINDOW_HOURS } from './reminders';

const HOUR = 60 * 60 * 1000;

test('an idea reminder written as local time is read as Israel time', () => {
  // 10:00 in Israel in winter (UTC+2) is 08:00 UTC.
  assert.equal(israelLocalToUtc('2026-12-08T10:00:00.000'), Date.UTC(2026, 11, 8, 8, 0, 0));
  // In summer (UTC+3) it is 07:00 UTC.
  assert.equal(israelLocalToUtc('2026-07-08T10:00:00.000'), Date.UTC(2026, 6, 8, 7, 0, 0));
  // An explicit offset is respected as written.
  assert.equal(israelLocalToUtc('2026-12-08T10:00:00Z'), Date.UTC(2026, 11, 8, 10, 0, 0));
});

test('only fresh reminders are pushed, each once — never a backlog', () => {
  const now = Date.UTC(2026, 11, 8, 12);
  const r = (key: string, hoursAgo: number): DueReminder => ({
    key, kind: 'idea', targetId: key, dueAt: now - hoursAgo * HOUR,
  });
  const due = pickDue(
    [r('fresh', 1), r('sent', 1), r('old', WINDOW_HOURS + 48), r('future', -2)],
    { sent: now - HOUR },
    now,
  );
  assert.deepEqual(due.map((d) => d.key), ['fresh']);
});

test('the push never names anybody, and many become one summary', () => {
  const one = pushText([{ key: 'k', kind: 'idea', targetId: 'm1', dueAt: 0 }]);
  assert.equal(one.route, '/matches/m1');
  assert.equal(one.title, 'הגיע הזמן לחזור לרעיון');

  const many = pushText(
    Array.from({ length: 5 }, (_, i) => ({ key: `k${i}`, kind: 'friend' as const, targetId: `p${i}`, dueAt: 0 })),
  );
  assert.equal(many.route, '/reminders');
  assert.match(many.title, /5 תזכורות/);
});

test('friend reminders are found: the key range ends after the prefix', async () => {
  const { FRIEND_KEY_PREFIX, FRIEND_KEY_END } = await import('./reminders');
  const inRange = (k: string) => k >= FRIEND_KEY_PREFIX && k < FRIEND_KEY_END;
  assert.equal(inRange('personReminder.abc-123'), true);
  // The note beside it, and anything else, are not reminders.
  assert.equal(inRange('personReminderNote.abc-123'), false);
  assert.equal(inRange('personalCard.person'), false);
});

test('a friend reminder setting becomes a reminder; its note and junk do not', async () => {
  const { friendReminderOf } = await import('./reminders');
  const due = Date.UTC(2026, 11, 8, 8);
  assert.deepEqual(friendReminderOf({ k: 'personReminder.p1', v: JSON.stringify(due) })?.targetId, 'p1');
  assert.equal(friendReminderOf({ k: 'personReminderNote.p1', v: '"x"' }), null);
  assert.equal(friendReminderOf({ k: 'personReminder.p1', v: 'not json' }), null);
  assert.equal(friendReminderOf({ _deleted: true }), null);
});

test('a bare date is pushed at 09:00 Israel time, never at midnight', async () => {
  const { pushMomentOf } = await import('./reminders');
  // Midnight in Israel in winter (UTC+2) is 22:00 UTC the day before.
  const midnight = Date.UTC(2026, 11, 7, 22, 0, 0);
  assert.equal(pushMomentOf(midnight), Date.UTC(2026, 11, 8, 7, 0, 0));
  // A reminder with a time of its own keeps it.
  const tenAm = Date.UTC(2026, 11, 8, 8, 0, 0);
  assert.equal(pushMomentOf(tenAm), tenAm);
});

test('a reminder is pushed by its push moment, and keyed by its own', () => {
  const now = Date.UTC(2026, 11, 8, 8);
  const r: DueReminder = {
    key: 'friend:p:1', kind: 'friend', targetId: 'p', dueAt: now - 9 * HOUR, pushAt: now - HOUR,
  };
  assert.equal(pickDue([r], {}, now).length, 1);
  assert.equal(pickDue([{ ...r, pushAt: now + HOUR }], {}, now).length, 0);
});

test('only users/{uid}/{collection}/{id} paths name an account', async () => {
  const { accountOfPath } = await import('./reminders');
  assert.equal(accountOfPath('users/u1/matches/m1', 'matches'), 'u1');
  assert.equal(accountOfPath('coupleArchives/x/matches/m1', 'matches'), null);
  assert.equal(accountOfPath('users/u1/settings/s', 'matches'), null);
});
