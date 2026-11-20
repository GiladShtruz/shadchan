import { test } from 'node:test';
import assert from 'node:assert/strict';
import { restoreDecision } from './grant_restore';

test('a grant the merge revoked comes back while its pair row is open', () => {
  for (const pair of ['approved', 'pending'])
    assert.equal(
      restoreDecision({ personalStatus: 'revoked', pairStatus: pair, coupleState: 'active' }),
      'restore',
    );
});

test('after a split the pair row was revoked by the split, not the single', () => {
  assert.equal(
    restoreDecision({ personalStatus: 'revoked', pairStatus: 'revoked', coupleState: 'split' }),
    'restore',
  );
  assert.equal(
    restoreDecision({ personalStatus: 'revoked', pairStatus: 'revoked', coupleState: 'active' }),
    'keep',
  );
});

test('the single\'s own no is never undone', () => {
  for (const pair of ['blocked', 'declined'])
    assert.equal(
      restoreDecision({ personalStatus: 'revoked', pairStatus: pair, coupleState: 'split' }),
      'keep',
    );
  // No pair row: the single revoked it by hand.
  assert.equal(
    restoreDecision({ personalStatus: 'revoked', pairStatus: undefined, coupleState: 'split' }),
    'keep',
  );
  assert.equal(
    restoreDecision({ personalStatus: 'approved', pairStatus: 'pending', coupleState: 'active' }),
    'keep',
  );
});
