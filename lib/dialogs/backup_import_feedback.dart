import 'package:flutter/material.dart';
import 'package:shadchan/services/backup_service.dart';

class BackupImportFeedback {
  static Future<void> showResultDialog(
    BuildContext context,
    ImportResult result,
  ) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ייבוא הושלם'),
          content: Text(
            'יובאו: ${result.peopleAdded} אנשים, ${result.matchesAdded} הצעות, ${result.notesAdded} הערות. דולגו: ${result.skipped} רשומות.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        );
      },
    );
  }

  static void showImportError(
    BuildContext context,
    Object error, {
    String fallbackMessage = 'לא הצלחנו לייבא את קובץ הגיבוי',
  }) {
    final String message = error is FormatException
        ? error.message
        : '$fallbackMessage: $error';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 10),
        ),
      );
  }
}
