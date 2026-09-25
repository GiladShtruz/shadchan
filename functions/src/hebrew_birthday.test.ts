import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HDate } from '@hebcal/core';
import { isHebrewBirthday, parseCivilDate, israelToday } from './hebrew_birthday';

function civil(hd: HDate): Date {
  return hd.greg();
}

test('a birthday falls on the same Hebrew date each year', () => {
  // 14 Tishrei 5760 → 14 Tishrei 5787.
  const born = civil(new HDate(14, 'Tishrei', 5760));
  const iso = `${born.getFullYear()}-${String(born.getMonth() + 1).padStart(2, '0')}-${String(born.getDate()).padStart(2, '0')}`;
  assert.equal(isHebrewBirthday(iso, civil(new HDate(14, 'Tishrei', 5787))), true);
  assert.equal(isHebrewBirthday(iso, civil(new HDate(15, 'Tishrei', 5787))), false);
});

test('Adar of an ordinary year is celebrated in Adar II of a leap year', () => {
  // 5761 is ordinary, 5763 is a leap year.
  const born = civil(new HDate(10, 'Adar', 5761));
  const iso = `${born.getFullYear()}-${String(born.getMonth() + 1).padStart(2, '0')}-${String(born.getDate()).padStart(2, '0')}`;
  assert.equal(isHebrewBirthday(iso, civil(new HDate(10, 'Adar II', 5763))), true);
  assert.equal(isHebrewBirthday(iso, civil(new HDate(10, 'Adar I', 5763))), false);
});

test('Adar I of a leap year falls to Adar in an ordinary year', () => {
  const born = civil(new HDate(5, 'Adar I', 5760));
  const iso = `${born.getFullYear()}-${String(born.getMonth() + 1).padStart(2, '0')}-${String(born.getDate()).padStart(2, '0')}`;
  assert.equal(isHebrewBirthday(iso, civil(new HDate(5, 'Adar', 5761))), true);
});

test('a malformed date is never anybody’s birthday', () => {
  assert.equal(parseCivilDate('2000-02-30'), null);
  assert.equal(parseCivilDate('nonsense'), null);
  assert.equal(isHebrewBirthday('nonsense', new Date()), false);
});

test('today is taken in Israel, not in the server’s zone', () => {
  // 22:30 UTC on 1 March is already 2 March in Israel.
  const today = israelToday(new Date(Date.UTC(2026, 2, 1, 22, 30)));
  assert.equal(today.getDate(), 2);
});
