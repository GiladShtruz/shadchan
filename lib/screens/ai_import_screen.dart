import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shadchan/dialogs/import_file_kind_dialog.dart';
import 'package:shadchan/dialogs/import_problem_dialog.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/screens/ai_import_review_screen.dart';
import 'package:shadchan/utils/import_file_kind.dart';
import 'package:shadchan/services/ai_import_runner.dart';
import 'package:shadchan/services/excel_import_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/import_diagnostics.dart';
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
    // Read now rather than when something fails: the version is the first
    // thing a report has to carry, and looking it up at the moment of a
    // failure is how it ends up missing from exactly the reports that matter.
    unawaited(ImportDiagnostics.warmUp());

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

  static const List<String> _excelExtensions = <String>['xlsx', 'xlsm'];
  static const List<String> _chatExtensions = <String>['zip', 'txt'];

  /// Opens the system picker and returns a real file on this device.
  ///
  /// Deliberately `FileType.any` rather than an extension whitelist. On Android
  /// the whitelist is translated into MIME types, and the providers people
  /// actually keep a WhatsApp export in — Drive, Files, the manufacturer's own
  /// file app — hand back `application/octet-stream` for a `.zip`, so the
  /// export was greyed out and unpickable. The extension is checked here
  /// instead, where a wrong choice can be explained.
  ///
  /// **`withData` must stay off.** `file_picker` already copies whatever was
  /// picked into the app's cache and always hands back a real path; `withData`
  /// only adds a second and third copy of the same file — one `ByteArray` on
  /// the Java heap, one `Uint8List` on the Dart heap, both the full size of the
  /// export. A WhatsApp group export with media is routinely 100–500 MB and an
  /// Android heap is commonly 128–256 MB, so on a large export that allocation
  /// is simply refused: the plugin logs "probably the file is too big to fit
  /// device memory", returns null bytes, and the import failed before it had
  /// read a single message. Whether it fell over depended on the size of that
  /// particular group's export and on that particular phone's heap — which is
  /// exactly the "works on some phones" this feature had.
  Future<String?> _pickImportFile(AiImportSource source) async {
    final List<String> allowed = source == AiImportSource.excel
        ? _excelExtensions
        : _chatExtensions;

    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      withData: false,
    );
    final PlatformFile? file = picked?.files.singleOrNull;
    if (file == null) {
      return null;
    }

    final String extension = (file.extension ?? p.extension(file.name))
        .replaceAll('.', '')
        .toLowerCase();
    if (!allowed.contains(extension)) {
      _fail(
        source == AiImportSource.excel
            ? 'צריך לבחור קובץ אקסל (xlsx).'
            : 'צריך לבחור את קובץ הייצוא של וואטסאפ (zip או txt).',
      );
      return null;
    }

    final String? path = file.path;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }

    // Unreachable on a phone — the plugin's own path is the cache copy it just
    // wrote — and kept only so a platform that ever stops doing that fails with
    // a sentence instead of silently returning nothing.
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _fail(
        'לא הצלחנו לקרוא את הקובץ שנבחר. נסו לשמור אותו במכשיר ולבחור שוב.',
      );
      return null;
    }

    final Directory temp = await getTemporaryDirectory();
    final File copy = File(
      p.join(
        temp.path,
        'import_${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      ),
    );
    await copy.writeAsBytes(bytes);
    return copy.path;
  }

  Future<void> _start(AiImportSource source) async {
    if (_isWorking) {
      return;
    }

    final String? path = await _pickImportFile(source);
    if (path == null || !mounted) {
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

    final ImportDiagnostics log = ImportDiagnostics(
      source == AiImportSource.excel ? 'אקסל' : 'וואטסאפ',
    );
    final File file = File(path);
    final bool exists = file.existsSync();
    log
      ..noteFile(path, exists ? file.lengthSync() : 0)
      ..note('הקובץ נמצא', exists ? 'כן' : 'לא');

    try {
      void report(int done, int total) {
        if (mounted) {
          setState(() => _status = 'קורא אנשים… $done מתוך $total');
        }
      }

      debugPrint(
        'AI_IMPORT start source=$source path=$path '
        'exists=$exists bytes=${exists ? file.lengthSync() : -1}',
      );

      final AiImportOutcome outcome;
      if (source == AiImportSource.excel) {
        final List<ExcelTable> tables = await ExcelImportService.read(file);
        debugPrint(
          'AI_IMPORT excel read: ${tables.length} sheet(s) '
          '${tables.map((ExcelTable t) => '${t.sheetName}=${t.rows.length}').join(', ')}',
        );
        final int rows = tables.fold(
          0,
          (int sum, ExcelTable t) => sum + t.rows.length,
        );
        log
          ..note('גיליונות', tables.length)
          ..note('שורות', rows);
        if (tables.isEmpty) {
          _failWithReport(
            log,
            message: 'לא נמצאו שורות בקובץ.',
            hint: 'ודאו שהגיליון מכיל שורות ולא רק כותרות.',
          );
          return;
        }
        outcome = await AiImportRunner.runTables(tables, onProgress: report);
      } else {
        final WhatsAppChat chat = await WhatsAppImportService.readFile(file);
        final WhatsAppReadStats stats = chat.stats;
        debugPrint(
          'AI_IMPORT whatsapp read: ${chat.messages.length} messages, '
          '${chat.mediaPaths.length} media, entries=${stats.archiveEntries}, '
          'skipped=${stats.mediaSkipped}',
        );
        final int candidates = chat.candidateMessages.length;
        log
          ..note('פריטים בארכיון', stats.archiveEntries)
          ..note('הודעות', chat.messages.length)
          ..note('הודעות לקריאה', candidates)
          ..note(
            'תמונות',
            '${stats.mediaExtracted} '
                '(${ImportDiagnostics.formatBytes(stats.mediaBytes)}), '
                'דולגו ${stats.mediaSkipped}',
          );
        if (stats.truncatedMessages) {
          log.note('נחתך', 'כן — ${WhatsAppImportService.maxMessages} אחרונות');
        }
        if (stats.cappedMedia) {
          log.note('תמונות נחתכו', 'כן');
        }
        if (chat.isEmpty) {
          _failWithReport(
            log,
            message: 'לא זוהו הודעות בקובץ.',
            hint:
                'ודאו שזה קובץ הייצוא של וואטסאפ עצמו ("ייצוא צ׳אט"), ולא צילום '
                'מסך, קובץ גיבוי או קובץ שנשמר מחדש באפליקציה אחרת.',
          );
          return;
        }
        _warnAboutLimits(stats);
        outcome = await AiImportRunner.runChat(chat, onProgress: report);
      }

      log
        ..note('מנות', outcome.totalBatches)
        ..note('מנות שנכשלו', outcome.failedBatches)
        ..note('אנשים', outcome.people.length);
      if (outcome.firstFailure != null) {
        log
          ..note('סיבה', outcome.firstFailure!.reason.name)
          ..note(
            'שגיאה',
            log.describeError(outcome.firstFailure!.cause ?? '—'),
          );
      }

      if (!mounted) {
        return;
      }
      if (outcome.isEmpty) {
        _failWithReport(
          log,
          message: _emptyOutcomeMessage(outcome),
          hint: _emptyOutcomeHint(outcome),
        );
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
    } on WhatsAppReadException catch (error, stackTrace) {
      debugPrint('AI_IMPORT read failed: $error\n$stackTrace');
      log
        ..note('סיבה', error.reason.name)
        ..note('שגיאה', log.redact(error.cause ?? '—'));
      _failWithReport(
        log,
        message: _readFailureMessage(error.reason),
        hint: _readFailureHint(error.reason),
      );
    } catch (error, stackTrace) {
      debugPrint('AI_IMPORT read failed: $error\n$stackTrace');
      log.note('שגיאה', log.describeError(error));
      _failWithReport(
        log,
        message: 'לא הצלחנו לקרוא את הקובץ.',
        hint: 'אפשר לנסות שוב, ואם זה חוזר — לשלוח לנו את פרטי התקלה.',
      );
    }
  }

  /// Says out loud when the import kept less than the file held.
  ///
  /// Both of these end in a review list that is *shorter than it should be*,
  /// which is the one failure mode indistinguishable from success — the user
  /// sees people, approves them, and never learns that the rest of the group
  /// was never read.
  void _warnAboutLimits(WhatsAppReadStats stats) {
    final String? warning;
    if (stats.truncatedMessages) {
      warning =
          'הצ׳אט ארוך מאוד — נקראו ${WhatsAppImportService.maxMessages} '
          'ההודעות האחרונות בלבד.';
    } else if (stats.cappedMedia) {
      warning =
          'הייצוא כלל יותר תמונות ממה שאפשר לקרוא בבת אחת — חלק מהאנשים '
          'יגיעו בלי תמונה.';
    } else {
      warning = null;
    }
    if (warning == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(warning), duration: const Duration(seconds: 8)),
      );
  }

  String _readFailureMessage(WhatsAppReadFailure reason) => switch (reason) {
    WhatsAppReadFailure.notAnArchive =>
      'הקובץ אינו ארכיון תקין, או שהוא נפגם בדרך.',
    WhatsAppReadFailure.noTranscript => 'הקובץ נפתח, אבל אין בתוכו קובץ שיחה.',
    WhatsAppReadFailure.outOfMemory => 'הייצוא גדול מדי לזיכרון של המכשיר הזה.',
    WhatsAppReadFailure.outOfSpace => 'אין מספיק מקום פנוי במכשיר לייבוא הזה.',
    WhatsAppReadFailure.unreadable => 'לא הצלחנו לקרוא את הקובץ.',
  };

  String _readFailureHint(WhatsAppReadFailure reason) => switch (reason) {
    WhatsAppReadFailure.notAnArchive =>
      'אם שלחתם את הקובץ לעצמכם בוואטסאפ, הוא עלול להישמר חלקית. עדיף לשמור '
          'אותו ישירות במכשיר ("שמירה בקבצים") ולבחור אותו מכאן.',
    WhatsAppReadFailure.noTranscript =>
      'ודאו שבחרתם את קובץ ה‑zip שוואטסאפ יצרה ב"ייצוא צ׳אט", ולא ארכיון אחר.',
    WhatsAppReadFailure.outOfMemory =>
      'נסו לייצא את השיחה שוב ולבחור "ללא מדיה" — הקובץ יהיה קטן בהרבה, '
          'והאנשים ייקראו במלואם (רק בלי תמונות).',
    WhatsAppReadFailure.outOfSpace =>
      'פנו מקום במכשיר, או ייצאו את השיחה שוב עם "ללא מדיה".',
    WhatsAppReadFailure.unreadable =>
      'אפשר לנסות שוב, ואם זה חוזר — לשלוח לנו את פרטי התקלה.',
  };

  /// Says which of the very different reasons produced no people.
  ///
  /// "Try again" is the wrong advice for a device whose App Check token is not
  /// registered — it will fail identically every time — and it hides the one
  /// piece of information that would let someone fix it.
  String _emptyOutcomeMessage(AiImportOutcome outcome) {
    if (outcome.isComplete) {
      return 'הקובץ נקרא, אבל לא זוהו בו אנשים.';
    }
    return switch (outcome.firstFailure?.reason) {
      AiParseFailure.attestation => 'המכשיר הזה לא מאושר לשימוש ב‑AI.',
      AiParseFailure.unavailable => 'החיבור לשירות ה‑AI לא זמין במכשיר הזה.',
      AiParseFailure.network => 'הקריאה לשירות ה‑AI נכשלה.',
      _ => 'לא הצלחנו לקרוא את הקובץ.',
    };
  }

  String? _emptyOutcomeHint(AiImportOutcome outcome) {
    if (outcome.isComplete) {
      return 'ייתכן שהשיחה לא כוללת כרטיסים עם פרטי אנשים.';
    }
    return switch (outcome.firstFailure?.reason) {
      AiParseFailure.attestation =>
        'זו תקלה שרק אנחנו יכולים לתקן — שלחו לנו את פרטי התקלה ונטפל בזה.',
      AiParseFailure.unavailable =>
        'בדקו חיבור לאינטרנט ונסו שוב. אם זה חוזר, שלחו לנו את פרטי התקלה.',
      AiParseFailure.network => 'בדקו חיבור לאינטרנט ונסו שוב.',
      _ => 'אפשר לנסות שוב, ואם זה חוזר — לשלוח לנו את פרטי התקלה.',
    };
  }

  /// A failure the user can do something about, or hand over.
  void _failWithReport(
    ImportDiagnostics log, {
    required String message,
    String? hint,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isWorking = false;
      _status = '';
    });
    unawaited(
      ImportProblemDialog.show(
        context,
        message: message,
        hint: hint,
        report: log.build(problem: message),
      ),
    );
  }

  /// A wrong tap, not a fault: no report, no dialog to dismiss.
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
          _WhatsAppExportGuide(slate: slate),
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

/// How to get a WhatsApp export into the app, step by step.
///
/// Folded away by default: it is a one-time thing to learn, and it should not
/// stand between someone who already knows it and the file picker.
///
/// It ends at WhatsApp's own share sheet rather than at "save the file, then
/// come back and find it" — the app is registered for a shared `.zip`, so
/// handing it straight over is both shorter to describe and the route with
/// nowhere to lose the file along the way.
class _WhatsAppExportGuide extends StatelessWidget {
  const _WhatsAppExportGuide({required this.slate});

  final Color slate;

  static const List<String> _steps = <String>[
    'פותחים ב־WhatsApp את הקבוצה או השיחה שרוצים לייבא.',
    'לוחצים על שלוש הנקודות בתפריט העליון.',
    'בוחרים "עוד" ואז "ייצוא צ׳אט".',
    'בוחרים "לכלול מדיה".',
    'במסך השיתוף בוחרים את אפליקציית השדכן – והיא כבר תמשיך מכאן.',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        leading: Icon(Icons.help_outline_rounded, size: 20, color: slate),
        title: Text(
          'איך מייבאים מ־WhatsApp?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: slate,
          ),
        ),
        children: <Widget>[
          for (int i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: slate.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: slate,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 32, top: 2),
            child: Text(
              'בקבוצה גדולה הייצוא לוקח רגע — שווה לחכות.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
