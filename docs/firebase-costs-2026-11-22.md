# עלויות Firebase — בדיקה ותיקון (22.11.2026)

## מה ראינו

החשבון של נובמבר עד 22.11: **₪67.51** — Firestore ‏₪33.52, Gemini (Agent Platform) ‏₪20.59, Functions ‏₪12.95.
ב־22.11 נקראו **~802,000 מסמכים** (המכסה החינמית: 50,000 ביום). כתיבות: ~1,400 ביום — זניח.

מדידה ב־Cloud Shell (24 שעות, `gcloud logging read` על בקשות Cloud Run):

| פונקציה | הפעלות | זמן ריצה כולל |
|---|---|---|
| `onMatchmakerActivityWritten` | 398 | 20,883 ש' (~52 ש' כל אחת) |
| `onPersonalMemberActivity` | 325 | 5,087 ש' |
| `reconcileCoupleRecord` | 7,880 | 698 ש' |
| `onContactHashesWritten` | 16 | 591 ש' |
| `sendReminders` | 24 | 466 ש' |

גדלים: `communityMembers` 820, `personalCards` 171, `matchmakerActivity` 16, `contactHashes` 85
(אנשי קשר למשתמש: חציון 1,103, מקסימום 7,820).

## הסיבה

כל כתיבה של "פעיל לאחרונה" (`matchmakerActivity`, ~25 ביום לכל שדכן) וכל פרסום של מוני הקהילה
(`communityMembers`) הפעילו בשרת:

1. **`refreshPersonalCardCount`** — קריאה של שלושה אוספים שלמים (~1,007 מסמכים). 723 הפעלות ביום ≈ **730 אלף קריאות** — כמעט כל החשבון.
2. **`refreshContactNeighbours`** — בנייה מחדש של רשימת "השדכנים שאני מכיר" של המשתמש **ושל כל מי שהמספר שלו שמור אצלו**, כל אחת בקריאה של כל ספר הטלפונים (מסמך לכל איש קשר) ועוד ~15 קריאות לכל שדכן שנמצא, אחת אחרי השנייה (מכאן 52 שניות).

הערה: העלות גדלה בערך בריבוע של מספר המשתמשים (יותר משתמשים × יותר אנשים ששמרו כל מספר).

## מה שונה

### בשרת (`functions/src`) — דורש deploy
| שינוי | איפה |
|---|---|
| כתיבת פעילות כבר לא בונה שום רשימה: רק השורה של אותו שדכן ברשימות של מי ששמר אותו מתעדכנת במקום, ורק אם גודל המאגר השתנה או עברה שעה. הכתיבה הראשונה אי־פעם עדיין בונה פעם אחת. | `onMatchmakerActivityWritten`, `read_budget.ts` (`activityChange`, `patchHelperRows`) |
| מוני הקהילה לא מפעילים כלום, אלא אם השתנו שדות שמוצגים ברשימות (`hidden`, `photoUrl`, `joinedAt`). | `onPersonalMemberActivity` |
| `refreshPersonalCardCount` לא רץ על כל כתיבה: רק כל שעה, וכשכרטיס אישי נהיה פעיל/לא פעיל. סיכומי הקהילה בשאילתות `count()`/`sum()` (כמה קריאות במקום ~1,000), עם נפילה לקריאה מלאה אם שאילתה נדחית. לא כותב אם המספרים זהים. | `refreshPersonalCardCount`, `communityFigures`; `updatePersonalCardCount` **נמחקה** |
| `findHelpers`: רשימת אנשי הקשר שקיימים במערכת נשמרת ב־`contactMatches/{uid}` (שרת בלבד) ומחושבת מחדש רק כשספר הטלפונים הועלה מחדש (פעם ביום לכל היותר); `onPhoneDirectoryWritten` מעדכן אותה כשמספר מצטרף/עוזב. כל הקריאות במנות (`getAll`), החצי של הבעלים ב־"שמורים אחד אצל השני" נקרא פעם אחת, והרשימה נכתבת רק אם השתנתה. | `matchedHashesOf`, `findHelpers`, `getAllDocs` |
| `onPhoneDirectoryWritten` לא רץ על פרסום חוזר שבו השתנה רק `updatedAt`. | |
| תזכורות: שתי שאילתות על כל החשבונות (collection group) במקום 4 קריאות לכל בעל טוקן כל שעה; נופל לדרך הישנה עד שהאינדקסים נבנים. | `reminders.ts` (`dueAcrossAccounts`) |
| **באג:** שאילתת תזכורות החברים (`k >= 'personReminder.'` וגם `k <= 'personReminder.'`) לא החזירה כלום — תזכורות על חברים לא נשלחו ב־push בכלל, בטלפונים שהשרת אחראי בהם על התזכורות. תוקן (`'personReminder.'`). | `FRIEND_KEY_END` |
| תזכורת לתאריך בלבד (חצות) נשלחת ב־09:00, כמו שהאפליקציה מתזמנת בעצמה — לא באמצע הלילה. | `pushMomentOf` |
| `refreshAdminStats` כל 12 שעות במקום כל 3 ("רענון עכשיו" נשאר). | |
| `reconcileCoupleRecord` (רץ על **כל** כתיבה תחת `users/{uid}`) פוצל לשש פונקציות, אחת לכל אוסף רשומות. | `couple_dedup.ts` |

### באפליקציה — דורש גרסה חדשה
| שינוי | איפה |
|---|---|
| "פעיל לאחרונה" נכתב לכל היותר פעם בשעה (או 10 דקות כשגודל המאגר השתנה). | `PersonalCardService.publishActivity`, `ReadThrottle` |
| טיפים נקראים פעם ב־12 שעות, לא בכל פתיחה/חזרה/יציאה. | `TipsProvider.refreshApproved` |
| שורות שיתוף ורעיונות בין שדכנים: קריאה מלאה בחזרה לאפליקציה לכל היותר כל 5 דקות (היה 20 שניות). | `MatchmakerShares`, `MatchmakerNetwork` |
| רשימת ההתראות מאזינה ל־100 האחרונות (היה 300); "מחק הכל" מוחק גם ישנות יותר. | `InboxProvider` |
| סיכומי הקהילה: כשהסיכום מחזיר 0 — מאמינים לו (חסר אינדקס = שגיאה, לא אפס). הסריקה של עד 400 מסמכים רק אם השאילתה נכשלה. | `CommunityService._totalsForKey` |
| הסנכרון: חזרה לאפליקציה אחרי יותר מ־30 דקות פותחת את ה־listeners מחדש מהנקודה הנוכחית, כדי ש־Firestore לא יחייב על כל מה שנכתב מאז שנפתחו. | `AccountSyncEngine.resume` |
| שיתוף כרטיסים בין שדכנים: הטלפון זוכר מה פרסם (`network.held.{uid}`, מכשיר בלבד) ולא קורא את כל הכרטיסים מהשרת בכל עריכה; בדיקה מול השרת פעם ביום. | `NetworkSharing._publishOnce` |

השעונים (`ReadThrottle`, `serverReads.*`) וזיכרון הכרטיסים (`network.held`) הם הגדרות מכשיר בלבד (`AccountSyncCodec._deviceOnlyPrefixes`) ומתאפסים ביציאה מהחשבון.

## הערכה
אחרי ה־deploy (גם בלי גרסת אפליקציה חדשה — הטריגר מתעלם מכתיבות פעילות בתוך אותה שעה):
מ־~800 אלף קריאות ביום ל**עשרות אלפים** לכל היותר — קרוב למכסה החינמית, וזמן הפונקציות יורד ביותר מ־90%.
ההערכה מבוססת על הקוד והמדידה למעלה, לא על מדידה אחרי השינוי.

## Deploy
מתיקיית הפרויקט (במחשב או ב־Cloud Shell עם הענף הזה):
```bash
firebase deploy --only firestore:indexes
FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions
```
ה־CLI ישאל אם למחוק את `reconcileCoupleRecord` ואת `updatePersonalCardCount` — לענות **y**.

## איך לבדוק אחרי יום
אותה פקודה מ־Cloud Shell:
```bash
gcloud logging read "logName:\"run.googleapis.com%2Frequests\" AND timestamp>=\"$(date -u -d '-24 hours' +%Y-%m-%dT%H:%M:%SZ)\"" \
  --limit=50000 --format='value(resource.labels.service_name,httpRequest.latency)' \
| awk '{n[$1]++; gsub("s","",$2); t[$1]+=$2} END {for (s in n) printf "%-38s %6d calls %8.0f sec\n", s, n[s], t[s]}' | sort -k2 -nr
```
ובקונסול Firebase ← Usage and billing ← Cloud Firestore ← Reads.

## מה עוד אפשר (לא נעשה)
- כל כתיבה תחת `users/{uid}` בודקת בכללים `exists(memberships/uid)` — קריאה נוספת לכל בקשה. אפשר להחליף ב־custom claim.
- `CardAccessProvider` מאזין לכל כרטיס אישי מאושר בנפרד — קריאה לכל כרטיס בכל הפעלה. סביר כרגע.
- Gemini: משלמים לפי שימוש בייבוא AI (יש תקרות בקוד, `AiConfig`). כדאי להגדיר מכסה למשתמש ב־Firebase AI Logic בקונסול, והתראת תקציב ב־Google Cloud Billing.
