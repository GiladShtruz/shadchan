import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';

/// One answer per thing people actually get stuck on, and nothing else.
///
/// **Deliberately not an FAQ.** A long list of questions is written for the
/// person who built the app, not for the person using it: it grows every time
/// somebody asks something, and after twenty entries nobody reads any of them.
/// Six topics, each answered in a few lines, each opening only when it is
/// tapped — so the page is a table of contents at rest.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const List<({String title, String body})> _topics =
      <({String title, String body})>[
        (
          title: 'איך מוסיפים חברים?',
          body:
              'מעמוד הבית, בכפתור "הוספת חברים". אפשר לבחור מתוך אנשי הקשר '
              'בטלפון, למלא פרטים ידנית, או לתת ל‑AI לקרוא כרטיסייה, צילום '
              'מסך או קובץ.\n'
              'לא צריך למלא הכול בהתחלה — שם זה מספיק כדי להתחיל, ואת השאר '
              'אפשר להשלים מתי שנוח.',
        ),
        (
          title: 'איך מייבאים מ‑WhatsApp?',
          body:
              'פותחים ב‑WhatsApp את הקבוצה או השיחה, לוחצים על שלוש הנקודות '
              'בתפריט העליון, בוחרים "עוד" ואז "ייצוא צ׳אט", בוחרים "לכלול '
              'מדיה", ובמסך השיתוף בוחרים את אפליקציית השדכן.\n'
              'האפליקציה תקרא את השיחה ותציע רשימה של אנשים להוספה — כלום לא '
              'נכנס למאגר לפני שמאשרים.',
        ),
        (
          title: 'איך פותחים רעיון?',
          body:
              'מעמוד הבית בכפתור "הוספת רעיון", או מתוך הכרטיס של אחד הצדדים '
              'בכפתור "פתיחת הצעה".\n'
              'בוחרים את שני הצדדים, אפשר להוסיף הערה, וזהו. מכאן הרעיון חי '
              'ביומן שלו: סטטוס, הערות, תזכורות וכל מה שקרה בדרך.',
        ),
        (
          title: 'איך עובדות ההתאמות?',
          body:
              'האפליקציה משווה בין הכרטיסים שבמאגר — גיל, סגנון דתי ומה שכל '
              'צד סימן שהוא מחפש — ומציעה זוגות שיכולים להתאים.\n'
              'זו תמיד הצעה לבדיקה שלך, לא החלטה. ככל שהכרטיסים מלאים יותר, '
              'ההצעות מדויקות יותר.',
        ),
        (
          title: 'איך עובדות התזכורות?',
          body:
              'על כל חבר ועל כל רעיון אפשר לקבוע תזכורת — "לבדוק שוב בעוד '
              'חודש". ביום שנקבע היא מופיעה על הלוח בעמוד הבית, וגם כהתראה '
              'בטלפון.\n'
              'התזכורות נקבעות רק על ידך; האפליקציה לא מייצרת תזכורות מעצמה.',
        ),
        (
          title: 'מי יכול לראות את המאגר שלי?',
          body:
              'רק את/ה. המאגר שמור במכשיר שלך, ואם התחברת לחשבון — גם בגיבוי '
              'פרטי שנעול לחשבון הזה בלבד.\n'
              'אין באפליקציה שום מסך שמראה מאגר של משתמש אחר, ואין דרך לחפש '
              'אנשים של שדכן אחר.',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('עזרה והדרכה'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: <Widget>[
            Text(
              'התשובות הקצרות לדברים שהכי שואלים. אם משהו עדיין לא ברור — '
              'אפשר לכתוב לנו, ונשמח לעזור.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            for (final ({String title, String body}) topic in _topics)
              _HelpTile(title: topic.title, body: topic.body),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/support/report'),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('שליחת תקלה / רעיון לשיפור'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => CommunityLinks.openSupportEmail(),
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('כתבו לנו במייל'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            iconColor: dark ? theme.colorScheme.primary : AppColors.primaryDark,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
