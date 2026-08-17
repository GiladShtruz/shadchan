import 'package:flutter/material.dart';

/// The app's one yes/no dialog, used everywhere something is about to be
/// deleted, closed or committed.
///
/// The confirming answer is a *filled* button rather than a second bit of plain
/// text. Two identical text buttons side by side make the reader work out which
/// one is the action every single time, and this dialog is the last thing
/// between a matchmaker and a deleted contact — the destructive variant says so
/// in the app's error colour instead of relying on the word alone.
abstract final class ConfirmDialog {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'אישור',
    String cancelText = 'ביטול',
    bool isDestructive = false,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);

        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelText),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: isDestructive
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    )
                  : null,
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
