import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import {
  ACTIVITY_PATCH_EVERY_MS,
  activityChange,
  helperListChanged,
  memberListFieldsChanged,
  patchHelperRows,
  sameFigures,
  stableJson,
} from './read_budget';

const at = (ms: number) => Timestamp.fromMillis(ms);
const T0 = Date.UTC(2026, 10, 22, 10);

test('the first activity write builds the lists once; a deletion does nothing', () => {
  assert.equal(activityChange(undefined, { databaseCount: 3, lastActiveAt: at(T0) }), 'rebuild');
  assert.equal(activityChange({ databaseCount: 3, lastActiveAt: at(T0) }, undefined), 'none');
});

test('activity within the hour, same database size: nothing is read or written', () => {
  const before = { databaseCount: 40, lastActiveAt: at(T0) };
  assert.equal(activityChange(before, { databaseCount: 40, lastActiveAt: at(T0 + 59 * 60 * 1000) }), 'none');
});

test('an hour later, or a different database size, patches the rows', () => {
  const before = { databaseCount: 40, lastActiveAt: at(T0) };
  assert.equal(
    activityChange(before, { databaseCount: 40, lastActiveAt: at(T0 + ACTIVITY_PATCH_EVERY_MS) }),
    'patch',
  );
  assert.equal(activityChange(before, { databaseCount: 41, lastActiveAt: at(T0 + 60_000) }), 'patch');
  assert.equal(activityChange({ databaseCount: 40 }, { databaseCount: 40, lastActiveAt: at(T0) }), 'patch');
});

test('community counters alone never rebuild anybody\'s list', () => {
  const before = { hidden: false, photoUrl: 'u', joinedAt: at(T0), weekActions: 3, allActions: 10 };
  const after = { ...before, weekActions: 4, allActions: 11, updatedAt: at(T0 + 1) };
  assert.equal(memberListFieldsChanged(before, after), false);
  assert.equal(memberListFieldsChanged(before, { ...after, hidden: true }), true);
  assert.equal(memberListFieldsChanged(before, { ...after, photoUrl: 'v' }), true);
  assert.equal(memberListFieldsChanged(before, { ...after, joinedAt: at(T0 + 5) }), true);
  assert.equal(memberListFieldsChanged(undefined, after), true);
  assert.equal(memberListFieldsChanged(before, undefined), true);
});

test('a helper row is patched in place, and only when its figures moved', () => {
  const rows = [
    { uid: 'a', name: 'A', databaseCount: 10, lastActiveAt: at(T0) },
    { uid: 'b', name: 'B', databaseCount: 5, lastActiveAt: at(T0) },
  ];
  const next = patchHelperRows(rows, 'b', { databaseCount: 6, lastActiveAt: at(T0 + 1000) });
  assert.ok(next);
  assert.equal(next![0], rows[0]);
  assert.equal(next![1].databaseCount, 6);
  assert.equal(next![1].name, 'B');
  assert.equal(patchHelperRows(rows, 'b', { databaseCount: 5, lastActiveAt: at(T0) }), null);
  assert.equal(patchHelperRows(rows, 'nobody', { databaseCount: 1, lastActiveAt: null }), null);
  assert.equal(patchHelperRows(undefined, 'b', { databaseCount: 1, lastActiveAt: null }), null);
});

test('a rebuilt list equal to the stored one is not written again', () => {
  const list = {
    helpers: [{ uid: 'a', joinedAt: at(T0), mutual: true }],
    friends: [],
    uids: ['a'],
  };
  const stored = {
    helpers: [{ mutual: true, joinedAt: at(T0), uid: 'a' }],
    friends: [],
    uids: ['a'],
    updatedAt: at(T0 - 5),
  };
  assert.equal(helperListChanged(stored, list), false);
  assert.equal(helperListChanged(undefined, list), true);
  assert.equal(helperListChanged(stored, { ...list, uids: ['a', 'b'] }), true);
});

test('the same personal-area figures are not rewritten', () => {
  const stored = { singles: 3, weekKey: 'W1', startedAt: 1, updatedAt: at(5) };
  assert.equal(sameFigures(stored, { singles: 3, weekKey: 'W1' }), true);
  assert.equal(sameFigures(stored, { singles: 4, weekKey: 'W1' }), false);
  assert.equal(sameFigures(undefined, { singles: 3 }), false);
});

test('stable JSON ignores key order and reads timestamps as instants', () => {
  assert.equal(stableJson({ b: 1, a: at(7) }), stableJson({ a: at(7), b: 1 }));
  assert.notEqual(stableJson({ a: at(7) }), stableJson({ a: at(8) }));
});
