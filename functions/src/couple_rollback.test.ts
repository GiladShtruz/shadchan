import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  restorePlan,
  canRollBack,
  stepIndex,
  MERGE_STEPS,
} from './couple_workspace';

test('a tree is restored to its archive: archived records back, new ones tombstoned', () => {
  const archive = {
    people: { a: { firstName: 'דוד' }, gone: { _deleted: true } },
    personNotes: {},
    matches: {},
    matchNotes: {},
    personEvents: {},
    matchStatusEvents: {},
    settings: { userFirstName: { k: 'userFirstName', v: '"משה"' } },
  };
  const current = {
    people: {
      a: { firstName: 'דוד', _sources: ['x', 'y'] },
      b: { firstName: 'נועה', _sources: ['y'] },
      tomb: { _deleted: true },
    },
    personNotes: {},
    matches: { m: { personAId: 'a', personBId: 'b' } },
    matchNotes: {},
    personEvents: {},
    matchStatusEvents: {},
    settings: {
      userFirstName: { k: 'userFirstName', v: '"משה"' },
      'couple.reminder.m': { k: 'couple.reminder.m', v: '"{}"' },
    },
  };
  const plan = restorePlan(current, archive);
  // The archived record comes back whole — without the merge's metadata.
  assert.deepEqual(plan.people.a, { firstName: 'דוד' });
  assert.deepEqual(plan.people.gone, { _deleted: true });
  // What the merge added is taken away.
  assert.deepEqual(plan.people.b, { _deleted: true });
  assert.deepEqual(plan.matches.m, { _deleted: true });
  assert.deepEqual(plan.settings['couple.reminder.m'], { _deleted: true });
  // A tombstone that was already there is left alone.
  assert.equal(plan.people.tomb, undefined);
});

test('a merge can be undone until the card permissions are touched', () => {
  assert.equal(canRollBack(undefined), true);
  assert.equal(canRollBack('claimed'), true);
  assert.equal(canRollBack('archived'), true);
  assert.equal(canRollBack('merged'), true);
  assert.equal(canRollBack('files'), true);
  assert.equal(canRollBack('settings'), true);
  assert.equal(canRollBack('grants'), false);
  assert.equal(canRollBack('active'), false);
  assert.ok(stepIndex('files') > stepIndex('merged'));
  assert.equal(MERGE_STEPS[MERGE_STEPS.length - 1], 'active');
});
