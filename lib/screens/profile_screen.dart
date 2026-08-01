import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/backup_import_feedback.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/excel_export_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/share_utils.dart';
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

    final List<Widget> sections = <Widget>[
      _ProfileHeader(profile: profile, onEditPhoto: () => _editPhoto(profile)),
      const SizedBox(height: 24),
      const SectionHeader(title: 'הכרטיס האישי שלי'),
      _SingleCard(
        profile: profile,
        onToggle: (bool value) => profile.setIsSingle(value),
        onEditCard: () => _editPersonalCard(profile),
        onShareCard: () => _sharePersonalCard(profile),
      ),
      const SizedBox(height: 24),
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
      const SectionHeader(title: 'הודעות'),
      Card(
        child: ListTile(
          leading: const FaIcon(FontAwesomeIcons.whatsapp),
          title: const Text('הודעה לבקשת פרטים בוואטסאפ'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/profile/whatsapp-message'),
        ),
      ),
      const SizedBox(height: 24),
      const SectionHeader(title: 'גיבוי ושחזור'),
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

  // --- The personal card --------------------------------------------------

  Future<void> _editPersonalCard(UserProfileProvider profile) async {
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _PersonalCardDialog(initialText: profile.personalCard ?? '');
      },
    );
    if (text == null) {
      return;
    }
    await profile.setPersonalCard(text);
  }

  Future<void> _sharePersonalCard(UserProfileProvider profile) async {
    final String card = profile.personalCard ?? '';
    if (card.isEmpty) {
      return;
    }
    await ShareUtils.shareText(card, photoPath: profile.photoPath);
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

/// "רווק/ה? שמור כאן את הכרטיס האישי שלך" — off unless the matchmaker says so,
/// and only then does the card area appear.
class _SingleCard extends StatelessWidget {
  const _SingleCard({
    required this.profile,
    required this.onToggle,
    required this.onEditCard,
    required this.onShareCard,
  });

  final UserProfileProvider profile;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditCard;
  final VoidCallback onShareCard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = profile.gender;
    final String? card = profile.personalCard;

    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile(
            value: profile.isSingle,
            onChanged: onToggle,
            secondary: const Icon(Icons.favorite_border),
            title: Text('גם אני {רווק|רווקה}'.forGender(gender)),
            subtitle: Text(
              'אני {מחפש|מחפשת} גם לעצמי'.forGender(gender),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (profile.isSingle) ...<Widget>[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '{רווק|רווקה}? {שמור|שמרי} כאן את הכרטיס האישי שלך '
                            '{ושתף|ושתפי} אותו בקלות בעת הצורך.'
                        .forGender(gender),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  if (card != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        card,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: onEditCard,
                        icon: Icon(
                          card == null ? Icons.add : Icons.edit_outlined,
                          size: 18,
                        ),
                        label: Text(
                          card == null ? 'הוספת הכרטיס שלי' : 'עריכת הכרטיס',
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (card != null)
                        TextButton.icon(
                          onPressed: onShareCard,
                          icon: const Icon(Icons.ios_share, size: 18),
                          label: const Text('שיתוף'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonalCardDialog extends StatefulWidget {
  const _PersonalCardDialog({required this.initialText});

  final String initialText;

  @override
  State<_PersonalCardDialog> createState() => _PersonalCardDialogState();
}

class _PersonalCardDialogState extends State<_PersonalCardDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הכרטיס האישי שלי'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 10,
        minLines: 5,
        decoration: const InputDecoration(
          hintText: 'הדבק כאן את הכרטיס שלך',
          alignLabelWithHint: true,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('שמירה'),
        ),
      ],
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
