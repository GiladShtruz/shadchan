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
