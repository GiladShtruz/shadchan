import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/voice_note_player.dart';

/// A finished recording: the file name to store on the note, and its length.
class VoiceRecording {
  const VoiceRecording({required this.fileName, required this.durationMs});

  final String fileName;
  final int durationMs;
}

/// Asks for a few words to keep beside a recording — who is speaking, when it
/// was recorded, what it is about. Returns the words, empty when skipped.
abstract final class VoiceNoteCaption {
  static Future<String> ask(BuildContext context) async {
    final String? caption = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _CaptionDialog(),
    );
    return (caption ?? '').trim();
  }
}

class _CaptionDialog extends StatefulWidget {
  const _CaptionDialog();

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הערה להקלטה'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          hintText: 'מי מדבר, מתי הוקלט, על מה…',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('דילוג'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}

/// Records a voice note straight from a friend's profile.
///
/// It starts recording as soon as it opens — the tap that opened it was the
/// decision. Two phases, never mixed up: while recording, a breathing
/// microphone, a red dot, "מקליט…" and the time, with "סיום הקלטה"; then the
/// take, playable in place with its length, and "שמירה", "הקלטה מחדש" or
/// delete. Anything but "שמירה" (ביטול, a swipe down, the back key) throws it
/// away and deletes the file. No stop square and no play triangle stand in
/// for "record" — the microphone is the one sign for it, app-wide.
abstract final class VoiceRecorderSheet {
  static const String recordingTitle = 'הקלטה';
  static const String reviewTitle = 'ההקלטה מוכנה';
  static const String finishLabel = 'סיום הקלטה';
  static const String againLabel = 'הקלטה מחדש';

  static Future<VoiceRecording?> record(
    BuildContext context, {
    Duration? maxDuration,
  }) {
    return showModalBottomSheet<VoiceRecording>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      builder: (BuildContext context) =>
          _RecorderBody(maxDuration: maxDuration),
    );
  }
}

class _RecorderBody extends StatefulWidget {
  const _RecorderBody({this.maxDuration});
  final Duration? maxDuration;

  @override
  State<_RecorderBody> createState() => _RecorderBodyState();
}

class _RecorderBodyState extends State<_RecorderBody>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _ticker;
  String? _name;
  String? _path;
  bool _denied = false;
  bool _finished = false;
  bool _stopping = false;

  /// Recorded and stopped, waiting to be listened to, saved, deleted or
  /// recorded again.
  VoiceRecording? _take;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() => _denied = true);
        }
        return;
      }
      final ({String name, String path}) target =
          await VoiceNoteStore.newRecording();
      _name = target.name;
      _path = target.path;
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: target.path,
      );
      _clock
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (widget.maxDuration != null &&
            _clock.elapsed >=
                widget.maxDuration! - const Duration(seconds: 1)) {
          unawaited(_stop());
        }
        if (mounted) {
          setState(() {});
        }
      });
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        _pulse.repeat(reverse: true);
      }
      if (mounted) {
        setState(() {});
      }
    } on Object {
      if (mounted) {
        setState(() => _denied = true);
      }
    }
  }

  /// Ends the recording and shows it for review — nothing is kept yet.
  Future<void> _stop() async {
    if (_stopping || _take != null) return;
    _stopping = true;
    _ticker?.cancel();
    _clock.stop();
    _pulse.stop();
    String? written;
    try {
      written = await _recorder.stop();
    } on Object {
      written = null;
    }
    _stopping = false;
    final String? name = _name;
    if (!mounted) {
      return;
    }
    if (name == null || written == null || !File(written).existsSync()) {
      _finished = true;
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _take = VoiceRecording(
        fileName: name,
        durationMs: _clock.elapsedMilliseconds,
      );
    });
  }

  void _save() {
    final VoiceRecording? take = _take;
    if (take == null) return;
    _finished = true;
    Navigator.of(context).pop(take);
  }

  /// Throws this take away and starts a new one in its place.
  Future<void> _again() async {
    final String? old = _name;
    setState(() {
      _take = null;
      _name = null;
      _path = null;
    });
    await VoiceNoteStore.delete(old);
    if (mounted) await _start();
  }

  Future<void> _discard() async {
    _ticker?.cancel();
    _clock.stop();
    if (_take == null) {
      try {
        await _recorder.stop();
      } on Object {
        // Nothing was recording.
      }
    }
    _finished = true;
    await VoiceNoteStore.delete(_name);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    if (!_finished) {
      // Closed some other way: nothing is kept.
      final String? name = _name;
      _recorder.stop().whenComplete(() => VoiceNoteStore.delete(name));
    }
    _recorder.dispose();
    super.dispose();
  }

  static String clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark ? AppColors.secondaryDarkDm : AppColors.secondary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _discard();
        }
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _denied
              ? _deniedBody(theme)
              : _take == null
              ? _recordingBody(theme, accent)
              : _reviewBody(theme, accent, _take!),
        ),
      ),
    );
  }

  Widget _deniedBody(ThemeData theme) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const Icon(Icons.mic_off_rounded, size: 40),
      const SizedBox(height: 12),
      Text(
        'אין גישה למיקרופון. אפשר לאשר אותה בהגדרות הטלפון.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () {
          _finished = true;
          Navigator.of(context).pop();
        },
        child: const Text('סגירה'),
      ),
    ],
  );

  /// While recording: the microphone breathing in the action colour, a red
  /// dot and "מקליט…", the time, and one way to finish.
  Widget _recordingBody(ThemeData theme, Color accent) {
    final bool live = _path != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          VoiceRecorderSheet.recordingTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext context, Widget? child) {
            final double t = live ? _pulse.value : 0;
            return Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12 + 0.10 * t),
                boxShadow: <BoxShadow>[
                  if (live)
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25 * t),
                      blurRadius: 10 + 14 * t,
                      spreadRadius: 2 + 4 * t,
                    ),
                ],
              ),
              child: child,
            );
          },
          child: Icon(
            Icons.mic_rounded,
            size: 42,
            color: live ? accent : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (live) ...<Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: AppColors.rose,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              live ? 'מקליט…' : 'מתחילים…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              clock(_clock.elapsed),
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _discard,
                child: const Text('ביטול'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('voice-finish'),
                onPressed: live && !_stopping ? _stop : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text(VoiceRecorderSheet.finishLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// After recording: listen to it, then keep it, delete it or record again.
  Widget _reviewBody(ThemeData theme, Color accent, VoiceRecording take) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          VoiceRecorderSheet.reviewTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: VoiceNotePlayer(
            key: ValueKey<String>(take.fileName),
            fileName: take.fileName,
            durationMs: take.durationMs,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            IconButton(
              tooltip: 'מחיקה',
              onPressed: _discard,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _again,
                icon: const Icon(Icons.mic_rounded),
                label: const Text(VoiceRecorderSheet.againLabel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('voice-save'),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('שמירה'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
