import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectionId, joinedRecently } from './matchmaker_connections';

test('one document per pair, whoever asks', () => {
  assert.equal(connectionId('bbb', 'aaa'), 'aaa_bbb');
  assert.equal(connectionId('aaa', 'bbb'), 'aaa_bbb');
});

test('only a recent join is news', () => {
  const now = Date.UTC(2026, 10, 16);
  const day = 86400000;
  assert.equal(joinedRecently(now - 2 * day, now), true);
  assert.equal(joinedRecently(now - 7 * day, now), true);
  assert.equal(joinedRecently(now - 8 * day, now), false);
  // A colleague of years whom the owner only now saved in their phone.
  assert.equal(joinedRecently(now - 400 * day, now), false);
  // No join date at all (an account from before the field) is never news.
  assert.equal(joinedRecently(null, now), false);
  assert.equal(joinedRecently(undefined, now), false);
});
