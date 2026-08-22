/// The privacy policy, in the two languages the app ships it in.
///
/// One file rather than a string per screen, because the policy is shown in
/// three places now — the settings link, the overflow menu's dialog, and the
/// full screen behind both — and a policy that says different things in
/// different corners of the same app is worse than no policy at all.
///
/// Kept in step with `PRIVACY_POLICY.md` and `PRIVACY_POLICY_EN.md` at the root
/// of the repository, which are what gets published to the store listings. When
/// one changes, change the other: the store copy is the one a regulator reads,
/// and this one is the one a user reads.
abstract final class PrivacyPolicyText {
  /// Where a privacy question goes. Deliberately the same address in both
  /// languages and in both markdown files.
  static const String contactEmail = 'giladsh22@gmail.com';

  static const String hebrewTitle = 'מדיניות פרטיות';
  static const String englishTitle = 'Privacy Policy';

  /// Label of the button that swaps the dialog to the other language. Reads in
  /// the language it switches *to*, which is the only way it makes sense to
  /// somebody who cannot read the one currently on screen.
  static const String toEnglishLabel = 'למדיניות פרטיות באנגלית';
  static const String toHebrewLabel = 'Read this policy in Hebrew';

  static const String hebrew = '''
עודכן לאחרונה: 21 באוגוסט 2026

אפליקציית "שדכן" נועדה לסייע בניהול אנשי קשר, הצעות, הערות ותזכורות הקשורות לתהליך השידוכים. מדיניות פרטיות זו מסבירה איזה מידע האפליקציה מעבדת, כיצד נעשה בו שימוש, ואילו אפשרויות שליטה עומדות לרשותכם.

בקצרה: האפליקציה עובדת מקומית על המכשיר, גם בלי חשבון וגם בלי אינטרנט. אין בה פרסומות, אין בה כלי אנליטיקה ואין בה מעקב. איננו מוכרים מידע אישי. מידע יוצא מהמכשיר רק אם התחברתם והפעלתם גיבוי, אם הפעלתם ייבוא בעזרת בינה מלאכותית, אם שלחתם פנייה, אם אזור הקהילה פעיל אצלכם, או אם בחרתם בעצמכם לשתף, לייצא או לפרסם משהו.

1. איזה מידע האפליקציה מעבדת

האפליקציה עשויה לעבד מידע שאתם מזינים באופן ידני, לרבות שם פרטי, שם משפחה, מגדר, גיל, רמה דתית, עיר, מספר טלפון, איש קשר לבירורים, מקור היכרות, הערות פרטיות, תמונות, סימון מועדפים, מידע על הצעות והערות הקשורות להצעות.

אם תבחרו להשתמש בייבוא מאנשי קשר, האפליקציה תבקש גישה לקריאת אנשי הקשר במכשיר כדי להציג שמות ומספרי טלפון כמועמדים לייבוא. כדי לזרז כניסות חוזרות למסך הייבוא, רשימת מועמדי הייבוא עשויה להישמר בקאש מקומי במכשיר. אנשי קשר שלא תבחרו לייבא אינם מתווספים לרשומות האנשים של האפליקציה.

בתצוגת סריקת הכרטיסים באנדרואיד, האפליקציה עשויה לבקש גישה ליומן השיחות כדי למיין את אנשי הקשר המוצעים לפי שיחות אחרונות. יומן השיחות משמש למיון מקומי בלבד, אינו נשלח לשום מקום, ואינו נשמר כרשומת אדם אלא אם בחרתם לייבא איש קשר.

אם תבחרו להוסיף תמונות, האפליקציה תיגש לגלריה או לבוחר המדיה של המכשיר לצורך בחירת תמונה אחת או כמה תמונות ושמירתן ברשומת האדם. כדי למרכז תמונה על הפנים במקום לחתוך אותן, האפליקציה מריצה זיהוי פנים של Google ML Kit — כולו על גבי המכשיר. שום תמונה ושום נתון הנגזר ממנה אינם נשלחים לצורך זה לשום מקום.

אם תבחרו לשתף אל האפליקציה טקסט או תמונה מאפליקציה אחרת, למשל וואטסאפ, התוכן המשותף יועתק זמנית למכשיר ויוצג לכם כדי לבחור אם להוסיף אותו לאיש קשר קיים או ליצור איש קשר חדש. התוכן נשמר ברשומת אדם רק לאחר פעולה יזומה שלכם.

אם תבחרו לייצא או לייבא גיבוי, האפליקציה תיצור או תקרא קובץ JSON שיכול לכלול את כל המידע השמור באפליקציה, כולל אנשים, הצעות, הערות ותמונות מקומיות. האפליקציה אינה שומרת תאריכי לידה. גרסאות ישנות שלה שמרו, ולכן קובץ גיבוי שנוצר באחת מהן עשוי להכיל תאריך לידה — במקרה כזה האפליקציה קוראת אותו בעת הייבוא, ממירה אותו לגיל, ואינה שומרת את התאריך עצמו.

אם תבחרו לאפשר התראות, האפליקציה תציג תזכורות מקומיות שהגדרתם בעצמכם על הצעות ועל אנשים, וכן הזמנה לחזור לאפליקציה אם לא נכנסתם אליה שבוע. התזכורות נקבעות על המכשיר, ותוכנן אינו נשלח לשרת.

2. כיצד אנו משתמשים במידע

המידע משמש להפעלת תכונות האפליקציה בלבד, כולל ניהול רשומות אנשים, יצירת הצעות, הוספת הערות, חיפוש וסינון, ייבוא מאנשי קשר, מיון מועמדים לפי שיחות אחרונות באנדרואיד, הצגת תמונות, שיתוף יזום על ידי המשתמש, ייבוא בעזרת בינה מלאכותית כאשר אתם מפעילים אותו, גיבוי ושחזור, ותזכורות מקומיות שהגדרתם.

איננו משתמשים במידע לפרסום, לפרופיילינג, להחלטות אוטומטיות בעלות משמעות משפטית או לשיווק. איננו שולחים אליכם דיוור שיווקי.

3. היכן המידע נשמר

נכון ל-21 באוגוסט 2026, המידע נשמר מקומית על גבי המכשיר שבו האפליקציה מותקנת. המידע נשמר במסד נתונים מקומי של האפליקציה ובקבצים מקומיים עבור תמונות וגיבויים זמניים. האפליקציה עובדת במלואה גם ללא חיבור לאינטרנט וללא חשבון.

האפליקציה אינה דורשת יצירת חשבון: היא מציעה להתחבר פעם אחת, וניתן להמשיך בלעדיה ולעבוד מקומית בלבד. אם תבחרו להתחבר עם חשבון Google או Apple, ורק אז, יופעל גיבוי בענן: עותק של המאגר שלכם — אנשים, הצעות, הערות ותמונות — יישמר בשירותי Firebase של Google (Cloud Firestore ו-Cloud Storage) תחת החשבון שלכם בלבד. הגיבוי רץ אוטומטית בפתיחת האפליקציה ובסגירתה, ומטרתו היחידה היא לאפשר לכם לשחזר את המאגר במכשיר חדש.

הגישה לגיבוי מוגבלת בכללי אבטחה לחשבון שיצר אותו, ואין באפליקציה שום אפשרות לצפות במאגר של משתמש אחר. המידע אינו משמש לפרסום, לאנליטיקה או למכירה לצדדים שלישיים. יציאה מהחשבון מפסיקה את הגיבוי; המאגר שבמכשיר נשאר כפי שהוא.

האפליקציה משתמשת ב-Firebase App Check כדי לוודא שהבקשות מגיעות מהתקנה אמיתית שלה. הוא אינו מזהה אתכם.

4. ייבוא בעזרת בינה מלאכותית (Gemini של Google)

האפליקציה מציעה ייבוא בעזרת בינה מלאכותית: אפשר למסור לה קובץ גיליון או ייצוא של שיחת וואטסאפ, והיא תקרא מתוכו את האנשים במקום שתקלידו אותם אחד-אחד.

כאשר אתם מפעילים את הייבוא הזה, הטקסט של הקובץ שבחרתם נשלח למודל Gemini של Google, דרך שירות Firebase AI על גבי פלטפורמת Vertex AI, כדי שיפורק לרשומות אנשים. הטקסט הזה עשוי לכלול פרטים אישיים על האנשים שבקובץ — שמות, גילים, מספרי טלפון וכל מה שהקובץ מכיל.

מה שחשוב לדעת על כך:

- זה קורה רק כשאתם מתחילים ייבוא. שום תוכן אינו נשלח למודל ברקע, והתכונה לעולם אינה אוטומטית.
- נשלח טקסט בלבד. תמונות אינן נשלחות למודל אף פעם.
- העיבוד כפוף לתנאי עיבוד הנתונים של Google Cloud, שהם התחייבות חוזית שהתוכן אינו משמש לאימון המודלים של Google ואינו נשמר אצלה.
- הבקשות מעובדות בנקודת הקצה הגלובלית של Google, כלומר ייתכן שהעיבוד יתבצע מחוץ למדינת מגוריכם, ובכלל זה מחוץ לאזור הכלכלי האירופי.
- התוצאות מוצגות לכם לבדיקה, ונכתבות למאגר רק לאחר שאישרתם אותן.

אם אינכם רוצים לשלוח דבר לצד שלישי, פשוט אל תשתמשו בייבוא הזה — כל רשומת אדם ניתנת ליצירה ידנית, ושאר האפליקציה אינה מושפעת.

5. אזור הקהילה והדירוג

באפליקציה קיים אזור קהילה המציג נתונים מצטברים של כלל השדכנים — נקודות פעילות, מספר שדכנים פעילים, חברים שנוספו, רעיונות שנפתחו, זוגות שהתחילו לצאת ואירוסין — וכן דירוג של עשרת השדכנים הפעילים ביותר.

אזור הקהילה פתוח רק למשתמשים שהתחברו עם חשבון Google או Apple. מי שבוחר להשתמש באפליקציה בלי להתחבר אינו שולח שום נתון לשרת הזה, אינו נספר בנתוני הקהילה ואינו מופיע בדירוג — וגם אינו רואה אותם.

לצורך כך, ורק לצורך כך, נשמרים בשרת שני סוגי נתונים על המשתמש שהתחבר: מוני פעילות (היום, השבוע, החודש ומאז ומעולם, וכמה חברים, רעיונות, זוגות שהתחילו לצאת ואירוסין עומדים מאחוריהן) — מספרים בלבד; והשם והתמונה שרשמתם בפרופיל, כדי שאפשר יהיה להציג אתכם בדירוג.

שום פרט על אף אחד מהחברים שבמאגר אינו נשלח לשרת הזה. לא שם, לא גיל, לא טלפון, לא הערה ולא תמונה שלהם. מה שמוצג לשדכנים אחרים הוא השם והתמונה שרשמתם בפרופיל שלכם, והמספרים בלבד.

כברירת מחדל השם והתמונה שרשמתם בפרופיל מופיעים בדירוג הקהילה. מי שמעדיף להישאר אנונימי יכול לכבות בכל רגע את "להופיע בקהילה בשם שלי" מתוך "פרטיות והמאגר שלי" — ואז נשמרים מונים בלבד, ללא שם וללא זיהוי. באותו מקום אפשר גם להדליק את "שמור על הפרטיות שלי", שמפסיק כל שליחה לקהילה, וכן למחוק לחלוטין את נתוני הקהילה שלכם.

יש לשים לב: נתוני הקהילה נקראים על ידי האפליקציה בכל מכשיר שבו היא מותקנת, כדי לחשב את הסכומים ואת הדירוג. לכן יש להתייחס לשם המוצג בדירוג כאל מידע גלוי לכלל משתמשי האפליקציה.

6. הודעת "מזל טוב! זוג חדש התארס!"

כאשר שדכן מסמן באפליקציה שזוג הגיע לחתונה, נשלחת לשרת רשומה קצרה כדי שאפשר יהיה להציג לשאר המשתמשים הודעת "מזל טוב! זוג חדש התארס!".

שום פרט על אף אחד מבני הזוג אינו נשלח לשרת הזה — לא שם, לא שם פרטי, לא תמונה, לא גיל ולא כל פרט אחר. הרשומה מכילה מועד, את מזהה החשבון של השדכן, ואת מזהה ההצעה שלו עצמו (מזהה אקראי שנוצר בטלפון שלו, חסר משמעות מחוץ למאגר שלו, ומשמש רק כדי שאפשר יהיה לשלוח בחזרה ברכה). זה מה שרואים שאר המשתמשים: שזוג כלשהו התארס.

בעבר הציעה האפליקציה גם לפרסם את שמותיהם הפרטיים של בני הזוג ותמונה, לאחר שהשדכן סימן שקיבל את הסכמתם. התכונה הזו הוסרה מהאפליקציה. שני אנשים שאינם משתמשים באפליקציה, שלא הסכימו לדבר ושאין להם דרך לדעת על כך, לא ייחשפו על סמך סימון של אדם שלישי. גם השרת עצמו דוחה כעת כתיבת שם או תמונה של בן זוג, ולא רק האפליקציה נמנעת מכך.

הדבר היחיד שיכול להתווסף להודעה הוא שמו של השדכן עצמו. מיד לאחר סימון החתונה נשאלת שאלה נפרדת: האם לציין בהודעה שהשידוך הזה שלכם. אם תאשרו, יתווסף השם שרשמתם בפרופיל — ותו לא. אם לא תאשרו, או אם תסגרו את השאלה, ההודעה נשארת בלי שם. ההופעה שלכם בדירוג הקהילה אינה תשובה לשאלה הזו, והיא נשאלת מחדש בכל חתונה. מיד לאחר האישור מוצג כפתור "ביטול" שמסיר את השם ומשאיר את ההודעה בלי שם.

יש לשים לב שגם הודעה בלי שם נושאת את מזהה החשבון של השדכן, ומזהה זה משמש גם ברשומת הקהילה שלכם. שדכן שמופיע בדירוג בשמו ניתן לזיהוי בדרך זו גם כשההודעה עצמה אינה נושאת שם.

ההודעה זמנית: היא מוצגת עד שבוע ממועד הפרסום, ואין באפליקציה מסך, רשימה או ארכיון של זוגות שהתארסו.

7. פניות תמיכה

אם תשלחו תקלה או רעיון לשיפור מתוך האפליקציה, יישלחו אלינו הטקסט שכתבתם, תמונה אם צירפתם, השם שבפרופיל, וכן שלושה פרטים טכניים על המכשיר: דגם, מערכת הפעלה וגרסת האפליקציה. הפרטים האלה מוצגים לכם על המסך לפני השליחה. הפניות נגישות למנהלי האפליקציה בלבד, ומשמשות אך ורק לטיפול בפנייה.

8. מידע על אנשים אחרים

האפליקציה בנויה סביב שדכן שרושם מידע על אנשים אחרים, שאינם משתמשים באפליקציה ולא הסכימו למדיניות הזו.

במקום שבו חוקי הגנת הפרטיות חלים עליכם, האחריות על המידע הזה היא שלכם: שתהיה לכם סיבה חוקית להחזיק בו, שתטפלו בו בהגינות, ושתדעו לענות לאותם אנשים אם ישאלו מה רשום אצלכם. האפליקציה בנויה כדי לעזור בכך: הרשומות נשארות במכשיר כברירת מחדל, אינן משותפות עם משתמשים אחרים, ושום פרט מהמאגר אינו נשלח לשרת הקהילה. המסלולים היחידים שבהם מידע כזה יוצא מהמכשיר הם אלה שאתם יוזמים — גיבוי בענן, ייבוא בעזרת בינה מלאכותית, פרסום הודעת אירוסין, ייצוא או שיתוף.

9. שיתוף מידע עם צדדים שלישיים

האפליקציה אינה מוכרת מידע אישי ואינה משתפת אותו עם מפרסמים או עם גורמים מסחריים.

מעבר לאזור הקהילה, לייבוא בעזרת בינה מלאכותית ולפניות התמיכה המתוארים לעיל, מידע יוצא מהמכשיר רק ביוזמתכם: אם תבחרו להשתמש בפונקציות שיתוף, ייצוא גיבוי, פתיחת קובץ גיבוי או חיוג, המידע הרלוונטי עשוי להימסר לאפליקציה, לשירות או למערכת ההפעלה שבחרתם להשתמש בהם. במקרים כאלה, הטיפול במידע כפוף גם למדיניות של השירות או האפליקציה החיצונית שבחרתם.

השירותים החיצוניים שבהם האפליקציה משתמשת, ולכל אחד מהם מדיניות פרטיות משלו:

- Google Play Services, ובכללם Firebase Authentication, Cloud Firestore, Cloud Storage, Firebase App Check, Firebase AI (Gemini על Vertex AI), Google Sign-In ו-Google ML Kit — https://www.google.com/policies/privacy/
- התחברות עם Apple, אם בחרתם בה — https://www.apple.com/legal/privacy/

מעבר לאלה אין באפליקציה שום רשת פרסום, שום ספק אנליטיקה ושום שירות דיווח קריסות.

10. העברת מידע לחו"ל

אם אתם משתמשים בגיבוי בענן, בייבוא בעזרת בינה מלאכותית, באזור הקהילה או בפניות תמיכה, המידע מעובד על גבי התשתית של Google ועשוי לעבור למדינות מחוץ למדינת מגוריכם, ובכלל זה מחוץ לאזור הכלכלי האירופי. בקשות הייבוא בפרט מעובדות בנקודת הקצה הגלובלית של Google.

במקום שבו הדין דורש אמצעי הגנה להעברות כאלה, אנו נסמכים על המנגנונים ש-Google Cloud ו-Firebase מעמידים ללקוחותיהם, ובהם תניות חוזיות סטנדרטיות (SCC) שאישרה הנציבות האירופית, החלטות נאותות, או הסכמתכם במקום שהיא נדרשת ומותרת.

11. הרשאות

האפליקציה עשויה לבקש את ההרשאות הבאות, רק כאשר הן נחוצות לפעולה שבחרתם:

- גישה לאנשי קשר: להצגת אנשי קשר מהמכשיר לצורך ייבוא יזום על ידכם. נשאר במכשיר.
- גישה ליומן שיחות באנדרואיד: למיון מועמדי ייבוא לפי שיחות אחרונות בתצוגת סריקת הכרטיסים. נשאר במכשיר, לצורך מיון בלבד.
- גישה לתמונות או לגלריה: לבחירת תמונה אחת או כמה תמונות לרשומת אדם.
- התראות: להצגת תזכורות מקומיות שהגדרתם. אינן יוצאות מהמכשיר.

ניתן לבטל הרשאות בכל עת דרך הגדרות המכשיר, אך ייתכן שחלק מהתכונות לא יעבדו ללא ההרשאה המתאימה.

12. שמירת מידע ומחיקה

המידע נשמר במכשיר עד שתבחרו לעדכן אותו, למחוק אותו או להסיר את האפליקציה. ניתן למחוק אנשים, תמונות, הערות והצעות מתוך האפליקציה. אם ייצאתם קובץ גיבוי או שיתפתם מידע עם אפליקציה אחרת, עותקים אלה עשויים להישאר מחוץ לאפליקציה עד שתמחקו אותם באופן ידני.

הגיבוי בענן, אם הפעלתם אותו, נשמר תחת החשבון שלכם עד שתמחקו אותו. הוא נמחק מהשרת בלחיצה אחת מתוך "פרטיות והמאגר שלי" — כל הרשומות, הפרופיל וכל התמונות — והמאגר שבמכשיר שלכם נשאר כפי שהוא. יציאה מהחשבון מפסיקה את עדכון הגיבוי אך אינה מוחקת אותו, וגם הסרת האפליקציה לבדה אינה מוחקת אותו.

נתוני הקהילה שלכם — המונים והשם, אם הוא מוצג — נמחקים מהשרת בלחיצה אחת מתוך "פרטיות והמאגר שלי". הסרת האפליקציה לבדה אינה מוחקת אותם.

הודעת אירוסין מוצגת עד שבוע וניתן להסיר אותה מיד בכפתור "ביטול הפרסום". פניות תמיכה נשמרות רק כל עוד הן נדרשות לטיפול בפנייה. תוכן שנשלח לייבוא בעזרת בינה מלאכותית אינו נשמר אצל Google לפי תנאי עיבוד הנתונים של Google Cloud, ואינו נשמר אצלנו.

13. הזכויות שלכם

בכפוף לדין החל, עומדת לכם הזכות לעיין במידע האישי שלכם, לתקן אותו, למחוק אותו, להגביל או להתנגד לעיבודו, לקבל אותו בפורמט נייד, ולחזור בכם מהסכמה כאשר העיבוד מבוסס עליה. את רוב אלה ניתן לממש ישירות מתוך האפליקציה — המידע נמצא במכשיר שלכם, ואת נתוני הקהילה ואת הגיבוי אפשר למחוק מתוכה.

אם אתם תושבי קליפורניה, עומדות לכם גם הזכויות לפי CCPA/CPRA: לדעת איזה מידע נאסף, למחוק אותו, לתקן אותו, לסרב למכירה או לשיתוף שלו, ולא להיות מופלים לרעה על מימוש הזכויות. איננו מוכרים ואיננו משתפים מידע אישי כמשמעות המונחים האלה שם.

לכל דבר שאינכם יכולים לעשות בעצמכם, פנו אל $contactEmail. כמו כן עומדת לכם הזכות להגיש תלונה לרשות להגנת הפרטיות במדינתכם.

14. הפסקת השימוש

תוכלו להפסיק כל עיבוד נוסף בהסרת האפליקציה. שימו לב שהסרה כשלעצמה אינה מוחקת נתוני קהילה שכבר נשמרו בשרת או גיבוי שכבר נוצר — מחקו אותם מתוך "פרטיות והמאגר שלי" לפני ההסרה, או פנו אלינו ונעשה זאת.

15. ילדים

האפליקציה אינה מיועדת לילדים מתחת לגיל 16, או לגיל גבוה יותר אם הדין החל דורש זאת, ואינה משווקת אליהם. איננו אוספים ביודעין מידע אישי מילדים. הורה או אפוטרופוס שסבור שילד מסר לנו מידע אישי מוזמן לפנות אלינו, ונמחק אותו.

16. אבטחת מידע

האפליקציה נשענת על מנגנוני האחסון וההרשאות של מערכת ההפעלה ושל Flutter. הגיבוי בענן, נתוני הקהילה ופניות התמיכה מוגנים בכללי אבטחה בצד השרת המגבילים כל רשומה לחשבון שיצר אותה, וכן ב-Firebase App Check. למרות שננקטים אמצעים סבירים, אין באפשרותנו להבטיח הגנה מוחלטת מפני גישה לא מורשית למכשיר עצמו, ואין שיטת העברה או אחסון שהיא בטוחה לחלוטין.

17. דיווח על אירוע אבטחה

אם יתרחש אירוע אבטחה הפוגע במידע האישי שלכם, נודיע לכם על כך בהתאם לדרישות הדין החל, ובכלל זה על טיב האירוע ועל הצעדים הננקטים בעקבותיו.

18. שינויים במדיניות

ייתכן שמדיניות פרטיות זו תתעדכן מעת לעת. במקרה של שינוי מהותי, הגרסה המעודכנת תחליף את הגרסה הקודמת ותישא תאריך עדכון חדש. במקום שבו הדין דורש זאת, נבקש את הסכמתכם לשינוי מהותי לפני שייכנס לתוקף.

19. יצירת קשר

לשאלות בנושא פרטיות או בקשות הקשורות למידע שלכם, ניתן לפנות אל גלעד שטרוזמן בכתובת $contactEmail.
''';

  static const String english = '''
Last updated: August 21, 2026

Shadchan ("the Application") helps matchmakers manage contacts, match ideas, notes and reminders related to the matchmaking process. It is developed and operated by Gilad Shtruzman ("the Service Provider", "we"), who acts as the data controller for the limited processing described below.

In short: the Application is local-first. Your database lives on your device, and the Application works with no account and no internet connection at all. It contains no advertising network, no analytics SDK, no crash-reporting SDK, no cookies and no tracking. We do not collect your IP address, your browsing behaviour, an advertising identifier, or a record of which screens you visit. We never sell personal information. Data leaves your device only when you sign in and enable cloud backup, when you use an AI-assisted import, when you send a support request, when the community area is active for your account, or when you yourself choose to share, export or publish something.

1. Information the Application processes

You may enter information manually, including first name, family name, gender, age, religious level, city, phone number, a contact for enquiries, how you know the person, private notes, photographs, favourite markers, and information about match ideas and the notes attached to them.

If you choose to use contact import, the Application requests permission to read the contacts on your device in order to show names and phone numbers as import candidates. The candidate list may be cached locally so that returning to the import screen is fast. Contacts you do not choose to import are not added to the Application's records, and no contact data is transmitted anywhere.

In the card-swipe import view on Android, the Application may request access to the call log in order to sort the suggested contacts by most recent calls. The call log is used for local sorting only. It is never uploaded, and it is never stored as a person record unless you choose to import that contact.

If you choose to add photographs, the Application accesses your gallery or media picker so you can select one or more images and save them to a person record. To centre a photograph on the face rather than cropping it off, the Application runs Google ML Kit face detection entirely on the device. No photograph, and no data derived from it, is transmitted anywhere for this purpose.

If you share text or an image into the Application from another app, WhatsApp for example, the shared content is copied temporarily to your device and shown to you so you can decide whether to add it to an existing person or create a new one. It is saved to a record only after a deliberate action of yours.

If you choose to export or import a backup, the Application creates or reads a JSON file that may contain everything stored in the Application, including people, ideas, notes and local photographs. The Application does not store dates of birth. Older versions did, so a backup file created by one of them may contain a date of birth — in that case the Application reads it during the import, converts it to an age, and does not keep the date itself.

If you allow notifications, the Application shows local reminders you set yourself on ideas and on people, and an invitation to come back if you have not opened it for a week. They are scheduled on the device, and no reminder content is sent to a server.

2. How the information is used

Information is used to operate the features of the Application and nothing else: managing person records, creating and tracking match ideas, adding notes, searching and filtering, importing contacts you select, sorting import candidates by recent calls on Android, displaying and storing photographs, sharing that you initiate, AI-assisted import when you start it, backup and restore, and local reminders you set yourself.

We do not use your information for advertising, profiling, automated decision-making with legal effect, or marketing. We will not send you marketing communications.

3. Where information is stored

As of August 21, 2026, information is stored locally on the device on which the Application is installed: in the Application's local database, and in local files for photographs and temporary backups. The Application works fully offline and with no account.

The Application does not require an account. It offers to sign in once, and you may decline and keep working locally.

If, and only if, you choose to sign in with a Google or Apple account, cloud backup is enabled: a copy of your database — people, ideas, notes and photographs — is stored in Google's Firebase services (Cloud Firestore and Cloud Storage) under your account alone. The backup runs automatically when the Application opens and closes, and its only purpose is to let you restore your database on a new device.

Access to the backup is restricted by server-side security rules to the account that created it, and the Application provides no way whatsoever to view another user's database. This data is not used for advertising, analytics, or sale to third parties. Signing out stops the backup; the database on the device stays exactly as it is.

Firebase App Check is used to verify that requests come from a genuine installation of the Application. It does not identify you.

4. AI-assisted import (Google Gemini)

The Application offers AI-assisted import: you can hand it a spreadsheet, or a WhatsApp chat export, and it will read the people out of it instead of you typing them in one at a time.

When you start such an import, the text of the file you selected is sent to Google's Gemini model, through Firebase AI on the Vertex AI platform, so that it can be parsed into person records. That text may contain personal information about the people in the file — names, ages, phone numbers, and whatever else the file happens to contain.

What you should know about this:

- It happens only when you start an import. No content is sent to the model in the background, and the feature is never automatic.
- Only text is sent. Photographs are never sent to the model.
- Processing is governed by the Google Cloud data-processing terms, which are a contractual commitment that the content is not used to train Google's models and is not retained.
- Requests are processed on Google's global endpoint, which means processing may occur outside your country of residence, including outside the European Economic Area.
- The parsed results are shown to you for review, and are written to your database only after you accept them.

If you would rather not send anything to a third party, do not use the AI import. Every record can be created manually, and the rest of the Application is unaffected.

5. Community area and leaderboard

The Application includes a community area showing aggregate figures across all matchmakers — activity points, number of active matchmakers, friends added, ideas opened, couples who started dating, and engagements — along with a leaderboard of the ten most active matchmakers.

The community area is open only to users who signed in with a Google or Apple account. If you use the Application without signing in, you send no data to this server at all, you are not counted in the community figures, you do not appear in the leaderboard, and you do not see them.

For this purpose, and only for this purpose, two kinds of data about a signed-in user are stored on the server: activity counters (today, this week, this month and all-time, and how many friends, ideas, couples dating and engagements lie behind them) — numbers only; and the name and picture from your profile, so that you can be shown in the leaderboard.

No detail about any person in your database is ever sent to this server. Not a name, not an age, not a phone number, not a note, not a photograph of them. What other matchmakers see is the name and picture from your own profile, and the numbers.

By default, the name and picture from your profile do appear in the community leaderboard. Anyone who prefers to stay anonymous can switch off "Appear in the community under my name" at any time from "Privacy and my database" — counters are then kept with no name and no identification. In the same place you can switch on "Keep me private", which stops anything at all being sent to the community, and you can delete your community data entirely.

Please note: the community data is read by the Application on every device it is installed on, in order to compute the totals and the leaderboard. Treat a name shown in the leaderboard as visible to every user of the Application.

6. "Mazal tov! A new couple is engaged" announcements

When a matchmaker marks in the Application that a couple has reached the wedding, a short record is sent to the server so that the announcement can be shown to other users.

No detail about either member of the couple is ever sent to this server — not a name, not a first name, not a photograph, not an age, nothing. The record holds a timestamp, the matchmaker's account identifier, and their own proposal id (a random identifier generated on their phone, meaningless outside their own database, carried only so a congratulation can be delivered back). What other users see is that some couple got engaged.

The Application used to offer to publish the couple's first names and a photograph, once the matchmaker confirmed they had the couple's consent. That feature has been removed. Two people who are not users of the Application, who agreed to nothing and would have no way of knowing, are not made public on the strength of a third person ticking a box. The server itself now rejects any attempt to write a couple's name or picture — it is not merely that the app declines to.

The only thing that can be added to an announcement is the matchmaker's own name. Right after the wedding is marked, a separate question is asked: may the announcement say that this match was yours. If you agree, the name from your profile is added — and nothing else. If you decline, or dismiss the question, the announcement stays nameless. Appearing in the community leaderboard is not an answer to this question, and it is asked afresh for every wedding. Immediately afterwards an "Undo" button removes the name and leaves the announcement nameless.

Note that even a nameless announcement carries the matchmaker's account identifier, and that identifier is also used by your community record. A matchmaker who appears in the leaderboard under their name can be identified this way even when the announcement itself carries no name.

The announcement is temporary: it is shown for up to one week from publication, and the Application has no screen, list or archive of engaged couples.

7. Support requests

If you send a problem report or an improvement idea from within the Application, we receive the text you wrote, an image if you attached one, the name in your profile, and three technical details about the device: model, operating system, and application version. These are shown to you on screen before sending. Support requests are accessible to the Application's administrators only, and are used solely to handle the request.

8. Information about other people

The Application is built around a matchmaker recording information about other people, who are not users of the Application and have not agreed to this policy.

Where data protection law applies to you, you are responsible for that information: for having a lawful basis to hold it, for handling it fairly, and for responding to the people concerned if they ask what you hold about them. The Application is designed to help: records stay on your device by default, they are never shared with other users, and no detail from your database is ever transmitted to the community server. The only paths by which such information leaves your device are the ones you initiate — cloud backup, AI import, an engagement announcement you publish, an export, or a share.

9. Sharing and disclosure

The Application does not sell personal information and does not share it with advertisers or commercial parties.

Beyond the community area, the AI import and the support requests described above, information leaves the device only at your initiative: if you use sharing, backup export, opening a backup file, or dialling, the relevant information may be handed to the application, service or operating system you chose. In those cases the handling of that information is also subject to the policy of the external service you selected.

The third-party services the Application uses, each with its own privacy policy:

- Google Play Services, covering Firebase Authentication, Cloud Firestore, Cloud Storage, Firebase App Check, Firebase AI (Gemini on Vertex AI), Google Sign-In and Google ML Kit — https://www.google.com/policies/privacy/
- Sign in with Apple, if you choose it — https://www.apple.com/legal/privacy/

Beyond these, the Application uses no advertising networks, no analytics providers and no crash-reporting services.

We may disclose information as required by law, such as to comply with a subpoena or similar legal process; when we believe in good faith that disclosure is necessary to protect our rights, protect your safety or the safety of others, investigate fraud, or respond to a government request; and to trusted service providers who work on our behalf, have no independent use of the information, and are bound by the rules set out here.

10. International data transfers

If you use cloud backup, AI import, the community area or support requests, the data involved is processed on Google's infrastructure and may be transferred to countries outside your country of residence, including outside the European Economic Area. AI import requests in particular are processed on Google's global endpoint.

Where applicable law requires safeguards for such transfers, we rely on the mechanisms Google Cloud and Firebase provide for their customers, including Standard Contractual Clauses approved by the European Commission, adequacy decisions, or your consent where it is required and legally permitted.

11. Legal bases for processing (EEA/UK)

Performance of a contract — operating the features you asked for, including storing your records and, if enabled, restoring them from backup.

Consent — device permissions (contacts, call log, photos, notifications), signing in and enabling cloud backup, publishing an engagement announcement with details, and using AI-assisted import. You may withdraw consent at any time; withdrawal does not affect processing carried out beforehand.

Legitimate interests — running the community area for signed-in users, including showing your profile name and picture in the leaderboard, which you can switch off at any time; verifying that requests come from a genuine installation; handling support requests you send; and preventing abuse.

12. Permissions

The Application may request the following permissions, only when they are needed for an action you chose:

- Contacts: to show device contacts so you can import the ones you pick. Stays on the device.
- Call log (Android): to sort import candidates by recent calls in the card-swipe view. Stays on the device, for sorting only.
- Photos and gallery: to choose one or more images for a person record.
- Notifications: local reminders you set yourself. Never leave the device.

You may revoke permissions at any time through device settings, but some features may not work without the corresponding permission.

13. Data retention and deletion

On-device data is kept until you update it, delete it, or uninstall the Application. You can delete people, photographs, notes and ideas from within the Application. If you exported a backup file or shared information with another application, those copies may remain outside the Application until you delete them manually.

Cloud backup, if enabled, is kept under your account until you delete it or delete your account. Signing out stops the backup being updated.

Your community data — the counters, and your name if it is displayed — is deleted from the server with one tap from "Privacy and my database". Uninstalling the Application alone does not delete it.

An engagement announcement is shown for up to one week and can be removed immediately with the "Unpublish" button. Support requests are kept only as long as needed to handle the request. Content sent for AI-assisted import is not retained by Google under the Google Cloud data-processing terms, and is not retained by us.

14. Your rights

Subject to applicable law, you have the right to access, correct, delete, restrict or object to the processing of your personal data, the right to data portability, and the right to withdraw consent where processing is based on consent. Most of these you can exercise directly in the Application — the data is on your device, and the community and backup data can be deleted from within it.

If you are a California resident, you also have the rights under the CCPA/CPRA to know what personal information is collected, to delete it, to correct it, to opt out of its sale or sharing, and not to be discriminated against for exercising those rights. We do not sell or share personal information as those terms are defined there, and we do not use it for cross-context behavioural advertising.

For anything you cannot do yourself, contact $contactEmail. You also have the right to lodge a complaint with your local data protection authority.

15. Opt-out

You can stop any further processing by uninstalling the Application. Note that uninstalling does not by itself delete community data already stored on the server or a cloud backup already created — delete those from "Privacy and my database" before you uninstall, or write to us and we will do it.

16. Children

The Application is not intended for children under 16 years of age, or such higher age as required by applicable law, and is not marketed to them. We do not knowingly collect personal information from children. A parent or guardian who believes a child has provided us with personal information is invited to contact us, and we will delete it.

17. Security

The Application relies on the storage and permission mechanisms of the operating system and of Flutter. Cloud backup, community data and support requests are protected by server-side security rules that restrict each record to the account that created it, and by Firebase App Check. Although reasonable measures are taken, we cannot guarantee absolute protection against unauthorised access to the device itself, and no method of transmission or storage is completely secure.

18. Data breach notification

If a data breach occurs that affects your personal data, we will notify you in accordance with applicable legal requirements, including, where required, the nature of the breach and the steps being taken to address it.

19. Changes to this policy

This privacy policy may be updated from time to time. In the event of a material change, the updated version will replace the previous one and carry a new update date. Where required by law, we will seek your consent to material changes before they take effect.

20. Contact

For questions about privacy, or requests concerning your information, contact Gilad Shtruzman at $contactEmail.
''';
}
