import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// The single's own answer to "may my matchmaker show my card to the
/// matchmakers they know personally?" — one switch per matchmaker, in the
/// personal area. Off until the single turns it on.
///
/// **The explanation is the point.** A card does not open to the public or
/// to a mass database: only to matchmakers who know this matchmaker
/// personally and are connected with them in the app, view only, and every
/// approach still goes through this matchmaker. Turning it off takes the card
/// out at once.
class OnwardShareSwitch extends StatelessWidget {
  const OnwardShareSwitch({super.key, required this.row, required this.name});

  final CardAccess row;
  final String name;

  static String explanation(String name) =>
      'הכרטיס שלך לא נפתח לציבור ולא למאגר המוני. הוא יוצג רק לשדכנים שמכירים '
      'את $name אישית ומחוברים אליו/ה בשדכן — כדי שעוד שדכנים שסומכים עליהם '
      'יוכלו לחשוב עליך.\n\n'
      'הם יראו את הכרטיס בלבד: תמונות, פרטים, "מה אני מחפש/ת" ותגיות. לא '
      'יוכלו לשמור, לערוך או לשתף אותו, ולא לפנות אליך ישירות — כל פנייה תעבור '
      'דרך $name.\n\n'
      'השליטה נשארת אצלך: אפשר לבטל בכל רגע, והכרטיס ייעלם מהם מיד.';

  Future<void> _set(BuildContext context, bool on) async {
    if (!OfflineGuard.allow(context)) return;
    if (on) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('לאפשר ל$name לשתף את הכרטיס עם שדכנים שהוא/היא מכיר/ה?'),
          content: SingleChildScrollView(child: Text(explanation(name))),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('לא עכשיו'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('לאשר'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    final bool done = await context.read<CardAccessProvider>().setShareOnward(
      row,
      allowed: on,
    );
    if (!context.mounted || done) return;
    AppNotice.show(context, 'לא הצלחנו לשמור. נסו שוב.', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool asking = row.shareOnwardRequested && !row.shareOnward;
    return Material(
      color: asking
          ? theme.colorScheme.secondary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: SwitchListTile(
        value: row.shareOnward,
        onChanged: (bool on) => _set(context, on),
        title: Text('$name יכול/ה להציג את הכרטיס לשדכנים שהוא/היא מכיר/ה'),
        subtitle: Text(
          asking
              ? '$name מבקש/ת את האישור שלך · רק שדכנים שמחוברים אליו/ה, לא מאגר ציבורי'
              : 'רק לשדכנים שמחוברים אליו/ה אישית — לא מאגר ציבורי',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
