import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectionId, joinedRecently, shareNotice, isActiveShare } from './matchmaker_shares';

test('connectionId sorts the pair', () => {
  assert.equal(connectionId('bbb', 'aaa'), 'aaa_bbb');
  assert.equal(connectionId('aaa', 'bbb'), 'aaa_bbb');
});

test('joinedRecently: only within the window', () => {
  const now = Date.UTC(2026, 10, 20);
  assert.equal(joinedRecently(now - 86400000, now), true);
  assert.equal(joinedRecently(now - 8 * 86400000, now), false);
  assert.equal(joinedRecently(null, now), false);
});

test('active modes', () => {
  assert.equal(isActiveShare('all'), true);
  assert.equal(isActiveShare('selected'), true);
  assert.equal(isActiveShare('allExcept'), true);
  assert.equal(isActiveShare('none'), false);
  assert.equal(isActiveShare('requested'), false);
  assert.equal(isActiveShare(null), false);
});

test('a request reaches the owner', () => {
  const n = shareNotice(null, 'requested', 'יונתן', 'רחל');
  assert.equal(n?.to, 'owner');
  assert.equal(n?.kind, 'shareRequest');
  assert.match(n!.title, /רחל/);
});

test('a new share reaches the reader, also after a request', () => {
  assert.equal(shareNotice(null, 'all', 'יונתן', 'רחל')?.kind, 'shareOpened');
  assert.equal(shareNotice('requested', 'selected', 'יונתן', 'רחל')?.to, 'reader');
  assert.equal(shareNotice('none', 'allExcept', 'יונתן', 'רחל')?.kind, 'shareOpened');
});

test('a stop reaches the reader; a change between active modes says nothing', () => {
  assert.equal(shareNotice('all', 'none', 'יונתן', 'רחל')?.kind, 'shareStopped');
  assert.equal(shareNotice('selected', null, 'יונתן', 'רחל')?.kind, 'shareStopped');
  assert.equal(shareNotice('all', 'selected', 'יונתן', 'רחל'), null);
  assert.equal(shareNotice('none', 'none', 'יונתן', 'רחל'), null);
});
