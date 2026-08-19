import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/backup_import_feedback.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/cloud_sync_service.dart';
import 'package:shadchan/services/excel_export_service.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "המאגר והנתונים שלי" — everything that can be done to the database itself,
/// on one screen instead of scattered across four sections of the settings.
///
/// Ordered by how far the data travels: what is on this phone, then the cloud
/// copy, then a file handed to somebody else. Import sits at the bottom with
/// export because they are the two halves of the same idea, even though one of
/// them writes.
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
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final AccountProvider account = context.watch<AccountProvider>();
    final SyncProvider sync = context.watch<SyncProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('המאגר והנתונים שלי'),
        centerTitle: true,
      ),
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
                SettingsRow(
                  icon: Icons.people_outline,
                  title: 'מספר אנשים במאגר',
                  trailing: _Count(value: personRepo.count),
                ),
                SettingsRow(
                  icon: Icons.favorite_outline,
                  title: 'מספר הצעות',
                  trailing: _Count(value: matchRepo.count),
                ),
              ],
            ),
            _CloudGroup(
              account: account,
              sync: sync,
              onBackUpNow: () =>
                  _backUpNow(sync, personRepo, matchRepo, profile),
              onRestore: () =>
                  _confirmRestore(sync, personRepo, matchRepo, profile),
            ),
            SettingsGroup(
              title: 'גיבוי לקובץ',
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

  // --- The cloud ------------------------------------------------------------

  Future<void> _backUpNow(
    SyncProvider sync,
    PersonRepository personRepo,
    MatchRepository matchRepo,
    UserProfileProvider profile,
  ) async {
    final CloudSyncResult result = await sync.sync(
      personRepo: personRepo,
      matchRepo: matchRepo,
      profile: profile,
    );
    if (!mounted) {
      return;
    }
    // Success is silent — the row's own "גובה לפני רגע" line already says it,
    // and a message for every tap of a button whose result is visible above it
    // is the kind of confirmation this app removed everywhere else.
    final String? message = switch (result) {
      CloudSyncResult.success || CloudSyncResult.upToDate => null,
      CloudSyncResult.skipped => 'צריך להתחבר לחשבון כדי לגבות',
      CloudSyncResult.notPermitted => 'אין הרשאה לגבות. יש לפנות לתמיכה.',
      CloudSyncResult.empty || CloudSyncResult.failed =>
        'הגיבוי לא הושלם. יש לוודא חיבור לאינטרנט ולנסות שוב.',
    };
    if (message != null) {
      _say(message);
    }
  }

  /// Restore asks first, because it is the one action here that changes the
  /// database. What it does *not* do is overwrite: the merge is additive and
  /// skips ids that already exist, and the dialog says so — someone restoring
  /// onto a phone that already has people needs to know their work is not about
  /// to be replaced.
  Future<void> _confirmRestore(
    SyncProvider sync,
    PersonRepository personRepo,
    MatchRepository matchRepo,
    UserProfileProvider profile,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('שחזור מהענן?'),
          content: const Text(
            'נוסיף למאגר שבמכשיר את כל מי שנמצא בגיבוי ועדיין לא אצלך, וגם '
            'נשלים פרטים חסרים בפרופיל שלך. כרטיסים ופרטים שכבר קיימים כאן '
            'יישארו בדיוק כפי שהם.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('שחזור'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    final CloudRestoreOutcome outcome = await sync.restore(
      personRepo: personRepo,
      matchRepo: matchRepo,
      profile: profile,
    );
    if (!mounted) {
      return;
    }

    final ImportResult? result = outcome.result;
    if (result != null) {
      await BackupImportFeedback.showResultDialog(context, result);
      return;
    }
    _say(switch (outcome.status) {
      CloudSyncResult.empty => 'אין עדיין גיבוי בענן',
      CloudSyncResult.skipped => 'צריך להתחבר לחשבון כדי לשחזר',
      CloudSyncResult.notPermitted => 'אין הרשאה לשחזר. יש לפנות לתמיכה.',
      _ => 'השחזור לא הושלם. יש לוודא חיבור לאינטרנט ולנסות שוב.',
    });
  }

  // --- Files ----------------------------------------------------------------

  Future<void> _exportData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    setState(() => _isExporting = true);
    try {
      final File backupFile = await BackupService.exportData(
        personRepo,
        matchRepo,
      );
      await BackupService.shareBackup(backupFile);
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
    try {
      final File excelFile = await ExcelExportService.exportData(
        personRepo,
        matchRepo,
      );
      await ExcelExportService.shareExport(excelFile);
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The cloud backup, or the invitation to make one possible.
///
/// **Signed out, this is not a disabled feature — it is the clearest reason in
/// the app to connect an account.** So it says what an account buys and offers
/// the button, rather than drawing a greyed-out "גיבוי עכשיו" whose only
/// possible outcome is an error.
class _CloudGroup extends StatelessWidget {
  const _CloudGroup({
    required this.account,
    required this.sync,
    required this.onBackUpNow,
    required this.onRestore,
  });

  final AccountProvider account;
  final SyncProvider sync;
  final VoidCallback onBackUpNow;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!account.isSignedIn) {
      return SettingsGroup(
        title: 'גיבוי בענן',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'הגיבוי בענן כבוי',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'התחברות מאפשרת לשמור את המאגר בענן, לשחזר אותו במכשיר חדש '
                  'ולסנכרן אותו בין מכשירים.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: () => context.push('/sign-in'),
                    child: const Text('התחברות וגיבוי הנתונים'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final bool busy = sync.isSyncing || sync.isRestoring;

    return SettingsGroup(
      title: 'גיבוי בענן',
      children: <Widget>[
        SettingsRow(
          icon: Icons.cloud_done_outlined,
          leadingOverride: sync.isSyncing ? const SettingsSpinner() : null,
          title: 'גיבוי אוטומטי פעיל',
          subtitle: _statusLine(sync),
          trailing: busy
              ? null
              : IconButton(
                  onPressed: onBackUpNow,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'גיבוי עכשיו',
                ),
        ),
        SettingsRow(
          icon: Icons.cloud_download_outlined,
          leadingOverride: sync.isRestoring ? const SettingsSpinner() : null,
          title: 'שחזור מהענן',
          subtitle: 'הוספת הכרטיסים מהגיבוי למאגר שבמכשיר',
          enabled: !busy,
          onTap: onRestore,
        ),
      ],
    );
  }

  /// Says when, not whether. A failed attempt still reports the last good
  /// backup alongside it, because "נסינו ולא הצלחנו" without a date leaves
  /// somebody unable to tell a hiccup from a month of silence.
  static String _statusLine(SyncProvider sync) {
    if (sync.isSyncing) {
      return 'מגבה עכשיו…';
    }
    final DateTime? at = sync.lastSyncedAt;
    final String when = at == null ? 'עדיין לא גובה' : 'גובה ${_relative(at)}';
    return switch (sync.lastResult) {
      CloudSyncResult.failed ||
      CloudSyncResult.notPermitted => '$when · הניסיון האחרון נכשל',
      _ => when,
    };
  }

  static String _relative(DateTime at) {
    final Duration ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) {
      return 'לפני רגע';
    }
    if (ago.inHours < 1) {
      return 'לפני ${ago.inMinutes} דקות';
    }
    if (ago.inHours < 24) {
      return ago.inHours == 1 ? 'לפני שעה' : 'לפני ${ago.inHours} שעות';
    }
    final int days = ago.inDays;
    if (days == 1) {
      return 'אתמול';
    }
    if (days < 30) {
      return 'לפני $days ימים';
    }
    return 'ב-${DateFormat('d.M.yyyy').format(at)}';
  }
}

/// A figure at the end of a row, for the two rows that are facts rather than
/// actions.
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
