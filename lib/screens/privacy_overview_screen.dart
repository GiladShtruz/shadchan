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

  static const List<({IconData icon, String title, String body})> _points =
      <({IconData icon, String title, String body})>[
        (
          icon: Icons.lock_outline_rounded,
          title: 'המאגר הוא שלך בלבד',
          body:
              'כל מה שנשמר באפליקציה — חברים, רעיונות, הערות ותמונות — נשמר '
              'קודם כול במכשיר שלך. אין באפליקציה שום מסך שמראה מאגר של שדכן '
              'אחר, ואין דרך לחפש בו.',
        ),
        (
          icon: Icons.cloud_outlined,
          title: 'הגיבוי בענן נעול לחשבון שלך',
          body:
              'רק אם התחברת עם חשבון Google נשמר עותק בענן. הוא נעול לחשבון '
              'הזה בכללי אבטחה בצד השרת, כך שאפילו אנחנו לא רואים אותו. אם לא '
              'התחברת — שום דבר לא עולה לענן.',
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
          icon: Icons.auto_awesome_outlined,
          title: 'מה נשלח בייבוא עם AI',
          body:
              'רק הקובץ או הטקסט שבחרת לייבא באותו רגע נשלח לקריאה, והוא לא '
              'משמש לאימון מודלים. המאגר הקיים שלך לא נשלח לשום מקום, אף פעם.',
        ),
        (
          icon: Icons.leaderboard_outlined,
          title: 'מה כן נראה לשדכנים אחרים',
          body:
              'רק שני דברים: השם שרשמת בפרופיל, ומספר נקודות הפעילות '
              'שצברת. זה מה שמרכיב את נתוני הקהילה ואת הדירוג.\n'
              'כל זה קורה רק אם התחברת עם חשבון. בלי התחברות שום נתון '
              'שלך לא נשלח לקהילה, ולא תופיע בדירוג.\n'
              'אם החלטת שאינך רוצה להופיע יותר, אפשר למחוק את נתוני הקהילה '
              'שלך לגמרי — הכפתור נמצא בתחתית העמוד הזה.',
        ),
        (
          icon: Icons.favorite_outline_rounded,
          title: 'זוג שהתארס — והמקום היחיד שבו שם של חבר יכול לצאת',
          body:
              'כשמסמנים שזוג הגיע לחתונה, שאר המשתמשים רואים הודעת מזל טוב '
              'אנונימית לגמרי: בלי שמות, בלי תמונה ובלי שום פרט. רק שזוג '
              'כלשהו התארס.\n'
              'מיד אחר כך {תוכל|תוכלי} לבחור להוסיף להודעה שמות פרטיים, תמונה '
              'ואת שמך — אבל רק אחרי שתסמן{|י} שקיבלת אישור מבני הזוג עצמם. '
              'בלי הסימון הזה שום דבר לא נשלח. זה המקום היחיד באפליקציה שבו '
              'פרט על חבר יכול לצאת מהמכשיר, וזה קורה רק ביוזמתך.',
        ),
        (
          icon: Icons.forum_outlined,
          title: 'מה רואים כשפונים אלינו',
          body:
              'בפנייה על תקלה נשלחים רק מה שכתבת, תמונה אם צירפת, ושלושה '
              'פרטים על המכשיר — דגם, מערכת הפעלה וגרסת האפליקציה. שום פרט על '
              'אף אחד מהחברים שלך לא נשלח.',
        ),
        (
          icon: Icons.delete_outline_rounded,
          title: 'למחוק זה למחוק',
          body:
              'אפשר למחוק אדם, תמונה, הערה או רעיון מתוך האפליקציה בכל רגע. '
              'הסרת האפליקציה מוחקת את כל מה ששמור במכשיר; אם יש גיבוי בענן, '
              'אפשר לבקש למחוק גם אותו.',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Gender? gender = context.userGender;

    return Scaffold(
      appBar: AppBar(title: const Text('פרטיות והמאגר שלי'), centerTitle: true),
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
            // The one control that acts on what this page describes rather than
            // only describing it. "להסתיר אותי מהדירוג" used to sit beside it;
            // it was removed from the app by product decision, so **this is now
            // the only way to take a published name back down** and it has to
            // stay exactly where somebody looking for it would look.
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
