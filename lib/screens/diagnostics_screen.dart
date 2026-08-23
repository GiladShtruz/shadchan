import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/services/device_facts.dart';
import 'package:shadchan/services/diagnostics_log.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// "יומן תקלות" — what the app wrote down about its own startup, on screen and
/// copyable.
///
/// **This exists because a crash report was unreadable.** An iPhone showed the
/// splash screen and died, App Store Connect had nothing legible about it, and
/// there is no way to attach a debugger to a phone in somebody else's hand. So
/// the app keeps its own record ([DiagnosticsLog]) and this page is the way to
/// get it out: read it, copy the whole thing with one tap, or send it straight
/// into the report form where it arrives with the device, the OS and the build
/// already attached.
///
/// Deliberately plain, and deliberately monospaced-ish: the point is that every
/// character can be selected and pasted somewhere else without anything having
/// been reformatted on the way.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String? _log;
  DeviceFacts _facts = DeviceFacts.unknown;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String log = await DiagnosticsLog.read();
    final DeviceFacts facts = await DeviceFacts.read();
    if (mounted) {
      setState(() {
        _log = log;
        _facts = facts;
      });
    }
  }

  /// The log with the three facts on top, which is what makes a pasted log
  /// answerable: a stack trace without a build number is half a report.
  String get _report {
    final String log = (_log ?? '').trim();
    return <String>[
      'מכשיר: ${_facts.device}',
      'מערכת: ${_facts.os}',
      'גרסה: ${_facts.appVersion}',
      '',
      log.isEmpty ? '(היומן ריק)' : log,
    ].join('\n');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (mounted) {
      AppNotice.show(context, 'היומן הועתק. אפשר להדביק אותו בכל מקום.');
    }
  }

  Future<void> _share() async {
    await Share.share(_report);
  }

  Future<void> _clear() async {
    await DiagnosticsLog.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? log = _log;

    return Scaffold(
      appBar: AppBar(
        title: const Text('יומן תקלות'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: 'רענון',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'ניקוי היומן',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: log == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'כאן נרשם מה שהאפליקציה עשתה בכל הפעלה, ומה נכשל אם משהו '
                      'נכשל. אם האפליקציה קרסה — אפשר להעתיק מכאן את הכל '
                      'ולשלוח לנו.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                  if (DiagnosticsLog.previousRunCrashed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _CrashBanner(
                        lastStep: DiagnosticsLog.previousRunLastStep,
                      ),
                    ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: SingleChildScrollView(
                        // Left-to-right: this is machine text — paths, stack
                        // frames, timestamps — and laying it out RTL breaks
                        // every line of it in the middle.
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText(
                            _report,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontFamilyFallback: const <String>['monospace'],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _copy,
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('העתקת הכל'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _share,
                                icon: const Icon(Icons.ios_share, size: 18),
                                label: const Text('שיתוף'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () =>
                                context.push('/support/report', extra: _report),
                            icon: const Icon(Icons.forum_outlined, size: 18),
                            label: const Text('שליחה אלינו כתקלה'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "האפליקציה נסגרה באמצע ההפעלה" — said only when the previous run really did
/// stop before it drew anything.
class _CrashBanner extends StatelessWidget {
  const _CrashBanner({required this.lastStep});

  final String lastStep;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.error.withValues(alpha: 0.10),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lastStep.isEmpty
                  ? 'ההפעלה הקודמת נסגרה לפני שהאפליקציה הספיקה להיפתח, ולפני '
                        'שהספיקה לרשום ולו שלב אחד.'
                  : 'ההפעלה הקודמת נסגרה לפני שהאפליקציה נפתחה. '
                        'השלב האחרון שהסתיים: $lastStep',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
