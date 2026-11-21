import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The short introduction a matchmaker meets before sharing anything: the
/// database stays private until they choose, and three steps make it bigger —
/// connect with matchmakers you know, choose what to share, get more cards and
/// ideas. Shown while sharing is off, until closed once.
class NetworkOnboardingCard extends StatelessWidget {
  const NetworkOnboardingCard({super.key});

  static const List<(IconData, String, String)>
  steps = <(IconData, String, String)>[
    (
      Icons.handshake_outlined,
      'מוצאים שדכנים מאנשי הקשר',
      'שדכנים ששמורים אצלך בטלפון ומשתמשים בשדכן מופיעים מעצמם',
    ),
    (
      Icons.ios_share_rounded,
      'בוחרים מה לשתף עם כל שדכן',
      'כל המאגר, אנשים נבחרים או הכל חוץ מ… — בנפרד לכל אחד, רק כרטיסים מלאים',
    ),
    (
      Icons.auto_awesome_outlined,
      'מקבלים גישה לעוד כרטיסים ורעיונות',
      'רואים מה שדכנים שיתפו איתך, ומציעים להם רעיונות בצ\'אט',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'המאגר שלך פרטי — עד שתבחר/י אחרת',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'סגירה',
                  visualDensity: VisualDensity.compact,
                  onPressed: NetworkSharing.finishOnboarding,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            for (int i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.softBlue,
                      child: Icon(
                        steps[i].$1,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${i + 1}. ${steps[i].$2}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(steps[i].$3, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () {
                  NetworkSharing.finishOnboarding();
                  context.push('/known-matchmakers');
                },
                child: const Text('לשדכנים שאני מכיר'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
