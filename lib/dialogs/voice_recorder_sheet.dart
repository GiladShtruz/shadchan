import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/utils/app_colors.dart';

/// A finished recording: the file name to store on the note, and its length.
class VoiceRecording {
  const VoiceRecording({required this.fileName, required this.durationMs});

  final String fileName;
  final int durationMs;
}

/// Records a voice note straight from a friend's profile.
///
/// It starts recording as soon as it opens — the tap that opened it was the
/// decision — and has exactly two ways out: "שמירה" keeps the recording,
/// anything else (ביטול, a swipe down, the back key) throws it away and
/// deletes the file. The microphone is asked for here and nowhere else.
abstract final class VoiceRecorderSheet {
  static Future<VoiceRecording?> record(BuildContext context) {
    return showModalBottomSheet<VoiceRecording>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      builder: (BuildContext context) => const _RecorderBody(),
    );
  }
}

class _RecorderBody extends StatefulWidget {
  const _RecorderBody();

  @override
  State<_RecorderBody> createState() => _RecorderBodyState();
}

class _RecorderBodyState extends State<_RecorderBody> {
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  String? _name;
  String? _path;
  bool _denied = false;
  bool _finished = false;

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
      _clock.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      if (mounted) {
        setState(() {});
      }
    } on Object {
      if (mounted) {
        setState(() => _denied = true);
      }
    }
  }

  Future<void> _save() async {
    _ticker?.cancel();
    _clock.stop();
    final String? written = await _recorder.stop();
    _finished = true;
    final String? name = _name;
    if (!mounted) {
      return;
    }
    if (name == null || written == null || !File(written).existsSync()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      VoiceRecording(fileName: name, durationMs: _clock.elapsedMilliseconds),
    );
  }

  Future<void> _discard() async {
    _ticker?.cancel();
    _clock.stop();
    try {
      await _recorder.stop();
    } on Object {
      // Nothing was recording.
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
    if (!_finished) {
      // Closed some other way: nothing is kept.
      _recorder.stop().whenComplete(() => VoiceNoteStore.delete(_name));
    }
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Duration elapsed = _clock.elapsed;
    final String time =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

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
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.mic_off_outlined, size: 40),
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
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'הקלטת הערה',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Icon(
                      Icons.mic_rounded,
                      size: 44,
                      color: _path == null
                          ? theme.colorScheme.onSurfaceVariant
                          : (dark
                                ? AppColors.secondaryDarkDm
                                : AppColors.secondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      time,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
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
                            onPressed: _path == null ? null : _save,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('שמירה'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
