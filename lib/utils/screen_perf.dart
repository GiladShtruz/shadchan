import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shadchan/services/telemetry.dart';

/// A small performance log for one visit to one screen: how long until its
/// content was there, how many times it was built, how many Firestore
/// listeners and reads the app held, memory and the image cache — on entry
/// and on leaving, so a screen that leaves work running behind it shows up
/// as a difference between the two.
///
/// Lines start with `PERF ` (read them with `adb logcat | grep PERF` on a
/// device). The last few reports are also kept in [recent] for the support
/// console's diagnostics. Never records anything about a person.
class ScreenPerf {
  ScreenPerf(this.screen, {required this.listeners}) {
    _enter = _snapshot();
    debugPrint('PERF $screen enter ${_enter.line}');
  }

  final String screen;

  /// Counts the Firestore listeners the app holds now.
  final int Function() listeners;

  final Stopwatch _clock = Stopwatch()..start();
  late final _Snap _enter;
  int builds = 0;
  int reads = 0;
  int? _firstContentMs;

  static final List<String> recent = <String>[];

  /// Firestore reads/listens started anywhere in the network code, app-wide
  /// — a screen's report shows how many it caused by the difference.
  static int queries = 0;

  /// Network card photos actually fetched (cache misses), app-wide.
  static int photosLoaded = 0;

  /// Network cards held in memory right now (pages + single reads).
  static int Function() cardsInMemory = () => 0;

  static void noteQuery([int n = 1]) {
    queries += n;
    // And into the account's cost counters (`Telemetry.meter`).
    Telemetry.meter(queries: n);
  }
  static void notePhoto() => photosLoaded++;

  void build() => builds++;

  /// The screen has something real on it (or knows it has nothing).
  void contentReady() {
    if (_firstContentMs != null) return;
    _firstContentMs = _clock.elapsedMilliseconds;
    debugPrint('PERF $screen content ${_firstContentMs}ms builds=$builds');
  }

  void read([int n = 1]) => reads += n;

  void leave() {
    final _Snap exit = _snapshot();
    final String line =
        'PERF $screen leave after=${_clock.elapsedMilliseconds}ms '
        'content=${_firstContentMs ?? -1}ms builds=$builds reads=$reads '
        'enter[${_enter.line}] exit[${exit.line}]';
    debugPrint(line);
    recent.add(line);
    if (recent.length > 10) recent.removeAt(0);
  }

  _Snap _snapshot() {
    int rssMb = -1;
    try {
      rssMb = ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {}
    final ImageCache cache = PaintingBinding.instance.imageCache;
    return _Snap(
      queries: queries,
      photos: photosLoaded,
      cards: cardsInMemory(),
      listeners: listeners(),
      rssMb: rssMb,
      imagesMb: cache.currentSizeBytes ~/ (1024 * 1024),
      images: cache.currentSize,
    );
  }
}

class _Snap {
  const _Snap({
    required this.queries,
    required this.photos,
    required this.cards,
    required this.listeners,
    required this.rssMb,
    required this.imagesMb,
    required this.images,
  });
  final int queries;
  final int photos;
  final int cards;
  final int listeners;
  final int rssMb;
  final int imagesMb;
  final int images;

  String get line =>
      'listeners=$listeners queries=$queries cards=$cards photos=$photos '
      'rss=${rssMb}MB images=$images/${imagesMb}MB';
}
