import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeDatabases, splitDatabase, normalizedPhone } from './couple_data';
import { isActiveCard } from './card_activity';
test('draft threshold and deletion', () => {
  const words = (n: number) => Array.from({ length: n }, () => 'מילה').join(' ');
  assert.equal(
    isActiveCard({ firstName: 'דוד', description: ' '.repeat(50) }),
    false,
  );
  // A photo alone, or text alone, is still a draft.
  assert.equal(isActiveCard({ photoPaths: ['photo'] }), false);
  assert.equal(isActiveCard({ description: words(40) }), false);
  assert.equal(isActiveCard({ photoPaths: ['photo'], description: words(19) }), false);
  assert.equal(isActiveCard({ photoPaths: ['photo'], description: words(20) }), true);
  // Runs of spaces and new lines are one gap, not many words.
  assert.equal(
    isActiveCard({ photoPaths: ['p'], description: `  ${words(10)}\n\n   ${words(9)}  ` }),
    false,
  );
  assert.equal(isActiveCard({ photoPaths: [], description: words(30) }), false);
  assert.equal(
    isActiveCard({ photoPaths: ['photo'], description: words(20), deleted: true }),
    false,
  );
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
  // The inviting side keeps its ids; the joining side only where they collide.
  assert.equal(result.ids.a.p, 'p');
  assert.equal(result.ids.b.p, 'p');
  assert.equal(result.ids.b.x, 'b__x');
  assert.equal(result.data.matches.m.personAId, result.ids.a.p);
  assert.equal(result.data.matches.m.personBId, result.ids.a.x);
  assert.equal(result.data.matchNotes.n.matchId, 'm');
  assert.equal(result.data.matches.m.reminderDate, undefined);
  assert.ok(result.data.personNotes.n && result.data.personNotes.b__n);
  assert.equal(result.data.personNotes.b__n.personId, 'p');
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

test('a database joining an empty one becomes the shared database unchanged', () => {
  const joining = {
    people: { p1: { firstName: 'דוד', phone: '0501111111' }, p2: { firstName: 'שרה' } },
    matches: { m1: { personAId: 'p1', personBId: 'p2' } },
    matchNotes: { j1: { matchId: 'm1', text: 'שורה' } },
    personNotes: { n1: { personId: 'p1', text: 'הערה' } },
    settings: {
      [encodeURIComponent('home.board')]: {
        k: 'home.board',
        v: JSON.stringify(JSON.stringify([{ kind: 'person', id: 'p1' }])),
      },
    },
  };
  const result = mergeDatabases([
    { uid: 'inviter', data: {} },
    { uid: 'joiner', data: joining },
  ]);
  assert.deepEqual(Object.keys(result.data.people).sort(), ['p1', 'p2']);
  assert.deepEqual(Object.keys(result.data.matches), ['m1']);
  assert.equal(result.data.matchNotes.j1.matchId, 'm1');
  assert.equal(result.data.personNotes.n1.personId, 'p1');
  assert.deepEqual(result.data.people.p1._sources, ['joiner']);
  // A board pin still points at the same friend.
  const board = Object.values(result.data.settings)[0];
  assert.ok(String(board.v).includes('p1'));
});

test('the same friend added on both sides is one record from both, nothing lost', () => {
  const result = mergeDatabases([
    { uid: 'a', data: { people: { x: { firstName: 'נועה', phone: '052-7654321', city: 'חיפה' } } } },
    { uid: 'b', data: { people: { y: { firstName: 'נועה', phone: '+972527654321', city: 'ירושלים', heightCm: 165 } } } },
  ]);
  assert.deepEqual(Object.keys(result.data.people), ['x']);
  const p = result.data.people.x;
  assert.deepEqual(p._sources, ['a', 'b']);
  assert.equal(p.city, 'חיפה');
  assert.equal(p.heightCm, 165);
  assert.deepEqual(p._mergeConflicts.city, ['חיפה', 'ירושלים']);
  assert.equal(result.ids.b.y, 'x');
});

test('a fixed id on both sides (the own card) is kept apart, never merged', () => {
  const result = mergeDatabases([
    { uid: 'a', data: { people: { 'own-personal-card': { firstName: 'משה' } } } },
    { uid: 'b', data: { people: { 'own-personal-card': { firstName: 'רחל' } } } },
  ]);
  assert.equal(result.data.people['own-personal-card'].firstName, 'משה');
  assert.equal(result.data.people['b__own-personal-card'].firstName, 'רחל');
  assert.equal(result.ids.b['own-personal-card'], 'b__own-personal-card');
});
