import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeDatabases, splitDatabase, normalizedPhone } from './couple_data';
import { isActiveCard } from './card_activity';
test('draft threshold and deletion', () => {
  assert.equal(
    isActiveCard({ firstName: 'דוד', description: ' '.repeat(50) }),
    false,
  );
  assert.equal(isActiveCard({ description: 'א'.repeat(29) }), false);
  assert.equal(isActiveCard({ description: 'א'.repeat(30) }), true);
  assert.equal(isActiveCard({ photoPaths: ['photo'] }), true);
  assert.equal(isActiveCard({ photoPaths: ['photo'], deleted: true }), false);
});
test('phone normalization', () => {
  assert.equal(
    normalizedPhone('050-1234567'),
    normalizedPhone('+972 50 1234567'),
  );
  assert.equal(normalizedPhone(''), null);
});
test('merge preserves both sources, text conflicts, tags, note authors and idea references', () => {
  const a = {
    people: {
      p: {
        phone: '0501234567',
        firstName: 'דוד',
        description: 'גרסה א',
        tags: ['א'],
      },
      x: { firstName: 'שרה' },
    },
    personNotes: { n: { personId: 'p', text: 'אישי א' } },
    matches: {
      m: { personAId: 'p', personBId: 'x', reminderDate: '2026-10-24' },
    },
    matchNotes: { n: { matchId: 'm', text: 'היסטוריה' } },
  };
  const b = {
    people: {
      p: {
        phone: '+972501234567',
        firstName: 'דוד',
        description: 'גרסה ב',
        tags: ['ב'],
      },
      x: { firstName: 'שרה' },
    },
    personNotes: { n: { personId: 'p', text: 'אישי ב' } },
  };
  const result = mergeDatabases([
    { uid: 'a', data: a },
    { uid: 'b', data: b },
  ]);
  assert.equal(Object.keys(result.data.people).length, 3);
  const p = result.data.people[result.ids.a.p];
  assert.deepEqual(p._sources, ['a', 'b']);
  assert.ok(
    p.description.includes('גרסה א') && p.description.includes('גרסה ב'),
  );
  assert.deepEqual(p.tags, ['א', 'ב']);
  assert.equal(Object.keys(result.data.personNotes).length, 2);
  assert.equal(result.data.matches.a__m.personAId, result.ids.a.p);
  assert.equal(result.data.matches.a__m.personBId, result.ids.a.x);
  assert.equal(result.data.matchNotes.a__n.matchId, 'a__m');
  assert.equal(result.data.matches.a__m.reminderDate, undefined);
  assert.equal(result.possibleDuplicates.length, 1);
  assert.deepEqual(a.people.p.tags, ['א']);
});
test('split keeps full cross-source ideas without copying unrelated people', () => {
  const data = {
    people: {
      a: { _sources: ['a'] },
      b: { _sources: ['b'] },
      c: { _sources: ['b'] },
      d: { _sources: ['a', 'b'] },
    },
    matches: { m: { personAId: 'a', personBId: 'b' } },
    personNotes: { n: { personId: 'b', text: 'שמור' } },
    matchNotes: { n: { matchId: 'm', text: 'היסטוריה' } },
    personEvents: {},
    matchStatusEvents: {},
    settings: {},
  };
  const left = splitDatabase(data, 'a');
  const right = splitDatabase(data, 'b');
  assert.deepEqual(Object.keys(left.people).sort(), ['a', 'b', 'd']);
  assert.deepEqual(Object.keys(right.people).sort(), ['a', 'b', 'c', 'd']);
  assert.ok(
    left.matches.m &&
      right.matches.m &&
      left.matchNotes.n &&
      right.matchNotes.n,
  );
  assert.equal(left.personNotes.n.text, 'שמור');
});
