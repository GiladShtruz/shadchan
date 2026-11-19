import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/services/offline_guard.dart';

/// The single's own answer to "may the matchmakers I approved show my card
/// to the matchmakers they know?" — **one general setting**, not a switch per
/// matchmaker. On by default; the single can turn it off at any time.
///
/// **The explanation is the point.** The card does not open to the public or
/// to an unlimited database: only to matchmakers who know the single's
/// matchmakers and are connected with them in the app, view only, and it is
/// not passed on any further. Turning it off takes the card out of those
/// pools at once; the matchmakers the single approved keep it.
class OnwardShareSwitch extends StatelessWidget {
  const OnwardShareSwitch({super.key});

  static const String title =
      'השדכנים שאישרתי יכולים להציג את הכרטיס שלי לשדכנים שהם מכירים';

  /// What sharing through the matchmakers is, and what it is not.
  static const String explanation =
      'השיתוף אינו ציבורי או בלתי מוגבל. הכרטיס שלך מוצג רק לשדכנים שמכירים '
      'את השדכנים שאישרת ומחוברים אליהם באפליקציה, לצפייה בלבד, ואינו ממשיך '
      'לעבור הלאה. כל פנייה אליך עוברת דרך השדכן שאישרת.';

  /// What turning it off does.
  static const String offExplanation =
      'הכרטיס שלך יישאר זמין לשדכנים שאישרת, אבל לא יוצג לשדכנים שהם מכירים.';

  static Future<void> set(BuildContext context, bool on) async {
    if (!OfflineGuard.allow(context)) return;
    final PersonalCardProvider cards = context.read<PersonalCardProvider>();
    final CardAccessProvider access = context.read<CardAccessProvider>();
    if (!on) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('לכבות את השיתוף דרך השדכנים?'),
          content: const Text(offExplanation),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('לכבות'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await cards.setShareOnward(on);
    await access.applyShareOnward(on);
  }

  static Future<void> explain(BuildContext context) => showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('שיתוף דרך השדכנים שלי'),
      content: const SingleChildScrollView(
        child: Text('$explanation\n\n$offExplanation'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('הבנתי'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = context.watch<PersonalCardProvider>().shareOnward;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SwitchListTile(
              value: on,
              onChanged: (bool value) => set(context, value),
              title: const Text(title),
              subtitle: Text(
                on
                    ? 'הגדרה כללית לכל השדכנים שאישרת · לא ציבורי, לצפייה בלבד'
                    : offExplanation,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => explain(context),
                child: const Text('מה זה אומר?'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
