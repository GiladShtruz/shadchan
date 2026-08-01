import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/import_file_kind_dialog.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/screens/ai_import_review_screen.dart';
import 'package:shadchan/utils/import_file_kind.dart';
import 'package:shadchan/services/ai_import_runner.dart';
import 'package:shadchan/services/excel_import_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The ways a batch of contacts can be read by the AI. Each is only a different
/// way of getting text in front of the model — they all end at the same parsed
/// people and the same review step.
enum AiImportSource { excel, whatsapp, pastedText, camera, gallery }

/// The entry page behind "היעזרו ב‑AI להוספה".
///
/// Sources land here one at a time; the ones that are not built yet are shown
/// disabled rather than hidden, so the page reads as a finished menu with work
/// still coming instead of growing new buttons each release.
class AiImportScreen extends StatefulWidget {
  const AiImportScreen({super.key, this.incomingFilePath});

  /// A file handed to the app from outside — shared to it, or opened with it.
  /// When set, the screen asks what the file is and reads it straight away
  /// instead of waiting for the user to pick one they already chose.
  final String? incomingFilePath;

  /// The sources that are wired to a parser. The rest render disabled.
  static const Set<AiImportSource> _available = <AiImportSource>{
    AiImportSource.excel,
    AiImportSource.whatsapp,
  };

  @override
  State<AiImportScreen> createState() => _AiImportScreenState();
}

class _AiImportScreenState extends State<AiImportScreen> {
  bool _isWorking = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // First point in the app that needs Firebase, so this is where it comes
    // up. The cards enable themselves through the listenable when it lands.
    unawaited(FirebaseBootstrap.ensureReady());

    final String? incoming = widget.incomingFilePath;
    if (incoming != null && ImportFileKinds.isSupported(incoming)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startIncoming(incoming));
      });
    }
  }

  /// Handles a file that arrived from outside the app.
  ///
  /// The kind has to be asked rather than assumed: the same `.txt` can be a
  /// chat export or a typed list, and reading one as the other returns nothing
  /// at all, which reads as the feature being broken.
  Future<void> _startIncoming(String path) async {
    final ImportFileKind? kind = await ImportFileKindDialog.show(context, path);
    if (kind == null || !mounted) {
      return;
    }
    await _run(
      path,
      kind == ImportFileKind.excel
          ? AiImportSource.excel
          : AiImportSource.whatsapp,
    );
  }

  Future<void> _start(AiImportSource source) async {
    if (_isWorking) {
      return;
    }

    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: source == AiImportSource.excel
          ? const <String>['xlsx', 'xlsm']
          : const <String>['zip', 'txt'],
    );
    final String? path = picked?.files.single.path;
    if (path == null || path.isEmpty || !mounted) {
      return;
    }
    await _run(path, source);
  }

  Future<void> _run(String path, AiImportSource source) async {
    if (_isWorking) {
      return;
    }

    setState(() {
      _isWorking = true;
      _status = 'קורא את הקובץ…';
    });

    try {
      void report(int done, int total) {
        if (mounted) {
          setState(() => _status = 'קורא אנשים… $done מתוך $total');
        }
      }

      final File file = File(path);
      debugPrint(
        'AI_IMPORT start source=$source path=$path '
        'exists=${file.existsSync()} bytes=${file.existsSync() ? file.lengthSync() : -1}',
      );

      final AiImportOutcome outcome;
      if (source == AiImportSource.excel) {
        final List<ExcelTable> tables = await ExcelImportService.read(file);
        debugPrint(
          'AI_IMPORT excel read: ${tables.length} sheet(s) '
          '${tables.map((ExcelTable t) => '${t.sheetName}=${t.rows.length}').join(', ')}',
        );
        if (tables.isEmpty) {
          _fail('לא נמצאו שורות בקובץ.');
          return;
        }
        outcome = await AiImportRunner.runTables(tables, onProgress: report);
      } else {
        final WhatsAppChat chat = await WhatsAppImportService.readFile(file);
        debugPrint(
          'AI_IMPORT whatsapp read: ${chat.messages.length} messages, '
          '${chat.mediaPaths.length} media',
        );
        if (chat.isEmpty) {
          _fail('לא זוהו הודעות בקובץ. ודאו שזה ייצוא צ׳אט מוואטסאפ.');
          return;
        }
        outcome = await AiImportRunner.runChat(chat, onProgress: report);
      }

      if (!mounted) {
        return;
      }
      if (outcome.isEmpty) {
        _fail(_emptyOutcomeMessage(outcome));
        return;
      }

      setState(() {
        _isWorking = false;
        _status = '';
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AiImportReviewScreen(
            people: outcome.people,
            failedBatches: outcome.failedBatches,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('AI_IMPORT read failed: $error\n$stackTrace');
      _fail('לא הצלחנו לקרוא את הקובץ.');
    }
  }

  /// Says which of the two very different reasons produced no people.
  ///
  /// "Try again" is the wrong advice for a device whose App Check token is not
  /// registered — it will fail identically every time — and it hides the one
  /// piece of information that would let someone fix it.
  String _emptyOutcomeMessage(AiImportOutcome outcome) {
    if (outcome.isComplete) {
      return 'הקובץ נקרא, אבל לא זוהו בו אנשים.';
    }
    return switch (outcome.firstFailure?.reason) {
      AiParseFailure.attestation =>
        'המכשיר הזה לא מאושר לשימוש ב‑AI. בבנייה לפיתוח יש לרשום את טוקן '
            'ה‑debug ב‑App Check.',
      AiParseFailure.unavailable =>
        'החיבור לשירות ה‑AI לא זמין במכשיר הזה. '
            'ראו AI_IMPORT ביומן לפרטים.',
      AiParseFailure.network =>
        'הקריאה לשירות ה‑AI נכשלה. בדקו חיבור לאינטרנט ונסו שוב.',
      _ => 'לא הצלחנו לקרוא את הקובץ. ראו AI_IMPORT ביומן לפרטים.',
    };
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isWorking = false;
      _status = '';
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    if (_isWorking) {
      return Scaffold(
        appBar: AppBar(title: const Text('הוספה באמצעות AI')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(_status, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('הוספה באמצעות AI')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Text(
            'בחרו מאיפה לקרוא את הפרטים',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: slate,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ה‑AI יקרא את מה שתבחרו ויציע אנשים להוספה. תמיד תראו מה נמצא לפני '
            'שמשהו נכנס למאגר.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          // Firebase comes up alongside the app rather than before it, so the
          // cards have to switch on when it lands instead of being decided
          // once at build time.
          ValueListenableBuilder<bool>(
            valueListenable: FirebaseBootstrap.readyListenable,
            builder: (BuildContext context, bool ready, _) {
              return Column(
                children: <Widget>[
                  for (final AiImportSource source
                      in AiImportSource.values) ...<Widget>[
                    _SourceCard(
                      source: source,
                      slate: slate,
                      dark: dark,
                      enabled:
                          AiImportScreen._available.contains(source) && ready,
                      onTap: () => _start(source),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _PrivacyNote(slate: slate),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.slate,
    required this.dark,
    required this.enabled,
    required this.onTap,
  });

  final AiImportSource source;
  final Color slate;
  final bool dark;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: slate.withValues(alpha: dark ? 0.22 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_icon, color: slate, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: slate.withValues(alpha: dark ? 0.22 : 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'בקרוב',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: slate,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (source) {
    AiImportSource.excel => Icons.table_chart_outlined,
    AiImportSource.whatsapp => Icons.forum_outlined,
    AiImportSource.pastedText => Icons.notes_rounded,
    AiImportSource.camera => Icons.photo_camera_outlined,
    AiImportSource.gallery => Icons.photo_library_outlined,
  };

  String get _title => switch (source) {
    AiImportSource.excel => 'קובץ אקסל',
    AiImportSource.whatsapp => 'ייצוא מוואטסאפ',
    AiImportSource.pastedText => 'הדבקת טקסט',
    AiImportSource.camera => 'צילום כרטיסייה',
    AiImportSource.gallery => 'תמונה מהגלריה',
  };

  String get _subtitle => switch (source) {
    AiImportSource.excel => 'טבלה עם רשימת אנשים, בכל מבנה',
    AiImportSource.whatsapp => 'קובץ שיחה מיוצא, ZIP או טקסט',
    AiImportSource.pastedText => 'רשימה או הודעות עם כמה אנשים',
    AiImportSource.camera => 'צילום של כרטיסייה מודפסת',
    AiImportSource.gallery => 'צילום מסך או תמונה שכבר שמורה',
  };
}

/// Says plainly what leaves the phone. The app is local-first everywhere else,
/// so a screen that sends contact details somewhere should be the one screen
/// that explains itself.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.slate});

  final Color slate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.lock_outline_rounded, size: 16, color: slate),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'רק מה שתבחרו כאן נשלח לקריאה, ואינו משמש לאימון מודלים. המאגר '
            'הקיים שלכם לא נשלח לשום מקום.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
