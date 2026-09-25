import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/utils/app_colors.dart';

/// One voice note, playable where it sits in the list of notes.
///
/// The player is made on the first tap, not when the row is drawn: a profile
/// with twenty recordings must not open twenty audio sessions just to be
/// scrolled past.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.fileName,
    this.durationMs,
    this.compact = false,
  });

  final String fileName;
  final int? durationMs;
  final bool compact;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    final int? ms = widget.durationMs;
    if (ms != null && ms > 0) {
      _duration = Duration(milliseconds: ms);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final AudioPlayer? existing = _player;
    if (existing != null) {
      if (_playing) {
        await existing.pause();
      } else {
        if (_duration != null && _position >= _duration!) {
          await existing.seek(Duration.zero);
        }
        await existing.play();
      }
      return;
    }

    final File file = await VoiceNoteStore.fileFor(widget.fileName);
    if (!await file.exists()) {
      if (mounted) {
        setState(() => _missing = true);
      }
      return;
    }
    final AudioPlayer player = AudioPlayer();
    _player = player;
    try {
      final Duration? duration = await player.setFilePath(file.path);
      if (duration != null) {
        _duration = duration;
      }
    } on Object {
      await player.dispose();
      _player = null;
      if (mounted) {
        setState(() => _missing = true);
      }
      return;
    }
    _stateSub = player.playerStateStream.listen((PlayerState state) {
      if (!mounted) {
        return;
      }
      final bool done = state.processingState == ProcessingState.completed;
      setState(() => _playing = state.playing && !done);
      if (done) {
        player.pause();
        player.seek(Duration.zero);
      }
    });
    _positionSub = player.positionStream.listen((Duration position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });
    if (mounted) {
      setState(() {});
    }
    await player.play();
  }

  static String _clock(Duration d) {
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = AppColors.heading(dark: dark);

    if (_missing) {
      return Row(
        children: <Widget>[
          Icon(
            Icons.mic_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'ההקלטה לא נמצאת במכשיר הזה',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final Duration? total = _duration;
    final double progress = total == null || total.inMilliseconds == 0
        ? 0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0, 1);

    return Row(
      children: <Widget>[
        Material(
          color: ink.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggle,
            child: SizedBox.square(
              dimension: widget.compact ? 32 : 38,
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: ink,
                size: widget.compact ? 20 : 24,
                semanticLabel: _playing ? 'עצירה' : 'השמעת ההקלטה',
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: ink.withValues(alpha: 0.10),
              color: ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _clock(
            _playing || _position > Duration.zero
                ? _position
                : (total ?? Duration.zero),
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
