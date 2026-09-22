import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// How to get a WhatsApp export into the app, step by step.
///
/// **This is what "ייצוא מוואטסאפ" opens**, rather than the file picker. The
/// picker lands wherever the phone last left it — for most people Google
/// Drive, which holds no chat export and explains nothing — so the tap that
/// says "ייצוא מוואטסאפ" now answers the only question somebody at that point
/// actually has: how do I make one. The picker is still here, one button down,
/// for whoever already has the file.
///
/// The route ends at WhatsApp's own share sheet rather than at "save the file,
/// then come back and find it" — the app is registered for a shared `.zip`,
/// so handing it straight over is both shorter to describe and the route with
/// nowhere to lose the file along the way.
class WhatsAppExportGuideScreen extends StatelessWidget {
  const WhatsAppExportGuideScreen({super.key});

  /// Opens the guide. Resolves to `true` when the matchmaker asked for the
  /// file picker instead, so the caller can run its own import flow.
  static Future<bool> open(BuildContext context) async {
    final bool? pickFile = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const WhatsAppExportGuideScreen(),
      ),
    );
    return pickFile ?? false;
  }

  static const List<String> _steps = <String>[
    'פותחים ב־WhatsApp את הקבוצה או השיחה שרוצים לייבא.',
    'לוחצים על שלוש הנקודות בתפריט העליון.',
    'בוחרים "עוד" ואז "ייצוא צ׳אט".',
    'בוחרים "לכלול מדיה".',
    'במסך השיתוף בוחרים את אפליקציית השדכן – והיא כבר תמשיך מכאן.',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return Scaffold(
      appBar: AppBar(title: const Text('ייצוא מוואטסאפ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(
            'איך מייצאים שיחה מ־WhatsApp?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: slate,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'הייצוא נעשה בתוך WhatsApp, ובסוף בוחרים לשתף אותו לכאן.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: slate.withValues(alpha: dark ? 0.22 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: slate,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.schedule_rounded, size: 16, color: slate),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'בקבוצה גדולה הייצוא לוקח רגע — שווה לחכות.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Divider(color: theme.dividerColor.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(
            'כבר יש לך את קובץ הייצוא?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('בחירת קובץ מהמכשיר'),
          ),
        ],
      ),
    );
  }
}
