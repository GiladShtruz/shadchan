import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "פרטיות והמאגר שלי" — the human answer, next to but separate from the legal
/// privacy policy.
///
/// It exists because of what this app actually holds. A matchmaker's database is
/// other people's names, ages, phone numbers and private notes about their
/// shidduchim — information their friends handed over in confidence, not
/// something they published. The person typing it in deserves to know exactly
/// where it goes, in the same language they would ask the question in, without
/// reading four screens of policy to find out.
///
/// The legal document stays where it was and is linked from the bottom. This
/// page never contradicts it; it says the same things in fewer words.
class PrivacyOverviewScreen extends StatelessWidget {
  const PrivacyOverviewScreen({super.key});

  static const List<({IconData icon, String title, String body})>
  _points = <({IconData icon, String title, String body})>[
    (
      icon: Icons.lock_outline_rounded,
      title: 'המאגר הוא שלך בלבד',
      body:
          'כל מה שנשמר באפליקציה — חברים, רעיונות, הערות, הקלטות ותמונות — '
          'שייך לחשבון שלך. אין באפליקציה שום מסך שמראה מאגר של שדכן אחר, '
          'ואין דרך לחפש בו.',
    ),
    (
      icon: Icons.cloud_outlined,
      title: 'המאגר נעול לחשבון שלך',
      body:
          'חשבון הוא חובה, ואפשר להיכנס עם Google, עם Apple באייפון או עם '
          'מייל וסיסמה. המאגר נשמר ב־Firebase ומסתנכרן בין כל המכשירים '
          'המחוברים לאותו חשבון, וכללי אבטחה בצד השרת מאפשרים לקרוא אותו רק '
          'לחשבון עצמו. עותק נשמר גם במכשיר, כדי שאפשר יהיה לעבוד בלי חיבור.',
    ),
    (
      icon: Icons.groups_outlined,
      title: 'החברים שלך לא מקבלים חשבון',
      body:
          'האנשים {שאתה מוסיף|שאת מוסיפה} למאגר אינם משתמשים באפליקציה, '
          'לא מקבלים הודעה ולא רואים מה נכתב עליהם. הכרטיס שלהם נשלח רק '
          '{כשאתה בוחר|כשאת בוחרת} לשלוח אותו, בשיתוף רגיל מהטלפון.',
    ),
    (
      icon: Icons.badge_outlined,
      title: 'כרטיס אישי שחבר מנהל בעצמו',
      body:
          'חבר יכול למלא כרטיס אישי ולתת גישה רק לשדכנים שהוא בוחר. ההרשאה '
          'נבדקת בשרת, ואפשר להסיר אותה בכל רגע — ואז פרטי הכרטיס יורדים גם '
          'מהמכשיר של השדכן. מה שהשדכן כתב בעצמו נשאר אצלו בלבד ולא מגיע '
          'לחבר או לשדכן אחר. למציאת חברים נשלחים לשרת רק מספרים מגובבים, '
          'בלי שמות.',
    ),
    (
      icon: Icons.auto_awesome_outlined,
      title: 'מה נשלח בייבוא עם AI',
      body:
          'רק הטקסט שבחרת לייבא באותו רגע נשלח ל־Gemini. המאגר הקיים והתמונות '
          'לא נשלחים למודל. לפי תנאי Google Cloud, נתוני לקוח אינם משמשים '
          'לאימון מודלים בלי רשות, אך ייתכן עיבוד או שמירה לצורכי אבטחה, '
          'מניעת שימוש לרעה ותפעול השירות.',
    ),
    (
      icon: Icons.leaderboard_outlined,
      title: 'מה כן נראה לשדכנים אחרים',
      body:
          'נתוני הקהילה כוללים מוני פעילות. אם בחרת להופיע בשם, שדכנים '
          'מחוברים יכולים לראות גם את השם והתמונה שלך, המשפט הקצר, תשובות '
          'שבחרת לשתף, הטבה לקהילה ומספר WhatsApp שהזנת מרצונך. שום פרט '
          'על חבר מהמאגר אינו נכתב שם.\n'
          'בתחתית העמוד אפשר להסתיר את הפרופיל, לעצור לגמרי את הפרסום '
          'לקהילה או למחוק את נתוני הקהילה שכבר נשלחו.',
    ),
    (
      icon: Icons.favorite_outline_rounded,
      title: 'זוג שהתארס — בלי לחשוף את בני הזוג',
      body:
          'כשמסמנים שזוג הגיע לחתונה, שאר המשתמשים רואים הודעת מזל טוב '
          'אנונימית לגמרי: בלי שמות, בלי תמונה ובלי שום פרט. רק שזוג '
          'כלשהו התארס.\n'
          'מיד אחר כך {תוכל|תוכלי} לבחור להוסיף רק את שמך שלך, אחרי שאלה '
          'נפרדת. אי אפשר לפרסם שם, תמונה או פרט אחר של בני הזוג — גם כללי '
          'השרת מסרבים לקבל מידע כזה.',
    ),
    (
      icon: Icons.celebration_outlined,
      title: 'ברכות מזל טוב בין שדכנים',
      body:
          'על הודעת החתונה אפשר ללחוץ "שלחו מזל טוב". מה שנשלח הוא הברכה '
          'שכתבת והשם שלך, והיא מגיעה רק לשדכן עצמו — אל ההיסטוריה של אותה '
          'הצעה אצלו. רק השולח והמקבל רשאים לקרוא אותה, והשולח אינו יודע מי '
          'בני הזוג.\n'
          'מי ששלח לך ברכה רואה רק את השם שלך — שום פרט על הזוג לא נחשף לו.',
    ),
    (
      icon: Icons.forum_outlined,
      title: 'מה רואים כשפונים אלינו',
      body:
          'בפנייה על תקלה נשלחים מה שכתבת, תמונה אם צירפת, שמך ומזהה החשבון '
          'ושלושה פרטים על המכשיר — דגם, מערכת הפעלה וגרסת האפליקציה. רק '
          'אתה ומנהלי התמיכה יכולים לקרוא את הפנייה ואת שרשור התגובות.',
    ),
    (
      icon: Icons.delete_outline_rounded,
      title: 'למחוק זה למחוק',
      body:
          'אפשר למחוק אדם, תמונה, הערה או רעיון מתוך האפליקציה בכל רגע. '
          'הסרת האפליקציה או התנתקות מוחקות את העותק שבמכשיר, אבל המאגר '
          'נשאר בחשבון. למחיקת החשבון וכל הנתונים: הפרופיל שלי ← החשבון שלי '
          '← מחיקת החשבון. יש 30 יום לשחזר אותו לפני שהמחיקה סופית.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Gender? gender = context.userGender;

    return Scaffold(
      appBar: AppBar(title: const Text('פרטיות והמאגר שלי')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: dark
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : AppColors.primaryLight.withValues(alpha: 0.5),
              ),
              child: Text(
                'המאגר שלך הוא יומן אישי ופרטי. הוא מכיל מידע על חברים שסמכו '
                'עליך, ולכן חשוב לנו שיהיה ברור בדיוק מה נשמר, איפה, ומי יכול '
                'לראות אותו.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            for (final ({IconData icon, String title, String body}) point
                in _points)
              _PrivacyPoint(
                icon: point.icon,
                title: point.title,
                body: point.body.forGender(gender),
              ),
            const SizedBox(height: 4),
            // The narrow question first — may my name be shown — then the
            // wide one that makes it moot, then the erasure of what already
            // went. Read top to bottom they are three steps of the same
            // decision rather than three unrelated switches.
            const LeaderboardNameTile(),
            const SizedBox(height: 4),
            const PrivateModeTile(),
            const SizedBox(height: 4),
            const DeleteCommunityDataTile(),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/privacy-policy'),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('מדיניות הפרטיות המלאה'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color tone = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
