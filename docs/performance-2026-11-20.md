# בדיקת ביצועים — 2026-11-20

נבדק בקוד (פרופיילינג סטטי) — **לא** הורץ על מכשיר. אין כאן מכשיר Xiaomi;
רשימת הבדיקות במכשיר נמצאת ב־`docs/qa-device-checklist.md` ("ביצועים — Xiaomi").

## מה תוקן

| ממצא | השפעה | תיקון |
|---|---|---|
| `PersonRepository.getAll()` מיין את כל המאגר בכל קריאה, ובכל השוואה הקטין שתי מחרוזות (`toLowerCase`). מסך הבית קורא לה ~20 פעמים בכל בנייה. | עשרות אלפי מחרוזות זמניות בכל פריים → GC באמצע גלילה. בולט במיוחד במכשירים שמגבילים CPU (Xiaomi). | הרשימה הממוינת נשמרת בין קריאות; נזרקת בכל `notifyListeners`, בכל אירוע של ה־box ובשינוי אורך. מפתחות המיון מחושבים פעם אחת. טסט: `person_list_cache_test`. |
| אין touch resampling. | במכשירים שדוגמים מגע ב־240–480Hz (רוב Xiaomi) אירועי המגע לא מסונכרנים עם המסך → גלילה "רועדת"/קופצת. | `GestureBinding.instance.resamplingEnabled = true` ב־`main.dart`. |
| האפליקציה רצה ב־60Hz על מסכי 90/120Hz של Xiaomi. | MIUI/HyperOS לא מעלים קצב רענון לאפליקציה שלא מבקשת. | `MainActivity.preferHighestRefreshRate()` ב־`onCreate`/`onResume`. **לא קומפל כאן** (אין Android SDK). |
| הרעיונות שלי: `SliverList.list` עם כל הכרטיסים. | כל הכרטיסים נוצרו בכל בנייה. | `SliverList.builder` לרשימה הראשית ולסגורים. |
| תמונות שנפענחו בגודל מלא ל־avatar קטן (רשת, פרופיל). | זיכרון ו־decode כבדים. | `ResizeImage` בגודל המצויר. |
| תמונות כרטיסים משותפים: `FutureBuilder` חדש בכל בנייה הציג avatar ברירת מחדל לפריים אחד. | הבהוב בכל גלילה. | `MatchmakerNetwork.photoNow` כ־`initialData`. |
| "החברים שלך בשדכן" עבר על כל האירועים בכל בנייה. | O(אירועים) בכל rebuild של הבית. | memo לפי `PersonRepository.revision`. |
| "חברים שמנהלים כרטיס אישי" — רשימה אחת ארוכה. | כל השורות נבנו מיד. | שלוש לשוניות עם `ListView.builder`; ספירת התאמות לכרטיס נשמרת לפי revision. |

## עומס מבני — להחלטה

1. **טאבים שלא על המסך עדיין נבנים מחדש.** `_SwipeableBranches` שומר את כל ענפי ה־shell כ־`Offstage`. ווידג'טים בהם שמאזינים ל־`PersonRepository`/`MatchRepository` נבנים מחדש בכל שינוי, גם כשהם לא גלויים (למשל: ייבוא אנשי קשר במאגר שלי בונה גם את הבית). ההמלצה: חישובים על כל המאגר (לוח הפעולות, הצעות זוגות, נתונים) יעברו ל־view models עם memo לפי `revision`, או שענף לא פעיל יקבל `TickerMode`+cache של הווידג'ט האחרון.
2. **Listener לכל כרטיס מאושר.** `CardAccessProvider._followCard` פותח `snapshots()` לכל רווק שאישר גישה. שדכן עם 200 אישורים = 200 listeners פתוחים. עדיף שאילתה אחת (`personalCards` where `grantees` array-contains) — דורש שינוי מבנה נתונים וכללים.
3. **פרסום מלא לרשת.** `NetworkSharing.publish` קורא את כל `sharedCards/{uid}/cards` מהשרת בכל הרצה (כל 20 שניות אחרי פעילות). `PartnerSpace.publish` מדלג כשאין שינוי מקומי; כדאי להוסיף אותו מנגנון ל־`NetworkSharing`.
4. **הבית מחשב הכול בכל בנייה.** `HomeBoardSection._collect`, `FriendsWithCards.build` ו־`ActivityStats.allTime` רצים בכל rebuild. חלקם עם memo; האחרים כדאי להעביר ל־memo לפי revision.

## מדידה במכשיר (נדרש)

`flutter run --profile` על Xiaomi + DevTools → Performance: לבדוק build/raster לפריים בגלילת הבית, המאגר שלי והרעיונות שלי, לפני ואחרי. רשימה מלאה ב־QA.
