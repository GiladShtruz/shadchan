import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AlertInputs, compareVersions, computeAlerts, contactsBlock, newAlerts } from './admin_alerts';

const DAY = 24 * 60 * 60 * 1000;
const now = Date.UTC(2026, 10, 8, 12);

function base(overrides: Partial<AlertInputs> = {}): AlertInputs {
  return {
    now,
    contacts: contactsBlock([], now),
    contactDevices: [],
    dau: 50,
    dauHistory: [50, 52, 48],
    new7: 20,
    newPrev7: 22,
    pending: 5,
    pendingWeekAgo: 4,
    remindersLastRunAt: now - 30 * 60 * 1000,
    ...overrides,
  };
}

test('a normal week raises nothing', () => {
  assert.deepEqual(computeAlerts(base()), []);
});

test('versions are ordered by number, whatever the spelling', () => {
  assert.ok(compareVersions('1.0.21+64', '1.0.9+50') > 0);
  assert.ok(compareVersions('1.0.21 (65)', '1.0.21+64') > 0);
});

test('failing address-book reads raise an alert, with the common error', () => {
  const devices = [
    { readAt: now - DAY, suitable: 100 },
    { readAt: now - DAY, suitable: 100 },
    { readAt: now - 9 * DAY, failedAt: now - DAY, failure: 'platformexception' },
    { failedAt: now - 2 * DAY, failure: 'platformexception' },
    { failedAt: now - 3 * DAY, failure: 'timeoutexception' },
  ];
  const contacts = contactsBlock(devices, now);
  assert.equal(contacts.failing7, 3);
  assert.equal(contacts.topFailure, 'platformexception');
  const codes = computeAlerts(base({ contacts, contactDevices: devices })).map((a) => a.code);
  assert.deepEqual(codes, ['contacts_failing']);
});

test('a new version that finds half the contacts is caught', () => {
  const devices = [
    ...[100, 120, 90].map((s) => ({ appVersion: '1.0.20+63', readAt: now - DAY, suitable: s })),
    ...[30, 40, 20].map((s) => ({ appVersion: '1.0.21+64', readAt: now - DAY, suitable: s })),
  ];
  const alerts = computeAlerts(base({ contacts: contactsBlock(devices, now), contactDevices: devices }));
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].code, 'contacts_version_drop');
  assert.match(alerts[0].title, /1\.0\.21\+64/);
});

test('activity, sign-ups, piling requests and a stopped reminders job', () => {
  const codes = computeAlerts(
    base({
      dau: 10,
      new7: 3,
      newPrev7: 20,
      pending: 40,
      pendingWeekAgo: 10,
      remindersLastRunAt: now - 5 * 60 * 60 * 1000,
    }),
  ).map((a) => a.code);
  assert.deepEqual(codes, ['dau_drop', 'signups_drop', 'pending_requests_pile', 'reminders_stale']);
});

test('only alerts not raised last time are announced', () => {
  const fresh = newAlerts(
    [{ code: 'dau_drop', severity: 'medium', title: '', detail: '' }],
    [
      { code: 'dau_drop', severity: 'medium', title: '', detail: '' },
      { code: 'signups_drop', severity: 'medium', title: '', detail: '' },
    ],
  );
  assert.deepEqual(fresh.map((a) => a.code), ['signups_drop']);
});
