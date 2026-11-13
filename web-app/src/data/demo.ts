import type { Gender, MaritalStatus, MatchStatus, ProfileStatus, Region, ReligiousLevel } from '@/domain/enums';
import type {
  AppNotification,
  CommunityTotals,
  CommunityWindow,
  Database,
  LeaderboardRow,
  MatchIdea,
  MatchNote,
  MatchStatusEvent,
  Person,
  PersonEvent,
  PersonNote,
  PersonalArea,
  Tip,
} from '@/domain/types';

/**
 * A made-up database for the prototype. Every name, number and line here is
 * invented; nothing comes from a real account. The shapes are exactly the
 * Firestore documents, so swapping this for the live data later touches the
 * data layer only.
 */

function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 0x100000000;
  };
}

const rand = rng(20261113);
const pick = <T,>(arr: readonly T[]): T => arr[Math.floor(rand() * arr.length)];
const chance = (p: number) => rand() < p;

const NOW = Date.now();
const DAY = 86400000;
const daysAgo = (d: number, h = 10) => new Date(NOW - d * DAY + (h - 10) * 3600000).toISOString();
const daysAhead = (d: number) => new Date(NOW + d * DAY).toISOString();

const MALE = ['יוסף', 'דוד', 'אליעזר', 'נתנאל', 'אביעד', 'משה', 'יונתן', 'עמיחי', 'אריאל', 'שמואל', 'נועם', 'איתמר', 'אלחנן', 'הראל', 'ידידיה', 'אורי', 'בנימין', 'חגי', 'יהודה', 'עידו', 'רועי', 'שלמה', 'אהרון', 'מתן'];
const FEMALE = ['שרה', 'רבקה', 'נועה', 'תמר', 'אילת', 'הדס', 'מיכל', 'אביגיל', 'שירה', 'רעות', 'הודיה', 'טליה', 'אסתר', 'יעל', 'נחמה', 'אפרת', 'מוריה', 'רחל', 'דבורה', 'שני', 'אורית', 'הילה', 'נעמה', 'בתיה'];
const LAST = ['כהן', 'לוי', 'מזרחי', 'פרץ', 'ביטון', 'אברהם', 'פרידמן', 'שפירא', 'גולדברג', 'אזולאי', 'דהן', 'רוזנברג', 'בן דוד', 'חדד', 'אוחיון', 'קליין', 'שטרן', 'ברגר', 'וייס', 'סויסה', 'טל', 'אלון', 'הלוי', 'נחום'];
const CITIES: { city: string; region: Region }[] = [
  { city: 'ירושלים', region: 'jerusalem' },
  { city: 'בית שמש', region: 'jerusalem' },
  { city: 'אפרת', region: 'jerusalem' },
  { city: 'מעלה אדומים', region: 'jerusalem' },
  { city: 'פתח תקווה', region: 'center' },
  { city: 'רחובות', region: 'center' },
  { city: 'מודיעין', region: 'center' },
  { city: 'רעננה', region: 'center' },
  { city: 'בני ברק', region: 'center' },
  { city: 'חיפה', region: 'north' },
  { city: 'צפת', region: 'north' },
  { city: 'קרית שמונה', region: 'north' },
  { city: 'באר שבע', region: 'south' },
  { city: 'אשקלון', region: 'south' },
];
const LEVELS: ReligiousLevel[] = ['datiLeumi', 'datiLeumi', 'datiLeumi', 'datiLeumiTorani', 'datiLeumiTorani', 'datiOpen', 'chardal', 'haredi', 'masorti', 'datlashi', 'hiloni'];
const TAGS = ['מהישיבה', 'חברים מהעבודה', 'מהשכונה', 'מהקהילה', 'עולה חדש', 'אוהב טיולים', 'רציני', 'מוזיקלי', 'מהצבא'];

const CARD_MALE = [
  'בחור חם, צנוע ומשקיע. למד בישיבת הסדר, שירת כקצין בשריון וכיום לומד הנדסת תוכנה. אוהב לטייל, לבשל לשבת ולנגן בגיטרה. מחפש בחורה עם יראת שמיים, שמחה ופתוחה, שרוצה לבנות בית של תורה וחסד.',
  'מחנך בבית ספר יסודי, בעל לב רחב וחוש הומור. קובע עיתים לתורה כל ערב, מתנדב במד״א. מחפש בחורה רצינית, חמה ואכפתית, שאוהבת אנשים.',
  'עובד בהייטק כמפתח, אחרי שנתיים בישיבה גבוהה. שקט, יציב ונעים הליכות. אוהב ספרים, ריצה ושיחות עמוקות. מחפש בת זוג אינטליגנטית ובעלת ערכים.',
  'אברך בכולל אחר הצהריים ורואה חשבון בבוקר. משפחה חמה ומשכילה. מחפש בחורה יראת שמיים עם רצון להמשיך ולגדול.',
];
const CARD_FEMALE = [
  'בחורה מלאת שמחת חיים, עובדת כמרפאה בעיסוק. אחרי שירות לאומי באולפנה. אוהבת טבע, אמנות ואירוח. מחפשת בחור אמיתי, בעל יראת שמיים ותכלית, שיודע לצחוק.',
  'אחות במחלקת ילדים, רגישה ונתינה. קובעת שיעור קבוע ומתנדבת בקהילה. מחפשת בחור רציני, חם ובעל מידות טובות.',
  'סטודנטית לתואר שני בחינוך, יצירתית וחכמה. אוהבת לכתוב, לשיר ולטייל בארץ. מחפשת בחור עם עומק, שאוהב ללמוד ולגדול יחד.',
  'מעצבת גרפית, מבית חם ופתוח. צנועה, אכפתית ובעלת חוש אסתטי. מחפשת בחור עם ראש גדול ולב גדול.',
];

let idCounter = 0;
const id = (prefix: string) => `${prefix}-${(++idCounter).toString(36).padStart(4, '0')}`;

function phone(): string {
  const pre = pick(['050', '052', '053', '054', '055', '058']);
  let rest = '';
  for (let i = 0; i < 7; i++) rest += Math.floor(rand() * 10);
  return `${pre}-${rest}`;
}

function makePerson(gender: Gender, i: number): Person {
  const first = gender === 'male' ? MALE[i % MALE.length] : FEMALE[i % FEMALE.length];
  const last = LAST[(i * 7 + (gender === 'male' ? 3 : 11)) % LAST.length];
  const loc = pick(CITIES);
  const age = 21 + Math.floor(rand() * 15);
  const created = Math.floor(rand() * 220) + 2;
  const status: ProfileStatus = chance(0.78) ? 'available' : chance(0.6) ? 'busy' : 'onBreak';
  const marital: MaritalStatus | null = age > 31 && chance(0.25) ? 'divorced' : chance(0.85) ? 'single' : null;
  const hasCard = chance(0.7);
  const cards = gender === 'male' ? CARD_MALE : CARD_FEMALE;
  const tags = chance(0.5) ? [pick(TAGS)] : [];
  if (chance(0.2)) tags.push(pick(TAGS));
  return {
    id: id('p'),
    firstName: first,
    lastName: last,
    gender,
    manualAge: age,
    manualAgeUpdatedAt: daysAgo(created),
    religiousLevel: pick(LEVELS),
    religiousLevelOther: null,
    city: loc.city,
    phone: chance(0.92) ? phone() : null,
    source: null,
    notes: null,
    description: hasCard ? pick(cards) : null,
    inquiryContactName: chance(0.3) ? `${pick(FEMALE)} (${pick(['אמא', 'אחות', 'חברה', 'רב הקהילה'])})` : null,
    inquiryContactPhone: null,
    heightCm: chance(0.6) ? (gender === 'male' ? 168 + Math.floor(rand() * 20) : 155 + Math.floor(rand() * 17)) : null,
    maritalStatus: marital,
    region: loc.region,
    importBatchId: null,
    dateOfBirth: null,
    cardOwnerUid: chance(0.12) ? `owner-${i}` : null,
    cardSyncDetached: false,
    preSyncSnapshot: null,
    cardRemoteStatus: null,
    tags: [...new Set(tags)],
    additionalContacts: [],
    preferredMinAge: null,
    preferredMaxAge: null,
    preferredMinHeightCm: null,
    preferredMaxHeightCm: null,
    preferredCity: null,
    preferredRegions: [],
    preferredMaritalStatuses: [],
    preferredReligiousLevels: [],
    preferredReligiousLevelOtherLabels: [],
    profileStatus: status,
    photos: [],
    isFavorite: chance(0.15),
    needsReview: false,
    hidden: false,
    avatarIndex: null,
    createdAt: daysAgo(created),
    updatedAt: daysAgo(Math.floor(rand() * Math.min(created, 40))),
  };
}

function build(): {
  db: Database;
  personal: PersonalArea;
} {
  const men = Array.from({ length: 24 }, (_, i) => makePerson('male', i));
  const women = Array.from({ length: 24 }, (_, i) => makePerson('female', i));
  const people = [...men, ...women];

  const matches: MatchIdea[] = [];
  const matchNotes: MatchNote[] = [];
  const statusEvents: MatchStatusEvent[] = [];
  const personEvents: PersonEvent[] = [];
  const personNotes: PersonNote[] = [];

  const plan: { status: MatchStatus; days: number; askedM?: number; askedF?: number; reminder?: number; reason?: string }[] = [
    { status: 'idea', days: 2 },
    { status: 'idea', days: 5, askedM: 4 },
    { status: 'checking', days: 9, askedM: 8, askedF: 6, reminder: 0 },
    { status: 'checking', days: 14, askedF: 12 },
    { status: 'idea', days: 21, reminder: -2 },
    { status: 'unavailable', days: 30, reason: 'היא בהפסקה' },
    { status: 'unavailable', days: 18, reason: 'מחכים שיחזור מחו״ל' },
    { status: 'dating', days: 11, askedM: 10, askedF: 10 },
    { status: 'dating', days: 40, askedM: 39, askedF: 38 },
    { status: 'dated', days: 70 },
    { status: 'rejected', days: 33 },
    { status: 'rejected', days: 55 },
    { status: 'married', days: 150 },
    { status: 'idea', days: 1 },
    { status: 'checking', days: 7, askedM: 6, reminder: 3 },
  ];

  plan.forEach((pl, i) => {
    const man = men[(i * 5 + 1) % men.length];
    const woman = women[(i * 7 + 2) % women.length];
    const m: MatchIdea = {
      id: id('m'),
      personAId: man.id,
      personBId: woman.id,
      status: pl.status,
      currentHandler: 'me',
      handlerName: null,
      reminderDate: pl.reminder != null ? daysAhead(pl.reminder) : pl.status === 'idea' || pl.status === 'checking' ? daysAhead(20 + i) : null,
      reminderNote: pl.reminder != null ? 'לבדוק אם חזרו אליי' : null,
      waitingReason: pl.reason ?? null,
      progress: null,
      progressOther: null,
      relatedContacts: i % 4 === 0 ? [{ name: 'הרב שלמה', phone: '050-1234567', description: 'מכיר את המשפחה' }] : [],
      lastShareLabel: pl.askedM ? `הכרטיס של ${woman.firstName} נשלח ל${man.firstName}` : null,
      lastShareAt: pl.askedM ? daysAgo(pl.askedM) : null,
      createdAt: daysAgo(pl.days),
      updatedAt: daysAgo(Math.max(0, Math.min(pl.days, (pl.askedF ?? pl.askedM ?? pl.days) - 1))),
      askedMaleAt: pl.askedM != null ? daysAgo(pl.askedM) : null,
      askedFemaleAt: pl.askedF != null ? daysAgo(pl.askedF) : null,
      checkInEveryDays: null,
      datingStartedAt: pl.status === 'dating' || pl.status === 'dated' || pl.status === 'married' ? daysAgo(Math.max(1, pl.days - 3)) : null,
      datingEndedAt: pl.status === 'dated' ? daysAgo(pl.days - 30) : null,
    };
    matches.push(m);
    if (pl.status === 'dating') {
      man.profileStatus = 'busy';
      woman.profileStatus = 'busy';
    }
    if (pl.status === 'married') {
      man.profileStatus = 'mazelTov';
      woman.profileStatus = 'mazelTov';
    }
    const note = (text: string, d: number, auto = true) =>
      matchNotes.push({ id: id('mn'), matchId: m.id, text, createdAt: daysAgo(d, 9 + (i % 8)), isAutomatic: auto, mazelTovFrom: null });
    note(`נפתח רעיון בין ${man.firstName} ל${woman.firstName}`, pl.days);
    statusEvents.push({ id: id('se'), matchId: m.id, fromStatus: null, toStatus: 'idea', createdAt: daysAgo(pl.days), automatic: false });
    if (pl.askedM != null) note(`נשלח הכרטיס של ${woman.firstName} אל ${man.firstName}`, pl.askedM);
    if (pl.askedF != null) note(`נשלח הכרטיס של ${man.firstName} אל ${woman.firstName}`, pl.askedF);
    if (i % 3 === 0) note('דיברתי עם אמא שלה, נשמע שהיא פתוחה לרעיון. לחזור אליה אחרי שבת.', Math.max(0, pl.days - 2), false);
    if (pl.status === 'dating') note('מתחילים לצאת! 🎉', pl.days - 3);
    if (pl.status === 'rejected') note(`הרעיון נסגר — ${man.firstName} לא רצה להמשיך — מחפש מישהי יותר שקטה`, pl.days - 6);
    if (pl.status === 'married') note('מזל טוב! התארסו 💍', pl.days - 60);
    if (pl.status !== 'idea') {
      statusEvents.push({ id: id('se'), matchId: m.id, fromStatus: 'idea', toStatus: pl.status, createdAt: daysAgo(Math.max(0, pl.days - 3)), automatic: false });
    }
    for (const [p, other] of [
      [man, woman],
      [woman, man],
    ] as const) {
      personEvents.push({
        id: id('pe'),
        personId: p.id,
        type: 'proposalOpened',
        text: `נפתח רעיון עם ${other.firstName} ${other.lastName}`,
        createdAt: daysAgo(pl.days),
        relatedPersonId: other.id,
        relatedMatchId: m.id,
      });
    }
  });

  people.slice(0, 18).forEach((p, i) => {
    personNotes.push({
      id: id('pn'),
      personId: p.id,
      text: pick([
        'מכירה אותו מהקהילה, בחור זהב. חשוב לו שהיא תהיה בעלת מקצוע.',
        'ביקשה לא לשלוח את הכרטיס בלי לשאול אותה קודם.',
        'אמא שלה התקשרה לשאול אם יש רעיונות חדשים.',
        'עבר דירה לירושלים לפני חודשיים.',
        'רוצה מישהו שגר בצפון או מוכן לעבור.',
      ]),
      createdAt: daysAgo(i * 3 + 1),
      isAutomatic: false,
    });
    personEvents.push({
      id: id('pe'),
      personId: p.id,
      type: 'statusChanged',
      text: `הסטטוס עודכן ל${p.profileStatus === 'available' ? (p.gender === 'female' ? 'פנויה' : 'פנוי') : 'בהפסקה'}`,
      createdAt: daysAgo(i * 4 + 2),
      relatedPersonId: null,
      relatedMatchId: null,
    });
  });

  const db: Database = {
    profile: { firstName: 'רחל', lastName: 'אברהמי', gender: 'female', isSingle: false, about: 'שדכנית מירושלים, מכירה הרבה צעירים מהקהילה ומהאולפנה.' },
    people,
    personNotes,
    matches,
    matchNotes,
    personEvents,
    matchStatusEvents: statusEvents,
  };

  const me = makePerson('female', 9);
  me.id = 'personal-card';
  me.firstName = 'אביגיל';
  me.lastName = 'שמעוני';
  me.manualAge = 27;
  me.city = 'ירושלים';
  me.region = 'jerusalem';
  me.religiousLevel = 'datiLeumi';
  me.description = CARD_FEMALE[2];
  me.profileStatus = 'available';
  me.heightCm = 165;
  me.maritalStatus = 'single';

  const personal: PersonalArea = {
    card: me,
    privateLooking: 'מחפשת בחור שקט ויציב, שאוהב ללמוד. חשוב לי שיהיה עם עבודה מסודרת ושירצה לגור בירושלים או קרוב. פחות מתאים לי מישהו שמאוד עסוק בעצמו.',
    acceptsRequests: true,
    announces: true,
    access: [
      { matchmakerUid: 'mm-1', matchmakerName: 'רחל אברהמי', matchmakerGender: 'female', status: 'approved', seesPrivateLooking: true, requestedAt: daysAgo(40), databaseCount: 312, lastActiveAt: daysAgo(0) },
      { matchmakerUid: 'mm-2', matchmakerName: 'הרב דוד פרידמן', matchmakerGender: 'male', status: 'approved', seesPrivateLooking: false, requestedAt: daysAgo(25), databaseCount: 140, lastActiveAt: daysAgo(3) },
      { matchmakerUid: 'mm-3', matchmakerName: 'מיכל שטרן', matchmakerGender: 'female', status: 'pending', seesPrivateLooking: false, requestedAt: daysAgo(1), databaseCount: 58, lastActiveAt: daysAgo(1) },
      { matchmakerUid: 'mm-4', matchmakerName: 'יעל ברגר', matchmakerGender: 'female', status: 'approved', seesPrivateLooking: false, requestedAt: daysAgo(60), databaseCount: 95, lastActiveAt: daysAgo(9) },
    ],
    helpers: [
      { uid: 'mm-5', name: 'שושנה כהן', databaseCount: 220, lastActiveAt: daysAgo(0) },
      { uid: 'mm-6', name: 'אליהו לוי', databaseCount: 41, lastActiveAt: daysAgo(6) },
      { uid: 'mm-7', name: 'תמר הלוי', databaseCount: null, lastActiveAt: daysAgo(15) },
    ],
  };

  return { db, personal };
}

const built = build();
export const demoDatabase: Database = built.db;
export const demoPersonal: PersonalArea = built.personal;

export const demoCommunity: Record<CommunityWindow, { me: number; totals: CommunityTotals }> = {
  day: { me: 4, totals: { points: 186, friends: 121, ideas: 38, couples: 3, engagements: 0, activeMatchmakers: 64, newMatchmakers: 5 } },
  week: { me: 23, totals: { points: 1342, friends: 803, ideas: 271, couples: 19, engagements: 1, activeMatchmakers: 212, newMatchmakers: 31 } },
  month: { me: 61, totals: { points: 4820, friends: 2950, ideas: 980, couples: 58, engagements: 4, activeMatchmakers: 388, newMatchmakers: 102 } },
  all: { me: 812, totals: { points: 41250, friends: 26900, ideas: 8140, couples: 402, engagements: 37, activeMatchmakers: 1210, newMatchmakers: 1210 } },
};

export const demoLeaderboard: LeaderboardRow[] = [
  { uid: 'a', name: 'שושנה כהן', points: 2140, isMe: false },
  { uid: 'b', name: 'הרב דוד פרידמן', points: 1820, isMe: false },
  { uid: 'c', name: 'מרים אזולאי', points: 1604, isMe: false },
  { uid: 'd', name: 'יעל ברגר', points: 1290, isMe: false },
  { uid: 'e', name: 'אליהו לוי', points: 1012, isMe: false },
  { uid: 'f', name: 'נחמה ויס', points: 944, isMe: false },
  { uid: 'me', name: 'רחל אברהמי', points: 812, isMe: true },
  { uid: 'g', name: 'בתיה שפירא', points: 770, isMe: false },
  { uid: 'h', name: 'עמוס דהן', points: 702, isMe: false },
  { uid: 'i', name: 'אורית חדד', points: 655, isMe: false },
];

export const demoTips: Tip[] = [
  { id: 't1', text: 'לפני ששולחים כרטיס — כדאי לשאול קודם בקצרה אם הצד השני פנוי כרגע להצעות.', authorName: null },
  { id: 't2', text: 'כשרעיון לא מתקדם, שווה לכתוב לעצמך מה הייתה הסיבה. בפעם הבאה זה יחסוך זמן.', authorName: 'שושנה כהן' },
  { id: 't3', text: 'פעם בחודש עברו על המאגר וחשבו על כל חבר — הרבה שידוכים נולדים מעצירה קטנה כזו.', authorName: null },
];

export function demoNotifications(db: Database): AppNotification[] {
  const p = db.people;
  const m = db.matches;
  return [
    { id: 'n1', kind: 'reminder', title: `לבדוק מה קורה עם ${p[2].firstName} ו${p[26].firstName}`, subtitle: 'תזכורת · רעיון', createdAt: daysAgo(0, 9), read: false, matchId: m[2].id },
    { id: 'n2', kind: 'cardCreated', title: `${p[30].firstName} ${p[30].lastName} הוסיפה כרטיס אישי. רוצה לסנכרן עם הכרטיס הקיים?`, subtitle: null, createdAt: daysAgo(0, 8), read: false, personId: p[30].id },
    { id: 'n3', kind: 'accessApproved', title: `${p[5].firstName} אישר גישה לכרטיס שלו`, subtitle: null, createdAt: daysAgo(1, 18), read: false, personId: p[5].id },
    { id: 'n4', kind: 'reminder', title: `לבדוק שוב עם ${p[12].firstName}`, subtitle: 'תזכורת · חבר', createdAt: daysAgo(2, 9), read: true, personId: p[12].id },
    { id: 'n5', kind: 'support', title: 'תשובה מצוות שדכן: תודה על הרעיון! הוספנו אותו לרשימה.', subtitle: null, createdAt: daysAgo(4, 13), read: true },
    { id: 'n6', kind: 'statusEvent', title: `${p[40].firstName} עדכנה בכרטיס שהיא בהפסקה · 2 רעיונות עברו להמתנה`, subtitle: null, createdAt: daysAgo(5, 20), read: true, personId: p[40].id },
  ];
}
