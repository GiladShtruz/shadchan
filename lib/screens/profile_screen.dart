import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/backup_import_feedback.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/cloud_sync_service.dart';
import 'package:shadchan/services/excel_export_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/person_photo_editor.dart';
import 'package:shadchan/widgets/section_header.dart';

/// "הפרופיל שלי" — the matchmaker's own page, and the one place the app's
/// settings live. The home screen used to carry a gear icon; it now carries the
/// user's photo, and everything that was behind the gear is here, under the
/// person it belongs to.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isExporting = false;

  /// Whether the personal card preview is showing its full text.
  bool _personalCardExpanded = false;
  bool _isExportingExcel = false;
  bool _isImporting = false;

  bool get _busy => _isExporting || _isExportingExcel || _isImporting;

  @override
  Widget build(BuildContext context) {
    final PersonRepository personRepo = context.watch<PersonRepository>();
    final MatchRepository matchRepo = context.watch<MatchRepository>();
    final ThemeModeProvider themeModeProvider = context
        .watch<ThemeModeProvider>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final AccountProvider account = context.watch<AccountProvider>();
    final SyncProvider sync = context.watch<SyncProvider>();

    final List<Widget> sections = <Widget>[
      _ProfileHeader(profile: profile, onEditPhoto: () => _editPhoto(profile)),
      const SizedBox(height: 6),
      // The answer was already given during sign-up. All that is left here is a
      // quiet way back to it if it ever changes — not a section of its own.
      _PersonalStatusLine(
        profile: profile,
        onChangeRequested: () => _changePersonalStatus(profile),
      ),
      const SizedBox(height: 18),
      if (profile.isSingle) ...<Widget>[
        _PersonalCardCard(
          profile: profile,
          expanded: _personalCardExpanded,
          onToggleExpanded: () =>
              setState(() => _personalCardExpanded = !_personalCardExpanded),
          onEditCard: () => _editPersonalCard(profile),
          onShareCard: () => _sharePersonalCard(profile),
        ),
        const SizedBox(height: 24),
      ],
      const SectionHeader(title: 'תצוגה'),
      _ThemeCard(themeModeProvider: themeModeProvider),
      const SizedBox(height: 24),
      const SectionHeader(title: 'המאגר שלי'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.style_outlined),
          title: const Text('סגנונות דתיים'),
          subtitle: const Text('אילו סגנונות יופיעו באפליקציה'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/profile/religious-levels'),
        ),
      ),
      const SizedBox(height: 24),
      // Tips are read on the home screen and written here. The admin entry
      // only appears for the reviewing account; the rules refuse the queue to
      // anyone else regardless of what the app chooses to draw.
      const SectionHeader(title: 'טיפים לשדכנים'),
      Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('הוספת טיפ'),
              subtitle: const Text('טיפ משלך, שיוצג לשדכנים אחרים לאחר אישור'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/tips'),
            ),
            if (account.isTipsAdmin) ...<Widget>[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('אישור טיפים'),
                subtitle: const Text('טיפים שנשלחו וממתינים לבדיקה'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/tips-review'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      const SectionHeader(title: 'החשבון שלי'),
      _AccountCard(
        account: account,
        onSignIn: () => _signIn(account, sync, personRepo, matchRepo, profile),
        onSignOut: () => _confirmSignOut(account, sync),
      ),
      const SizedBox(height: 24),
      const SectionHeader(title: 'גיבוי בענן'),
      _CloudBackupCard(
        account: account,
        sync: sync,
        onBackUpNow: () => _backUpNow(sync, personRepo, matchRepo, profile),
        onRestore: () => _confirmRestore(sync, personRepo, matchRepo, profile),
      ),
      const SizedBox(height: 24),
      const SectionHeader(title: 'גיבוי לקובץ'),
      Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: _isExporting
                  ? const _TileSpinner()
                  : const Icon(Icons.upload_file),
              title: const Text('ייצוא נתונים'),
              enabled: !_busy,
              onTap: _busy ? null : () => _exportData(personRepo, matchRepo),
            ),
            const Divider(height: 1),
            ListTile(
              leading: _isExportingExcel
                  ? const _TileSpinner()
                  : const Icon(Icons.table_chart_outlined),
              title: const Text('ייצוא לאקסל'),
              enabled: !_busy,
              onTap: _busy ? null : () => _exportExcel(personRepo, matchRepo),
            ),
            const Divider(height: 1),
            ListTile(
              leading: _isImporting
                  ? const _TileSpinner()
                  : const Icon(Icons.download),
              title: const Text('ייבוא נתונים'),
              enabled: !_busy,
              onTap: _busy ? null : () => _importData(personRepo, matchRepo),
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
      appBar: AppBar(title: const Text('הפרופיל שלי'), centerTitle: true),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sections.length,
          itemBuilder: (BuildContext context, int index) => sections[index],
        ),
      ),
    );
  }

  // --- The photo ----------------------------------------------------------

  Future<void> _editPhoto(UserProfileProvider profile) async {
    final bool hasPhoto = profile.photoPath != null;
    if (!hasPhoto) {
      await _pickPhoto(profile);
      return;
    }

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('החלפת התמונה'),
                onTap: () => Navigator.of(sheetContext).pop('replace'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: const Text('הסרת התמונה'),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }
    if (choice == 'remove') {
      await profile.setPhotoPath(null);
      return;
    }
    await _pickPhoto(profile);
  }

  Future<void> _pickPhoto(UserProfileProvider profile) async {
    final String? path = await PhotoPickerService.pickSinglePhoto(context);
    if (path == null) {
      return;
    }
    await profile.setPhotoPath(path);
  }

  // --- Personal status ----------------------------------------------------

  /// Offered from the quiet line under the name. Changing to married hides the
  /// personal card rather than deleting it, so nothing is lost by answering.
  Future<void> _changePersonalStatus(UserProfileProvider profile) async {
    final Gender? gender = profile.gender;
    final bool? isSingle = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.favorite_border_rounded),
                title: Text('{רווק|רווקה}'.forGender(gender)),
                trailing: profile.isSingle ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text('{נשוי|נשואה}'.forGender(gender)),
                trailing: profile.isSingle ? null : const Icon(Icons.check),
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        );
      },
    );
    if (isSingle == null || isSingle == profile.isSingle) {
      return;
    }
    await profile.setIsSingle(isSingle);
  }

  // --- The personal card --------------------------------------------------

  Future<void> _editPersonalCard(UserProfileProvider profile) async {
    final List<String> initialPhotos = profile.personalCardPhotos;
    final _PersonalCardDraft? draft =
        await showModalBottomSheet<_PersonalCardDraft>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            return _PersonalCardEditorSheet(
              initialText: profile.personalCard ?? '',
              initialPhotos: initialPhotos,
            );
          },
        );
    if (draft == null) {
      return;
    }
    await profile.setPersonalCardContent(
      text: draft.text,
      photoPaths: draft.photos,
    );
    PhotoPickerService.deletePhotoFiles(
      initialPhotos.where((String path) => !draft.photos.contains(path)),
    );
  }

  Future<void> _sharePersonalCard(UserProfileProvider profile) async {
    final String card = profile.personalCard ?? '';
    final List<String> photos = profile.personalCardPhotos;
    if (card.isEmpty && photos.isEmpty) {
      return;
    }
    await ShareUtils.shareText(card, photoPaths: photos);
  }

  // --- The Google account -------------------------------------------------

  Future<void> _signIn(
    AccountProvider account,
    SyncProvider sync,
    PersonRepository personRepo,
    MatchRepository matchRepo,
    UserProfileProvider userProfile,
  ) async {
    final AccountSignInResult result = await account.signIn();
    if (!mounted) {
      return;
    }
    if (result.outcome == AccountSignInOutcome.failure) {
      _showSnackBar(result.message!);
      return;
    }
    if (result.outcome == AccountSignInOutcome.success) {
      // The first backup runs now rather than at the next app open, so the
      // section directly below stops saying "עדיין לא גובה" while the person
      // who just connected the account is still looking at it.
      unawaited(
        sync.sync(
          personRepo: personRepo,
          matchRepo: matchRepo,
          profile: userProfile,
        ),
      );
    }
  }

  /// Asks first, and says what is actually lost. Signing out is not
  /// destructive here — the database is in Hive either way — and saying so is
  /// the difference between a confirmation and a scare.
  Future<void> _confirmSignOut(
    AccountProvider account,
    SyncProvider sync,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('יציאה מהחשבון?'),
          content: const Text(
            'המאגר שלך שמור במכשיר וימשיך לעבוד כרגיל. רק החיבור לחשבון '
            'Google יתנתק.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('יציאה'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await account.signOut();
    // The ledger describes what is in *that* account's cloud tree. Signing
    // back into a different one and diffing against it would leave the new
    // account's backup missing everything the old one happened to hold.
    await sync.forget();
  }

  // --- The cloud backup ---------------------------------------------------

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
    // Success is silent — the card's own "גובה לפני רגע" line already says it,
    // and a snackbar for every tap of a button whose result is visible above it
    // is the kind of confirmation this app removed everywhere else.
    final String? message = switch (result) {
      CloudSyncResult.success || CloudSyncResult.upToDate => null,
      CloudSyncResult.skipped => 'צריך להתחבר לחשבון Google כדי לגבות',
      CloudSyncResult.notPermitted => 'אין הרשאה לגבות. יש לפנות לתמיכה.',
      CloudSyncResult.empty || CloudSyncResult.failed =>
        'הגיבוי לא הושלם. יש לוודא חיבור לאינטרנט ולנסות שוב.',
    };
    if (message != null) {
      _showSnackBar(message);
    }
  }

  /// Restore asks first, because it is the one action here that changes the
  /// database. What it does *not* do is overwrite: the merge is additive and
  /// skips ids that already exist, and the dialog says so — someone restoring
  /// onto a phone that already has people needs to know their work is not
  /// about to be replaced.
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
    _showSnackBar(switch (outcome.status) {
      CloudSyncResult.empty => 'אין עדיין גיבוי בענן',
      CloudSyncResult.skipped => 'צריך להתחבר לחשבון Google כדי לשחזר',
      CloudSyncResult.notPermitted => 'אין הרשאה לשחזר. יש לפנות לתמיכה.',
      _ => 'השחזור לא הושלם. יש לוודא חיבור לאינטרנט ולנסות שוב.',
    });
  }

  // --- Backup and restore -------------------------------------------------

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
      if (!mounted) {
        return;
      }
      _showSnackBar('לא הצלחנו לייצא את הנתונים');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
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
      if (!mounted) {
        return;
      }
      _showSnackBar('לא הצלחנו לייצא לאקסל');
    } finally {
      if (mounted) {
        setState(() => _isExportingExcel = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The Google account: connected, or an invitation to connect one.
///
/// Written as three plain states rather than one clever tile, because the
/// unavailable state is the one that has to explain itself — a device with no
/// network gets a sentence saying so instead of a button that fails when
/// tapped.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onSignIn,
    required this.onSignOut,
  });

  final AccountProvider account;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (account.isSignedIn) {
      final String? email = account.email;
      return Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: _AccountAvatar(
                photoUrl: account.photoUrl,
                displayName: account.displayName ?? email,
              ),
              title: Text(
                account.displayName ?? email ?? 'מחובר',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: email == null
                  ? null
                  : Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: account.isBusy
                  ? const _TileSpinner()
                  : Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'יציאה מהחשבון',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              enabled: !account.isBusy,
              onTap: account.isBusy ? null : onSignOut,
            ),
          ],
        ),
      );
    }

    if (!account.isFirebaseReady) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: const Text('החיבור לחשבון אינו זמין כרגע'),
          subtitle: const Text('יש לוודא חיבור לאינטרנט ולנסות שוב מאוחר יותר'),
          enabled: false,
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: account.isBusy
            ? const _TileSpinner()
            : const FaIcon(FontAwesomeIcons.google, size: 20),
        title: const Text('התחברות עם Google'),
        subtitle: const Text('כדי שנוכל לגבות את המאגר ולשחזר אותו במכשיר חדש'),
        enabled: !account.isBusy,
        onTap: account.isBusy ? null : onSignIn,
      ),
    );
  }
}

/// The cloud backup: whether it is on, when it last ran, and the two things
/// that can be done to it.
///
/// Signed out, it is a single explanatory line and nothing else. Offering
/// `גיבוי עכשיו` to someone with no account would be a button whose only
/// possible outcome is an error, and the account section directly above is
/// already the answer.
class _CloudBackupCard extends StatelessWidget {
  const _CloudBackupCard({
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
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: const Text('הגיבוי בענן כבוי'),
          subtitle: const Text(
            'אחרי התחברות לחשבון Google המאגר יגובה אוטומטית, ואפשר יהיה '
            'לשחזר אותו במכשיר חדש',
          ),
        ),
      );
    }

    final bool busy = sync.isSyncing || sync.isRestoring;

    return Card(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: sync.isSyncing
                ? const _TileSpinner()
                : Icon(
                    Icons.cloud_done_outlined,
                    color: theme.colorScheme.primary,
                  ),
            title: const Text('גיבוי אוטומטי פעיל'),
            subtitle: Text(_statusLine(sync)),
            trailing: busy
                ? null
                : IconButton(
                    onPressed: onBackUpNow,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'גיבוי עכשיו',
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: sync.isRestoring
                ? const _TileSpinner()
                : const Icon(Icons.cloud_download_outlined),
            title: const Text('שחזור מהענן'),
            subtitle: const Text('הוספת הכרטיסים מהגיבוי למאגר שבמכשיר'),
            enabled: !busy,
            onTap: busy ? null : onRestore,
          ),
        ],
      ),
    );
  }

  /// Says when, not whether. A failed attempt still reports the last good
  /// backup alongside it, because "נסינו ולא הצלחנו" without a date leaves
  /// someone unable to tell a hiccup from a month of silence.
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

/// The Google profile picture, falling back to the initial and then to a
/// generic icon — the photo is a remote URL and may simply not load.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.photoUrl, required this.displayName});

  final String? photoUrl;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial = (displayName ?? '').trim().isEmpty
        ? ''
        : displayName!.trim().characters.first;

    return CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
      child: initial.isEmpty
          ? Icon(
              Icons.person_outline,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            )
          : Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
    );
  }
}

class _TileSpinner extends StatelessWidget {
  const _TileSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}

/// The photo, the name and one gendered line of welcome.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onEditPhoto});

  final UserProfileProvider profile;
  final VoidCallback onEditPhoto;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = profile.gender;

    return Column(
      children: <Widget>[
        UserProfileAvatar(
          photoPath: profile.photoPath,
          gender: gender,
          radius: 46,
          onTap: onEditPhoto,
          showEditBadge: true,
        ),
        const SizedBox(height: 12),
        Text(
          profile.name ?? '{שדכן|שדכנית}'.forGender(gender),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile.photoPath == null
              ? 'אפשר להוסיף תמונה — היא תופיע בראש עמוד הבית'
              : 'תודה {שאתה חושב|שאת חושבת} על החברים שלך'.forGender(gender),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The personal status, as small as it can be while still being changeable.
///
/// Whether the matchmaker is single was settled during sign-up; repeating it as
/// a titled card on the profile gave a one-off answer permanent furniture.
class _PersonalStatusLine extends StatelessWidget {
  const _PersonalStatusLine({
    required this.profile,
    required this.onChangeRequested,
  });

  final UserProfileProvider profile;
  final VoidCallback onChangeRequested;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = profile.gender;
    final String label = profile.isSingle
        ? '{רווק|רווקה}'.forGender(gender)
        : '{נשוי|נשואה}'.forGender(gender);

    return Center(
      child: TextButton(
        onPressed: onChangeRequested,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          textStyle: theme.textTheme.bodySmall,
          visualDensity: VisualDensity.compact,
        ),
        child: Text('$label · שינוי'),
      ),
    );
  }
}

/// The matchmaker's own card, at the top of their page and only when they are
/// single.
///
/// It is a preview, not an editor: the text alone, four lines of it, with the
/// two things anyone ever wants to do with it — change it, send it — as icons
/// in the corner. Anything more would make a card that has to be scrolled past
/// on the way to the settings underneath.
class _PersonalCardCard extends StatelessWidget {
  const _PersonalCardCard({
    required this.profile,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEditCard,
    required this.onShareCard,
  });

  final UserProfileProvider profile;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEditCard;
  final VoidCallback onShareCard;

  /// Roughly how many lines fit in the collapsed preview.
  static const int _previewLines = 4;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String card = (profile.personalCard ?? '').trim();
    final bool hasCard =
        card.isNotEmpty || profile.personalCardPhotos.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'הכרטיס שלך',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasCard) ...<Widget>[
                  IconButton(
                    onPressed: onEditCard,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'עריכת הכרטיס',
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  IconButton(
                    onPressed: onShareCard,
                    icon: const Icon(Icons.ios_share, size: 20),
                    tooltip: 'שיתוף הכרטיס',
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            if (!hasCard) ...<Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(
                  'שמור את הכרטיס שלך כאן כדי שתוכל לשתף אותו בקלות בכל פעם '
                  'שתצטרך.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onEditCard,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('יצירת הכרטיס'),
                  ),
                ),
              ),
            ] else ...<Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(
                  card.isEmpty ? 'הכרטיס שלך שמור כאן.' : card,
                  maxLines: expanded ? null : _previewLines,
                  overflow: expanded
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              if (_isLong(card))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: onToggleExpanded,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: theme.textTheme.bodySmall,
                    ),
                    child: Text(expanded ? 'הצג פחות' : 'הצג עוד'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Cheap stand-in for "does not fit in the preview": either it already has
  /// more lines than the preview shows, or it is long enough to wrap past it.
  static bool _isLong(String card) {
    return '\n'.allMatches(card).length >= _previewLines || card.length > 180;
  }
}

class _PersonalCardDraft {
  const _PersonalCardDraft({required this.text, required this.photos});

  final String text;
  final List<String> photos;
}

class _PersonalCardEditorSheet extends StatefulWidget {
  const _PersonalCardEditorSheet({
    required this.initialText,
    required this.initialPhotos,
  });

  final String initialText;
  final List<String> initialPhotos;

  @override
  State<_PersonalCardEditorSheet> createState() =>
      _PersonalCardEditorSheetState();
}

class _PersonalCardEditorSheetState extends State<_PersonalCardEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final List<String> _photos = List<String>.of(widget.initialPhotos);
  final Set<String> _newPhotos = <String>{};
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    if (!_submitted) {
      PhotoPickerService.deletePhotoFiles(_newPhotos);
    }
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final List<String> added = await PhotoPickerService.pickPhotos(
      context,
      personId: 'my_personal_card',
    );
    if (!mounted || added.isEmpty) {
      return;
    }
    setState(() {
      _photos.addAll(added);
      _newPhotos.addAll(added);
    });
  }

  void _setPrimary(int index) {
    if (index <= 0 || index >= _photos.length) {
      return;
    }
    setState(() {
      final String path = _photos.removeAt(index);
      _photos.insert(0, path);
    });
  }

  void _removePhoto(int index) {
    final String removed = _photos.removeAt(index);
    if (_newPhotos.remove(removed)) {
      PhotoPickerService.deletePhotoFiles(<String>[removed]);
    }
    setState(() {});
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final String path = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, path);
    });
  }

  void _save() {
    _submitted = true;
    Navigator.of(context).pop(
      _PersonalCardDraft(
        text: _controller.text.trim(),
        photos: List<String>.unmodifiable(_photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'עריכת הכרטיס האישי',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'אפשר לשמור טקסט חופשי, להוסיף כמה תמונות שרוצים ולסדר אותן.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: <Widget>[
                  TextField(
                    controller: _controller,
                    minLines: 6,
                    maxLines: 12,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'הטקסט שלי',
                      hintText: 'אפשר לכתוב או להדביק כאן את הכרטיס שלך',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PersonPhotoEditor(
                    photoPaths: _photos,
                    onAddPhoto: _addPhotos,
                    onSetPrimary: _setPrimary,
                    onRemove: _removePhoto,
                    onReorder: _reorderPhotos,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('שמירת הכרטיס'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The theme picker, moved here from the old settings screen unchanged.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.themeModeProvider});

  final ThemeModeProvider themeModeProvider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The mode icons ride along with the title instead of inside the
            // segments, which had no room for them; the active one lights up
            // so the row still says which mode is on.
            Row(
              children: <Widget>[
                Text('ערכת נושא', style: theme.textTheme.titleMedium),
                const Spacer(),
                for (final (ThemeMode mode, IconData icon) entry
                    in <(ThemeMode, IconData)>[
                      (ThemeMode.system, Icons.brightness_auto_outlined),
                      (ThemeMode.light, Icons.light_mode_outlined),
                      (ThemeMode.dark, Icons.dark_mode_outlined),
                    ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 10),
                    child: Icon(
                      entry.$2,
                      size: 20,
                      color: themeModeProvider.themeMode == entry.$1
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.45,
                            ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              // A third of the card is not enough for an icon, a checkmark
              // and 'אוטומטי' side by side - that is what pushed the last
              // letter onto a second line. Labels only, and a scale-down
              // guard so a large system font shrinks the text instead of
              // wrapping or clipping it.
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('אוטומטי', maxLines: 1, softWrap: false),
                  ),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('בהיר', maxLines: 1, softWrap: false),
                  ),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('כהה', maxLines: 1, softWrap: false),
                  ),
                ),
              ],
              selected: <ThemeMode>{themeModeProvider.themeMode},
              onSelectionChanged: (Set<ThemeMode> selection) {
                themeModeProvider.setThemeMode(selection.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The matchmaker's own photo, drawn the same way wherever it appears: the home
/// app bar, and the head of this screen. Falls back to the initial of their
/// name, and to a plain person icon when there is no name either.
class UserProfileAvatar extends StatelessWidget {
  const UserProfileAvatar({
    super.key,
    required this.photoPath,
    required this.gender,
    this.name,
    this.radius = 16,
    this.onTap,
    this.showEditBadge = false,
  });

  final String? photoPath;
  final Gender? gender;
  final String? name;
  final double radius;
  final VoidCallback? onTap;

  /// Draws the small camera badge that says the photo can be added or changed.
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? path = photoPath;
    final bool hasPhoto = path != null && File(path).existsSync();
    final String initial = (name ?? '').trim().isEmpty
        ? ''
        : name!.trim().characters.first;

    // Without a photo the circle wears the same gender tint every other avatar
    // in the app does, so the matchmaker's own face reads as one of them.
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(
      gender ?? Gender.unknown,
      dark: dark,
    );

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.genderSurface(
        gender ?? Gender.unknown,
        dark: dark,
      ),
      foregroundImage: hasPhoto ? FileImage(File(path)) : null,
      child: hasPhoto
          ? null
          : (initial.isNotEmpty
                ? Text(
                    initial,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: radius * 0.8,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  )
                : Icon(Icons.person_outline, size: radius, color: accent)),
    );

    if (showEditBadge) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(
                hasPhoto ? Icons.edit : Icons.add_a_photo_outlined,
                size: 14,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) {
      return avatar;
    }

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }
}
