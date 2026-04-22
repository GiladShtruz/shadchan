import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/core/services/backup_service.dart';
import 'package:shadchan/data/repositories/match_repository.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:shadchan/presentation/shared/backup_import_feedback.dart';
import 'package:shadchan/presentation/shared/widgets/section_header.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final PersonRepository personRepo = context.watch<PersonRepository>();
    final MatchRepository matchRepo = context.watch<MatchRepository>();
    final List<Widget> sections = <Widget>[
      const SectionHeader(title: 'גיבוי ושחזור'),
      Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.upload_file),
              title: const Text('ייצוא נתונים'),
              enabled: !_isExporting && !_isImporting,
              onTap: _isExporting || _isImporting
                  ? null
                  : () => _exportData(personRepo, matchRepo),
            ),
            const Divider(height: 1),
            ListTile(
              leading: _isImporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.download),
              title: const Text('ייבוא נתונים'),
              enabled: !_isExporting && !_isImporting,
              onTap: _isExporting || _isImporting
                  ? null
                  : () => _importData(personRepo, matchRepo),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const SectionHeader(title: 'מידע'),
      Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('מדיניות פרטיות'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/privacy-policy'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.people),
              title: Text('מספר אנשים: ${personRepo.count}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: Text('מספר הצעות: ${matchRepo.count}'),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('גרסה: 1.0.0'),
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות'), centerTitle: true),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        itemBuilder: (BuildContext context, int index) => sections[index],
      ),
    );
  }

  Future<void> _exportData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final File backupFile = await BackupService.exportData(
        personRepo,
        matchRepo,
      );
      await BackupService.shareBackup(backupFile);

      if (!mounted) {
        return;
      }

      _showSnackBar('הגיבוי מוכן לשיתוף');
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showSnackBar('לא הצלחנו לייצא את הנתונים');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _importData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    setState(() {
      _isImporting = true;
    });

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
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
