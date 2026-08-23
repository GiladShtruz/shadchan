import 'package:flutter/material.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/widgets/app_notice.dart';

class BackupImportFeedback {
  static Future<void> showResultDialog(
    BuildContext context,
    ImportResult result,
  ) async {
    AppNotice.show(
      context,
      'ייבוא הושלם — יובאו: ${result.peopleAdded} אנשים, '
      '${result.matchesAdded} הצעות, ${result.notesAdded} הערות. '
      'דולגו: ${result.skipped} רשומות.',
      duration: const Duration(seconds: 6),
    );
  }

  static void showImportError(
    BuildContext context,
    Object error, {
    String fallbackMessage = 'לא הצלחנו לייבא את קובץ הגיבוי',
  }) {
    final String message = error is FormatException
        ? error.message
        : fallbackMessage;
    AppNotice.show(context, message);
  }
}
