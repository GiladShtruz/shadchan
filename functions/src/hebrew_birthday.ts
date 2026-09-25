import { HDate, HebrewCalendar } from '@hebcal/core';

/**
 * Whether `today` (a civil date in Israel) is the Hebrew birthday of somebody
 * born on `dateOfBirth` (`YYYY-MM-DD`).
 *
 * The rule is the one Jewish practice uses, and it is the reason this lives
 * on the server in one place rather than on every phone: somebody born in
 * Adar of an ordinary year celebrates in Adar II of a leap year; somebody born
 * in Adar I or Adar II keeps their own month in a leap year and falls to Adar
 * in an ordinary one; 30 Cheshvan and 30 Kislev fall back when the month has
 * only 29 days. `HebrewCalendar.getBirthdayOrAnniversary` implements exactly
 * that.
 *
 * A civil date carries no time of day, so a birth after nightfall — which is
 * already the next Hebrew day — cannot be told apart. The card has a date, not
 * a time, and the civil date's own Hebrew day is used.
 */
export function isHebrewBirthday(dateOfBirth: string, today: Date): boolean {
  const born = parseCivilDate(dateOfBirth);
  if (born === null) {
    return false;
  }
  const todayHd = new HDate(today);
  const birthday = HebrewCalendar.getBirthdayOrAnniversary(
    todayHd.getFullYear(),
    born,
  );
  if (birthday === undefined) {
    return false;
  }
  return (
    birthday.getFullYear() === todayHd.getFullYear() &&
    birthday.getMonth() === todayHd.getMonth() &&
    birthday.getDate() === todayHd.getDate()
  );
}

/** `YYYY-MM-DD` as a local midnight, or null when it is not a real date. */
export function parseCivilDate(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (match === null) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(year, month - 1, day);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null;
  }
  return date;
}

/** Today's civil date in Israel, as a local midnight. */
export function israelToday(now: Date = new Date()): Date {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Jerusalem',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  return parseCivilDate(parts) ?? now;
}
