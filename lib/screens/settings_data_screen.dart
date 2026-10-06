import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/backup_import_feedback.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/excel_export_service.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/community_widgets.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "המאגר והנתונים שלי" — everything that can be done to the database itself,
/// on one screen instead of scattered across four sections of the settings.
///
/// The database itself lives in the account and is the same on every phone
/// signed in to it, so there is nothing here about a backup: what is left is
/// the database's size, and files handed to somebody else.
class SettingsDataScreen extends StatefulWidget {
  const SettingsDataScreen({super.key});

  @override
  State<SettingsDataScreen> createState() => _SettingsDataScreenState();
}

class _SettingsDataScreenState extends State<SettingsDataScreen> {
  bool _isExporting = false;
  bool _isExportingExcel = false;
  bool _isImporting = false;

  bool get _busy => _isExporting || _isExportingExcel || _isImporting;

  @override
  Widget build(BuildContext context) {
    final PersonRepository personRepo = context.watch<PersonRepository>();
    final MatchRepository matchRepo = context.watch<MatchRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('המאגר והנתונים שלי')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SettingsGroup(
              title: 'המאגר שלי',
              children: <Widget>[
                SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'פרטיות והמאגר שלי',
                  onTap: () => context.push('/support/privacy'),
                ),
                // The switch itself rather than a row that opens the page it
                // lives on. Somebody who came to the settings looking for
                // "don't share my activity" should find the thing, not a
                // signpost to it — and it sits directly under the privacy row
                // so the page it belongs to is still one tap away.
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: PrivateModeTile(),
                ),
                SettingsRow(
                  icon: Icons.people_outline,
                  title: 'מספר אנשים במאגר',
                  trailing: _Count(value: personRepo.count),
                ),
                SettingsRow(
                  icon: Icons.favorite_outline,
                  title: 'מספר רעיונות',
                  trailing: _Count(value: matchRepo.count),
                ),
              ],
            ),
            SettingsGroup(
              title: 'ייצוא וייבוא קבצים',
              children: <Widget>[
                SettingsRow(
                  icon: Icons.upload_file,
                  leadingOverride: _isExporting
                      ? const SettingsSpinner()
                      : null,
                  title: 'ייצוא נתונים',
                  enabled: !_busy,
                  trailing: const SizedBox.shrink(),
                  onTap: () => _exportData(personRepo, matchRepo),
                ),
                SettingsRow(
                  icon: Icons.table_chart_outlined,
                  leadingOverride: _isExportingExcel
                      ? const SettingsSpinner()
                      : null,
                  title: 'ייצוא לאקסל',
                  enabled: !_busy,
                  trailing: const SizedBox.shrink(),
                  onTap: () => _exportExcel(personRepo, matchRepo),
                ),
                SettingsRow(
                  icon: Icons.download,
                  leadingOverride: _isImporting
                      ? const SettingsSpinner()
                      : null,
                  title: 'ייבוא נתונים',
                  enabled: !_busy,
                  trailing: const SizedBox.shrink(),
                  onTap: () => _importData(personRepo, matchRepo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Files ----------------------------------------------------------------

  Future<void> _exportData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    setState(() => _isExporting = true);
    // Read before the export runs: the share is anchored to this screen, and
    // iOS refuses a share with no anchor.
    final Rect origin = ShareUtils.originOf(context);
    try {
      final File backupFile = await BackupService.exportData(
        personRepo,
        matchRepo,
      );
      await BackupService.shareBackup(backupFile, origin: origin);
    } catch (_) {
      if (mounted) {
        _say('לא הצלחנו לייצא את הנתונים');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportExcel(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    setState(() => _isExportingExcel = true);
    final Rect origin = ShareUtils.originOf(context);
    try {
      final File excelFile = await ExcelExportService.exportData(
        personRepo,
        matchRepo,
      );
      await ExcelExportService.shareExport(excelFile, origin: origin);
    } catch (_) {
      if (mounted) {
        _say('לא הצלחנו לייצא לאקסל');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingExcel = false);
      }
    }
  }

  Future<void> _importData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    setState(() => _isImporting = true);
    try {
      final FilePickerResult? pickerResult = await FilePicker.platform
          .pickFiles(
            type: FileType.custom,
            allowedExtensions: const <String>['json'],
          );

      final String? selectedPath = pickerResult?.files.single.path;
      if (selectedPath == null || selectedPath.isEmpty) {
        return;
      }

      final ImportResult result = await BackupService.importData(
        File(selectedPath),
        personRepo,
        matchRepo,
      );
      if (!mounted) {
        return;
      }
      await BackupImportFeedback.showResultDialog(context, result);
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      BackupImportFeedback.showImportError(
        context,
        error,
        fallbackMessage: 'לא הצלחנו לייבא את הנתונים',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      BackupImportFeedback.showImportError(
        context,
        Exception(),
        fallbackMessage: 'לא הצלחנו לייבא את הנתונים',
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _say(String message) {
    AppNotice.show(context, message);
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      '$value',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}
