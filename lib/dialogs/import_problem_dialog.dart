import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/utils/app_colors.dart';

/// What the user sees when an import does not work.
///
/// It replaces a snackbar, and the reason is not presentation. An import is a
/// minute of waiting that ends in nothing, and a line that slides away after
/// four seconds gives the person no way to read it twice, no way to copy it and
/// nowhere to go — so the failures got reported as "it doesn't work", from four
/// causes with four different fixes, and the ones that were the app's fault
/// were indistinguishable from the ones that were not.
///
/// So the dialog does two things: it says *which* failure this was and what
/// might be done about it, and it offers to hand the whole thing to the
/// developer. The report is shown in full before it goes anywhere.
abstract final class ImportProblemDialog {
  static Future<void> show(
    BuildContext context, {
    required String message,
    String? hint,
    required String report,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _ImportProblemDialog(message: message, hint: hint, report: report),
    );
  }
}

class _ImportProblemDialog extends StatefulWidget {
  const _ImportProblemDialog({
    required this.message,
    required this.hint,
    required this.report,
  });

  final String message;
  final String? hint;
  final String report;

  @override
  State<_ImportProblemDialog> createState() => _ImportProblemDialogState();
}

class _ImportProblemDialogState extends State<_ImportProblemDialog> {
  bool _showReport = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.report));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('פרטי הבעיה הועתקו')));
  }

  /// Copies the report, then opens the app's own report form with it already
  /// written in.
  ///
  /// It used to open WhatsApp at the developer's number. That is gone: support
  /// has one channel now, and it is the form — which lands in the admin console
  /// with the device, the OS and the version attached, instead of in a chat
  /// thread that has to be triaged by hand. The clipboard copy stays, because
  /// it is the one thing that still works when nothing else does.
  Future<void> _send() async {
    await Clipboard.setData(ClipboardData(text: widget.report));
    if (!mounted) {
      return;
    }
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/support/report', extra: widget.report);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return AlertDialog(
      title: const Text('הייבוא לא הצליח'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.message, style: theme.textTheme.bodyMedium),
            if (widget.hint != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                widget.hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Offered, not hidden behind a "details" nobody opens, and not
            // shown by default either: the person came here to import a file,
            // not to read a diagnostic.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _showReport = !_showReport),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _showReport
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: slate,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'מה יישלח למפתחים?',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: slate,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showReport) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: slate.withValues(alpha: dark ? 0.18 : 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  widget.report,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'אין כאן שמות, הודעות, תמונות או שם הקובץ — רק גדלים, מספרים '
                'וסוג התקלה.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('סגירה'),
        ),
        TextButton(onPressed: _copy, child: const Text('העתקה')),
        FilledButton.icon(
          onPressed: _send,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('שליחת הבעיה למפתחי האפליקציה'),
        ),
      ],
    );
  }
}
