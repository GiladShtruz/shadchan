import 'package:flutter/material.dart';
import 'package:shadchan/services/analytics_service.dart';

/// "שליחת נתוני שימוש לשיפור האפליקציה" — the switch behind [Analytics].
///
/// On by default, one tap off, and synced with the account so it holds on
/// every phone. What it sends is said right under it: what was done, never
/// who it was about.
class UsageDataTile extends StatefulWidget {
  const UsageDataTile({super.key});

  static const String title = 'שליחת נתוני שימוש לשיפור האפליקציה';

  static const String explanation =
      'נספר רק מה נעשה באפליקציה — כמה חברים נוספו, כמה רעיונות נפתחו, איפה '
      'נתקעים — כדי לדעת מה לשפר. לעולם לא שמות, טלפונים, כרטיסים, הערות או '
      'הקלטות, ושום פרט על החברים שבמאגר.';

  @override
  State<UsageDataTile> createState() => _UsageDataTileState();
}

class _UsageDataTileState extends State<UsageDataTile> {
  late bool _on = !Analytics.optedOut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: _on,
      onChanged: (bool value) {
        setState(() => _on = value);
        Analytics.setOptedOut(!value);
      },
      secondary: Icon(
        Icons.insights_outlined,
        size: 22,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        UsageDataTile.title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        UsageDataTile.explanation,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      isThreeLine: true,
    );
  }
}
