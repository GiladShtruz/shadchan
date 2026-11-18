import { test } from 'node:test';
import assert from 'node:assert/strict';
import { categoryOf, mutes } from './notices';

const doc = (muted: unknown) => ({ get: (f: string) => (f === 'muted' ? muted : undefined) });

test('every kind sits under the same switch as in the app', () => {
  assert.equal(categoryOf('reminder'), 'ideas');
  assert.equal(categoryOf('cardCreated'), 'cardFriends');
  assert.equal(categoryOf('friendJoined'), 'newMatchmakers');
  assert.equal(categoryOf('accessApproved'), 'access');
  assert.equal(categoryOf('birthday'), 'celebrations');
  assert.equal(categoryOf('personalNews'), 'system');
  assert.equal(categoryOf('anythingElse'), 'system');
});

test('a switched-off kind is not pushed; everything is on by default', () => {
  assert.equal(mutes(doc(undefined), 'cardCreated'), false);
  assert.equal(mutes(doc(['cardFriends']), 'cardCreated'), true);
  assert.equal(mutes(doc(['cardFriends']), 'accessRequest'), false);
  assert.equal(mutes(doc(['ideas']), 'reminder'), true);
});
