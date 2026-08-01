import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/import_file_kind.dart';

/// Asks what an incoming file actually is before reading it.
///
/// The app cannot tell from the file alone — a `.txt` is as often a chat export
/// as a typed list — and guessing wrong is not a small error: the file is read
/// with the wrong instructions and comes back with no people at all, which
/// looks like the feature failing rather than like a wrong answer to a question
/// nobody asked.
abstract final class ImportFileKindDialog {
  /// Returns the chosen kind, or null when the user backs out.
  ///
  /// Skips the question when the file admits only one reading — being asked to
  /// confirm the obvious is its own kind of noise.
  static Future<ImportFileKind?> show(
    BuildContext context,
    String filePath,
  ) async {
    final List<ImportFileKind> options = ImportFileKinds.optionsFor(filePath);
    if (options.length == 1) {
      return options.single;
    }

    return showDialog<ImportFileKind>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _ImportFileKindDialog(filePath: filePath, options: options),
    );
  }
}

class _ImportFileKindDialog extends StatelessWidget {
  const _ImportFileKindDialog({required this.filePath, required this.options});

  final String filePath;
  final List<ImportFileKind> options;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return AlertDialog(
      title: const Text('במה מדובר?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            p.basename(filePath),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (final ImportFileKind kind in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pop(kind),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ImportFileKinds.titleOf(kind),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: slate,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ImportFileKinds.subtitleOf(kind),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
      ],
    );
  }
}
