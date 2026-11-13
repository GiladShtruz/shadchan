import {
  MATCH_STATE_LABEL,
  RELIGIOUS_LABEL,
  type Gender,
  type MatchStatus,
  type ProposalTab,
  type ReligiousLevel,
} from './enums';
import type { MatchIdea, Person } from './types';

/**
 * Domain rules ported from the Flutter app. Each function names the Dart code
 * it mirrors; if that code changes, change this too. (Long term these belong
 * in Cloud Functions so the two clients cannot disagree — see
 * docs/web-client.md.)
 */

const DAY = 24 * 60 * 60 * 1000;

export function fullName(p: Pick<Person, 'firstName' | 'lastName'>): string {
  return [p.firstName, p.lastName].filter(Boolean).join(' ').trim();
}

/** `Person.age`: birth date if known, else the manual age advanced yearly. */
export function ageOf(p: Person, now = new Date()): number | null {
  if (p.dateOfBirth) {
    const b = new Date(p.dateOfBirth);
    let y = now.getFullYear() - b.getFullYear();
    if (now.getMonth() < b.getMonth() || (now.getMonth() === b.getMonth() && now.getDate() < b.getDate())) y -= 1;
    return y;
  }
  if (p.manualAge == null) return null;
  if (!p.manualAgeUpdatedAt) return p.manualAge;
  const elapsed = now.getTime() - new Date(p.manualAgeUpdatedAt).getTime();
  return p.manualAge + Math.max(0, Math.floor(elapsed / (365 * DAY)));
}

export function religiousLabel(p: Person): string | null {
  if (!p.religiousLevel) return null;
  if (p.religiousLevel === 'other') return (p.religiousLevelOther ?? '').trim() || RELIGIOUS_LABEL.other;
  return RELIGIOUS_LABEL[p.religiousLevel];
}

/** One short line: "26 · דתי לאומי · ירושלים". */
export function summaryLine(p: Person): string {
  const age = ageOf(p);
  return [age != null ? String(age) : null, religiousLabel(p), p.city].filter(Boolean).join(' · ');
}

export function pausesMatches(p: Person): boolean {
  return p.profileStatus === 'busy' || p.profileStatus === 'onBreak';
}

/** `matchProposalTabFor` in enums.dart. `null` = hidden. */
export function proposalTab(m: MatchIdea, a: Person | undefined, b: Person | undefined): ProposalTab | null {
  const archived = a?.profileStatus === 'mazelTov' || b?.profileStatus === 'mazelTov';
  const paused = (a && pausesMatches(a)) || (b && pausesMatches(b));
  switch (m.status) {
    case 'married':
      return 'weddings';
    case 'dated':
      return 'dated';
    case 'rejected':
      return 'rejected';
    case 'dating':
      return archived ? null : 'dating';
    default:
      if (archived) return null;
      if (m.status === 'unavailable' || paused) return 'waiting';
      return 'open';
  }
}

/** The idea category buttons on "הרעיונות שלי". */
export type IdeaCategory = 'all' | 'open' | 'waiting' | 'dating' | 'closed';

export const IDEA_CATEGORY_LABEL: Record<IdeaCategory, string> = {
  all: 'הכל',
  open: 'פתוחים',
  waiting: 'בהמתנה',
  dating: 'יוצאים',
  closed: 'נסגרו',
};

export function ideaCategory(tab: ProposalTab): Exclude<IdeaCategory, 'all'> {
  switch (tab) {
    case 'open':
      return 'open';
    case 'waiting':
      return 'waiting';
    case 'dating':
      return 'dating';
    default:
      return 'closed';
  }
}

/** `MatchStage` — derived from the two "asked" dates and the status. */
export function stageLabel(m: MatchIdea, male: Person | undefined, female: Person | undefined): string {
  if (m.status === 'dating') return 'מתחילים לצאת';
  const askedM = !!m.askedMaleAt;
  const askedF = !!m.askedFemaleAt;
  if (askedM && askedF) return 'בבדיקה';
  if (askedM) return 'מחכים לתשובת הבחור';
  if (askedF) return 'מחכים לתשובת הבחורה';
  return `יאללה לקדם — לשאול את ${male?.firstName ?? 'הבחור'}`;
}

/** The colour for a match state — `AppColors.matchState`. */
export function matchStateColor(status: MatchStatus, paused = false): string {
  if (status === 'married') return 'var(--c-dating)';
  if (status === 'dating') return 'var(--c-female)';
  if (status === 'unavailable' || paused) return 'var(--c-copper)';
  if (status === 'rejected' || status === 'dated') return 'var(--c-muted)';
  return 'var(--c-male)';
}

export function matchStateWord(m: MatchIdea, paused: boolean): string {
  if ((m.status === 'idea' || m.status === 'checking') && paused) return 'בהמתנה';
  return MATCH_STATE_LABEL[m.status];
}

export function sidesOf(m: MatchIdea, byId: Map<string, Person>): { male?: Person; female?: Person } {
  const a = byId.get(m.personAId);
  const b = byId.get(m.personBId);
  if (a?.gender === 'female' || b?.gender === 'male') return { male: b, female: a };
  return { male: a, female: b };
}

// ---- Automatic suggestions (`MatchSuggestionUtils.matchesBasicPreferences`) ----

const AGE_BANDS = [
  { upTo: 30, younger: 5, older: 1 },
  { upTo: 40, younger: 7, older: 2 },
  { upTo: Infinity, younger: 12, older: 5 },
];

export const DEFAULT_STYLES: Partial<Record<ReligiousLevel, ReligiousLevel[]>> = {
  hiloni: ['hiloni', 'masorti', 'datlashi'],
  masorti: ['masorti', 'hiloni', 'datlashi'],
  datlashi: ['datlashi', 'hiloni', 'masorti'],
  datiOpen: ['datiOpen', 'datiLeumi'],
  datiLeumi: ['datiLeumi', 'datiOpen', 'datiLeumiTorani'],
  datiLeumiTorani: ['datiLeumiTorani', 'datiLeumi', 'chardal'],
  chardal: ['chardal'],
  haredi: ['haredi'],
};

function femaleRangeForMale(maleAge: number) {
  const band = AGE_BANDS.find((b) => maleAge <= b.upTo)!;
  return { min: maleAge - band.younger, max: maleAge + band.older };
}

function stylesFor(p: Person): ReligiousLevel[] | null {
  if (!p.religiousLevel) return null;
  return DEFAULT_STYLES[p.religiousLevel] ?? [p.religiousLevel];
}

export function oppositeGender(g: Gender): Gender | null {
  return g === 'male' ? 'female' : g === 'female' ? 'male' : null;
}

/** Whether [candidate] passes [source]'s basic filter: side, age, style. */
export function matchesBasic(source: Person, candidate: Person): boolean {
  if (candidate.id === source.id || candidate.hidden) return false;
  if (oppositeGender(source.gender) !== candidate.gender) return false;
  const sAge = ageOf(source);
  const cAge = ageOf(candidate);
  if (sAge != null && cAge != null) {
    const male = source.gender === 'male' ? sAge : cAge;
    const female = source.gender === 'male' ? cAge : sAge;
    const range = femaleRangeForMale(male);
    if (female < range.min || female > range.max) return false;
  }
  const styles = source.preferredReligiousLevels.length ? source.preferredReligiousLevels : stylesFor(source);
  if (styles && candidate.religiousLevel && !styles.includes(candidate.religiousLevel)) return false;
  return true;
}

export function suggestionsFor(source: Person, people: Person[], matches: MatchIdea[]): Person[] {
  const paired = new Set<string>();
  for (const m of matches) {
    if (m.personAId === source.id) paired.add(m.personBId);
    if (m.personBId === source.id) paired.add(m.personAId);
  }
  return people
    .filter((c) => c.profileStatus !== 'mazelTov' && !paired.has(c.id) && matchesBasic(source, c))
    .sort((x, y) => {
      const px = pausesMatches(x) ? 1 : 0;
      const py = pausesMatches(y) ? 1 : 0;
      if (px !== py) return px - py;
      return y.updatedAt.localeCompare(x.updatedAt);
    });
}

// ---- Dates ----

export function daysBetween(a: Date, b: Date): number {
  return Math.round((b.getTime() - a.getTime()) / DAY);
}

const HE_MONTHS = ['ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני', 'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'];

export function shortDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()}.${d.getMonth() + 1}`;
}

export function longDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()} ב${HE_MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** WhatsApp-style time: today → HH:MM, yesterday → אתמול, else d.m. */
export function chatTime(iso: string, now = new Date()): string {
  const d = new Date(iso);
  const sameDay = d.toDateString() === now.toDateString();
  if (sameDay) return d.toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' });
  const y = new Date(now.getTime() - DAY);
  if (d.toDateString() === y.toDateString()) return 'אתמול';
  return shortDate(iso);
}

export function relativeDays(iso: string, now = new Date()): string {
  const days = daysBetween(now, new Date(iso));
  if (days === 0) return 'היום';
  if (days === 1) return 'מחר';
  if (days === -1) return 'אתמול';
  if (days > 1) return `בעוד ${days} ימים`;
  return `לפני ${-days} ימים`;
}

export function spanLabel(fromIso: string, to = new Date()): string {
  const days = Math.max(0, daysBetween(new Date(fromIso), to));
  if (days < 1) return 'מהיום';
  if (days === 1) return 'יום';
  if (days === 2) return 'יומיים';
  if (days < 7) return `${days} ימים`;
  if (days < 14) return 'שבוע';
  if (days < 30) return `${Math.floor(days / 7)} שבועות`;
  if (days < 60) return 'חודש';
  return `${Math.floor(days / 30)} חודשים`;
}

/** `'{זכר|נקבה}'` templates, as `GenderText` resolves them in Dart. */
export function g(template: string, gender: Gender | null | undefined): string {
  return template.replace(/\{([^|{}]*)\|([^|{}]*)\}/g, (_, m: string, f: string) => (gender === 'female' ? f : m));
}

export function phoneToWhatsApp(phone: string | null): string | null {
  if (!phone) return null;
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('972')) return digits;
  if (digits.startsWith('0') && digits.length >= 9) return `972${digits.slice(1)}`;
  return digits.length >= 9 ? digits : null;
}
