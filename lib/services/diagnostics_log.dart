import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A flight recorder for app startup, written to a plain file as it happens.
///
/// **The reason this exists is a crash nobody could read.** The app came up on
/// an iPhone, showed the splash and died — and `main` already wraps everything
/// in `runZonedGuarded`, so a Dart failure would have painted an error screen
/// instead. What that leaves is a failure *below* Dart: a plugin registering, a
/// channel, something in the engine's own startup. None of it reaches
/// `FlutterError.onError`, none of it reaches a `catch`, and the App Store
/// crash report was not readable either.
///
/// So the app writes down where it got to, one line at a time, to a file that
/// outlives the process. On the next launch that file is read back: if the
/// previous run never reached [markFirstFrame], the app knows it died, and it
/// knows the last step it finished before it did. "Died right after
/// `hive_init`" and "never wrote a line at all" are completely different bugs,
/// and telling them apart without a debugger is exactly what this buys.
///
/// **Written synchronously, on purpose.** `writeAsStringSync` hands the bytes
/// to the OS before it returns, so a line survives a process that is killed a
/// millisecond later. An async write is buffered inside the isolate and is
/// exactly the thing a crash throws away.
///
/// Nothing personal goes in here. Steps are fixed identifiers, and what else
/// lands in it is an error message and a stack trace from the app's own code.
abstract final class DiagnosticsLog {
  /// Old runs are worth keeping — a crash that happens every third launch is
  /// read by comparing runs — but not without limit. The file is trimmed to
  /// this from the front whenever it grows past it.
  static const int _maxBytes = 96 * 1024;

  static const String _fileName = 'shadchan_diagnostics.log';
  static const String _firstFrameStep = 'first_frame';

  static File? _file;

  /// Lines written before the file's directory was known. Flushed by [start].
  static final List<String> _buffered = <String>[];

  static bool _previousRunCrashed = false;
  static String _previousRunLastStep = '';

  /// Whether the run before this one stopped before the first frame was drawn.
  ///
  /// This is what the app shows the matchmaker as "האפליקציה נסגרה באמצע
  /// ההפעלה". False on a first ever launch, because there is no previous run to
  /// have crashed.
  static bool get previousRunCrashed => _previousRunCrashed;

  /// The last step the crashed run finished, for the notice to name.
  static String get previousRunLastStep => _previousRunLastStep;

  /// Where the log lives, once [start] has found it. Null before that, and on
  /// a device where no writable directory could be found at all.
  static File? get file => _file;

  /// Opens the log, works out whether the previous run crashed, and writes the
  /// header for this one.
  ///
  /// Never throws. A diagnostics file that cannot be opened must not be the
  /// reason an app fails to start — that would be the joke writing itself.
  static Future<void> start({String? appVersion}) async {
    try {
      final Directory directory = await _directory();
      final File file = File('${directory.path}/$_fileName');
      String existing = '';
      if (file.existsSync()) {
        existing = file.readAsStringSync();
      }
      _readPreviousRun(existing);

      if (existing.length > _maxBytes) {
        existing = existing.substring(existing.length - _maxBytes);
        file.writeAsStringSync(existing);
      }
      _file = file;

      final List<String> pending = <String>[
        '',
        '=== הפעלה ${_stamp(DateTime.now())} '
            '· ${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
            '${appVersion == null ? '' : ' · גרסה $appVersion'}'
            '${kDebugMode ? ' · debug' : ''} ===',
        ..._buffered,
      ];
      _buffered.clear();
      _append(pending.join('\n'));
    } on Object catch (error) {
      // Nothing to do but carry on without a log.
      debugPrint('DiagnosticsLog.start failed: $error');
    }
  }

  /// One finished startup step, by a fixed name — `hive_init`, `boxes_open`,
  /// `notifications`, `migrations`.
  static void mark(String step) {
    _write('· $step');
  }

  /// The app is on screen. A run that never writes this line is a run that
  /// died getting there, which is the whole detection rule.
  static void markFirstFrame() {
    _write('· $_firstFrameStep');
  }

  /// A failure, wherever it was caught — a guarded startup step, the zone
  /// handler, or `FlutterError.onError`.
  static void error(Object error, StackTrace? stack, {String? context}) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('!! ${context ?? 'שגיאה'}: $error');
    if (stack != null) {
      // The first frames are the ones that name the code; a hundred more are
      // framework plumbing that fills the screen the matchmaker has to copy.
      final List<String> frames = stack.toString().trim().split('\n');
      buffer.writeln(frames.take(18).join('\n'));
      if (frames.length > 18) {
        buffer.writeln('   … (${frames.length - 18} שורות נוספות)');
      }
    }
    _write(buffer.toString().trimRight());
  }

  /// The native log written from Swift before Dart exists. See
  /// `ios/Runner/StartupBreadcrumbs.swift`; absent on Android, where nothing
  /// writes it.
  static const String _nativeFileName = 'shadchan_startup.log';

  /// Both logs, native first, for the diagnostics screen to show and the
  /// matchmaker to copy.
  ///
  /// The native one comes first because it starts earlier: it records the
  /// delegate, the plugins and the scene, and this one only starts once `main`
  /// runs. Read top to bottom they are one story, and where the first stops is
  /// where the launch stopped.
  static Future<String> read() async {
    final Directory directory = await _directory();
    final String native = _readFile(File('${directory.path}/$_nativeFileName'));
    final String dart = _readFile(
      _file ?? File('${directory.path}/$_fileName'),
    );

    return <String>[
      if (native.trim().isNotEmpty) ...<String>[
        '--- הפעלה (מערכת) ---',
        native,
      ],
      if (dart.trim().isNotEmpty) ...<String>['--- אפליקציה ---', dart],
    ].join('\n');
  }

  static String _readFile(File file) {
    try {
      return file.existsSync() ? file.readAsStringSync() : '';
    } on Object catch (error) {
      return 'לא הצלחנו לקרוא את $file: $error';
    }
  }

  /// Empties both the native and Dart logs and resets the previous-run flag.
  static Future<void> clear() async {
    try {
      final Directory directory = await _directory();
      (_file ?? File('${directory.path}/$_fileName')).writeAsStringSync('');
      final File native = File('${directory.path}/$_nativeFileName');
      if (native.existsSync()) {
        native.writeAsStringSync('');
      }
      _previousRunCrashed = false;
      _previousRunLastStep = '';
    } on Object catch (error) {
      debugPrint('DiagnosticsLog.clear failed: $error');
    }
  }

  /// The documents directory first, the temporary one as a fallback.
  ///
  /// Documents rather than application support so this file lands **beside**
  /// `shadchan_startup.log`, the native one written from Swift — the two are
  /// read together, one continuing where the other stops, and a reader on an
  /// iPhone gets at both through the Files app or neither.
  ///
  /// `path_provider` is a plugin, so it is itself a thing that can fail on a
  /// device where startup is already going wrong. `Directory.systemTemp` needs
  /// no channel at all and survives a relaunch on both platforms, which is all
  /// this file asks of it.
  static Future<Directory> _directory() async {
    // On iOS this is the app container's `tmp` directory. Its parent is the
    // container root and `Documents` is guaranteed by the iOS app sandbox.
    // Deriving it locally avoids making path_provider the first method-channel
    // call in Dart startup: if plugin messaging is the thing that is broken,
    // the recorder must already be writing before we try any plugin.
    if (Platform.isIOS) {
      final Directory documents = Directory(
        '${Directory.systemTemp.parent.path}/Documents',
      );
      if (!documents.existsSync()) {
        documents.createSync(recursive: true);
      }
      return documents;
    }
    try {
      return await getApplicationDocumentsDirectory();
    } on Object {
      return Directory.systemTemp;
    }
  }

  /// Reads back the last run recorded in [existing] and decides whether it
  /// finished. A run is a block starting at a `===` header.
  static void _readPreviousRun(String existing) {
    final List<String> lines = existing
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.isNotEmpty)
        .toList();
    final int header = lines.lastIndexWhere(
      (String line) => line.startsWith('=== '),
    );
    if (header < 0) {
      return;
    }
    final List<String> run = lines.sublist(header + 1);
    if (run.any((String line) => line.endsWith(_firstFrameStep))) {
      return;
    }
    _previousRunCrashed = true;
    _previousRunLastStep = run.reversed
        .firstWhere((String line) => line.startsWith('· '), orElse: () => '')
        .replaceFirst('· ', '');
  }

  static void _write(String line) {
    final String stamped = '${_time(DateTime.now())} $line';
    if (_file == null) {
      _buffered.add(stamped);
      debugPrint('DIAG $line');
      return;
    }
    _append(stamped);
    debugPrint('DIAG $line');
  }

  static void _append(String text) {
    try {
      _file?.writeAsStringSync('$text\n', mode: FileMode.append, flush: true);
    } on Object catch (error) {
      debugPrint('DiagnosticsLog write failed: $error');
    }
  }

  static String _stamp(DateTime now) =>
      '${_two(now.day)}.${_two(now.month)}.${now.year} ${_time(now)}';

  static String _time(DateTime now) =>
      '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
