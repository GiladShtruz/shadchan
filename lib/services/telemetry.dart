// The feature ids are stored on the server as they are spelt here.
// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_version.dart';
import 'package:uuid/uuid.dart';

/// **Every part of the app the monitoring knows about, by a fixed id.**
///
/// The id is the enum value's name, and it is stored on the server — **never
/// rename one**; add a new value for a new feature. The admin dashboard needs
/// nothing else to start showing it (an unknown id is listed under its own
/// name until `FEATURE_NAMES` in `functions/src/analytics.ts` gives it a
/// Hebrew one).
enum AppFeature {
  home,
  people,
  ideas,
  matches,
  chats,
  profile,
  personal_card,
  my_matchmakers,
  partner_matchmakers,
  database_sharing,
  add_friend,
  add_contacts,
  add_manual,
  ai,
  ai_card,
  ai_import,
  ai_chat,
  search,
  filters,
  notifications,
  whatsapp_share,
  voice_notes,
  photo_upload,
  card_open,
  access,
  idea_open,
  idea_status,
  shared_idea,
  settings,
  activity,
  board,
  tags,
  notes,
  other,
  app,
}

/// The monitoring's one way in — **the only place in the app that sends a
/// usage event**, so every screen speaks the same small taxonomy:
///
/// * [opened] — `feature_opened` (pages are opened automatically by the
///   router: `AppRouter.trackScreens`);
/// * [started] / [completed] / [failed] — `action_started` / `_completed` /
///   `_failed`, with an action code (`pick`, `save`, `request`…) — and
///   [track] wraps an async action in the three of them with its duration;
/// * [timing] — a performance measure (app start, a screen drawn);
/// * [error] — an uncaught error, by type, on the page it happened;
/// * [aiCall] — one AI request's metadata;
/// * [meter] — counters of database reads/writes, file transfer and backend
///   calls, for the estimated infrastructure cost per account.
///
/// Each event carries an `event_id`, the time, the session, and (on the
/// batch) the account, app version, platform and kind of user. **Only codes
/// and numbers** — never a name, number, card, note, message, recording or
/// prompt; [code] reduces every string to a short ascii code.
///
/// **It never slows or blocks anything.** Recording is a list append; events
/// are kept in a local queue (the `telemetry` box, so a lost connection or a
/// closed app loses nothing) and written in batches of up to 400 to
/// `telemetryBatches/` every few minutes and when the app goes to the
/// background, without awaiting the server — Firestore's own offline queue
/// takes it from there. The server folds each batch once (by its id) and
/// drops repeated event ids, so a retry is never counted twice.
///
/// "שליחת נתוני שימוש" off: usage events stop; only AI calls and the cost
/// counters are kept, because they are what keeps the service affordable.
abstract final class Telemetry {
  static const String boxName = 'telemetry';
  static const String collection = 'telemetryBatches';
  static const int maxQueued = 3000;
  static const int batchSize = 400;

  static final List<Map<String, Object?>> _queue = <Map<String, Object?>>[];
  static bool _loaded = false;
  static Timer? _timer;
  static bool _started = false;
  static String _session = const Uuid().v4();
  static DateTime _sessionStart = DateTime.now();
  static DateTime? _pausedAt;
  static String? _deviceId;
  static String? _storageDay;

  /// The page in front of the user, for [error].
  static AppFeature currentFeature = AppFeature.app;

  /// Test seam: every event as it is recorded.
  @visibleForTesting
  static void Function(Map<String, Object?> event)? debugSink;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;

  /// A short ascii code from anything: an error, an exception type, a string.
  static String code(Object? value) {
    String raw;
    if (value is FirebaseException) {
      raw = value.code;
    } else if (value is TimeoutException) {
      raw = 'timeout';
    } else if (value is SocketException) {
      raw = 'network';
    } else if (value is String) {
      raw = value;
    } else {
      raw = value?.runtimeType.toString() ?? 'unknown';
    }
    final String cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  // --- The taxonomy -----------------------------------------------------------

  static void opened(AppFeature feature, {String? action}) =>
      _usage('open', feature, action: action);

  static void started(AppFeature feature, String action) =>
      _usage('start', feature, action: action);

  static void completed(
    AppFeature feature,
    String action, {
    int? ms,
    Map<String, num>? extra,
  }) => _usage('done', feature, action: action, ms: ms, extra: extra);

  static void failed(
    AppFeature feature,
    String action,
    Object? error, {
    int? ms,
  }) => _usage('fail', feature, action: action, ms: ms, error: code(error));

  /// [run], recorded as started → completed / failed with its duration. The
  /// result and any error pass straight through.
  static Future<T> track<T>(
    AppFeature feature,
    String action,
    Future<T> Function() run,
  ) async {
    final Stopwatch watch = Stopwatch()..start();
    started(feature, action);
    try {
      final T result = await run();
      completed(feature, action, ms: watch.elapsedMilliseconds);
      return result;
    } catch (error) {
      failed(feature, action, error, ms: watch.elapsedMilliseconds);
      rethrow;
    }
  }

  /// A step that only completes somewhere else — "פתיחת רעיון" tapped in
  /// התאמות completes when the idea is actually created, in the repository.
  /// The next [fulfil] of [kind] within five minutes records [feature] /
  /// [action] as completed.
  static void expect(String kind, AppFeature feature, String action) {
    _expected[kind] = (feature, action, DateTime.now());
  }

  static void fulfil(String kind) {
    final (AppFeature, String, DateTime)? e = _expected.remove(kind);
    if (e == null) return;
    if (DateTime.now().difference(e.$3) < const Duration(minutes: 5)) {
      completed(e.$1, e.$2);
    }
  }

  static final Map<String, (AppFeature, String, DateTime)> _expected =
      <String, (AppFeature, String, DateTime)>{};

  static void timing(AppFeature feature, String metric, int ms) =>
      _usage('time', feature, action: metric, ms: ms);

  static void error(Object error, {AppFeature? feature}) =>
      _usage('err', feature ?? currentFeature, error: code(error));

  /// One AI request. Tokens are the provider's own usage metadata; the
  /// server prices them with the pricing version of the moment.
  static void aiCall({
    required AppFeature feature,
    required String model,
    required int inputTokens,
    required int outputTokens,
    required int latencyMs,
    required bool ok,
    int tries = 1,
    Object? error,
  }) {
    _record(<String, Object?>{
      't': 'ai',
      'f': feature.name,
      'ms': latencyMs,
      if (!ok) 'e': code(error ?? 'failed'),
      'x': <String, Object?>{
        'model': code(model),
        'in': inputTokens,
        'out': outputTokens,
        'ok': ok,
        'tries': tries,
      },
    });
  }

  // --- Cost counters ----------------------------------------------------------

  static final Map<String, int> _meter = <String, int>{};

  /// Adds to this account's cost counters; sent as one event per batch.
  static void meter({
    int reads = 0,
    int writes = 0,
    int deletes = 0,
    int queries = 0,
    int uploadBytes = 0,
    int downloadBytes = 0,
    int uploads = 0,
    int downloads = 0,
    int functions = 0,
  }) {
    void add(String key, int value) {
      if (value > 0) _meter[key] = (_meter[key] ?? 0) + value;
    }

    add('r', reads);
    add('w', writes);
    add('d', deletes);
    add('q', queries);
    add('upB', uploadBytes);
    add('dnB', downloadBytes);
    add('upN', uploads);
    add('dnN', downloads);
    add('fn', functions);
  }

  // --- Recording --------------------------------------------------------------

  static void _usage(
    String type,
    AppFeature feature, {
    String? action,
    int? ms,
    String? error,
    Map<String, num>? extra,
  }) {
    if (Analytics.optedOut) return;
    _record(<String, Object?>{
      't': type,
      'f': feature.name,
      if (action != null) 'a': code(action),
      'ms': ?ms,
      'e': ?error,
      if (extra != null && extra.isNotEmpty) 'x': extra,
    });
    // The same four generic events in Firebase Analytics, with the feature
    // and action as parameters — never one event per screen.
    final AnalyticsEvent? mirror = switch (type) {
      'open' => AnalyticsEvent.feature_opened,
      'start' => AnalyticsEvent.action_started,
      'done' => AnalyticsEvent.action_completed,
      'fail' => AnalyticsEvent.action_failed,
      _ => null,
    };
    if (mirror != null) {
      Analytics.log(mirror, <String, Object?>{
        'feature': feature.name,
        if (action != null) 'action': code(action),
        'error': ?error,
      });
    }
  }

  static void _record(Map<String, Object?> event) {
    event['id'] = const Uuid().v4();
    event['ts'] = DateTime.now().millisecondsSinceEpoch;
    event['s'] = _session;
    final void Function(Map<String, Object?>)? sink = debugSink;
    if (sink != null) {
      sink(event);
      return;
    }
    _ensureLoaded();
    _queue.add(event);
    if (_queue.length > maxQueued) {
      final Map<String, Object?> dropped = _queue.removeAt(0);
      _persistRemove(<String>[dropped['id']! as String]);
    }
    _persistAdd(event);
    if (_started && _queue.length >= 200) unawaited(flush());
  }

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final Box<dynamic>? box = _box;
    if (box == null) return;
    for (final Object? key in box.keys) {
      if (key is! String || !key.startsWith('e:')) continue;
      final Object? raw = box.get(key);
      if (raw is! String) continue;
      try {
        final Object? json = jsonDecode(raw);
        if (json is Map) _queue.add(Map<String, Object?>.from(json));
      } on FormatException {
        continue;
      }
    }
    _queue.sort(
      (Map<String, Object?> a, Map<String, Object?> b) =>
          ((a['ts'] as int?) ?? 0).compareTo((b['ts'] as int?) ?? 0),
    );
  }

  // Hive writes in the root zone: one started in a widget test's fake-async
  // zone never completes.
  static void _persistAdd(Map<String, Object?> event) {
    if (_box == null) return;
    final String key = 'e:${event['id']}';
    final String value = jsonEncode(event);
    Zone.root.scheduleMicrotask(() async {
      try {
        await _box?.put(key, value);
      } catch (_) {}
    });
  }

  static void _persistRemove(List<String> ids) {
    if (_box == null || ids.isEmpty) return;
    Zone.root.scheduleMicrotask(() async {
      try {
        await _box?.deleteAll(<String>[for (final String id in ids) 'e:$id']);
      } catch (_) {}
    });
  }

  // --- Sessions and sending ---------------------------------------------------

  static final _Lifecycle _lifecycle = _Lifecycle();

  /// From `main` after the first frame. Never under `flutter test`.
  static void start() {
    if (_started) return;
    _started = true;
    _ensureLoaded();
    WidgetsBinding.instance.addObserver(_lifecycle);
    _newSession();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => flush());
  }

  static void _newSession() {
    _session = const Uuid().v4();
    _sessionStart = DateTime.now();
    _usage('sess', AppFeature.app, action: 'start');
  }

  static void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      _usage(
        'sess',
        AppFeature.app,
        action: 'end',
        ms: DateTime.now().difference(_sessionStart).inMilliseconds,
      );
      unawaited(flush());
    } else if (state == AppLifecycleState.resumed) {
      final DateTime? paused = _pausedAt;
      _pausedAt = null;
      // Back within half an hour: the same visit.
      if (paused == null ||
          DateTime.now().difference(paused) > const Duration(minutes: 30)) {
        _newSession();
      } else {
        _usage('sess', AppFeature.app, action: 'start');
      }
    }
  }

  static String _userType() {
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    bool single = false;
    if (Hive.isBoxOpen('settings')) {
      single = Hive.box<dynamic>('settings').get('userIsSingle') == true;
    }
    if (matchmaker && single) return 'both';
    if (single) return 'single';
    return matchmaker ? 'matchmaker' : 'unknown';
  }

  static String get _platform => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
      ? 'ios'
      : 'other';

  static String _device() {
    if (_deviceId != null) return _deviceId!;
    final Box<dynamic>? box = _box;
    String? id = box?.get('did') as String?;
    if (id == null) {
      id = const Uuid().v4();
      final String value = id;
      Zone.root.scheduleMicrotask(() async {
        try {
          await _box?.put('did', value);
        } catch (_) {}
      });
    }
    return _deviceId = id;
  }

  static bool _flushing = false;

  /// Sends what is queued, in batches. Never awaited by anything the user
  /// waits on.
  static Future<void> flush() async {
    if (_flushing || !_started) return;
    _flushing = true;
    try {
      if (!FirebaseBootstrap.isReady) return;
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await _addStorageFootprintOncePerDay();
      if (_meter.isNotEmpty) {
        _record(<String, Object?>{
          't': 'meter',
          'f': AppFeature.app.name,
          'x': Map<String, Object?>.from(_meter),
        });
        _meter.clear();
      }
      final String version = AppVersion.value.isEmpty
          ? await AppVersion.read()
          : AppVersion.value;
      while (_queue.isNotEmpty) {
        final List<Map<String, Object?>> batch = _queue
            .take(batchSize)
            .toList(growable: false);
        final String batchId = const Uuid().v4();
        // Not awaited: Firestore keeps the write on disk until it reaches the
        // server, so the local copy can go now.
        unawaited(
          FirebaseFirestore.instance
              .collection(collection)
              .doc(batchId)
              .set(<String, Object?>{
                'uid': user.uid,
                'did': _device(),
                if (version.isNotEmpty)
                  'v': version.length > 20 ? version.substring(0, 20) : version,
                'p': _platform,
                'ut': _userType(),
                'events': batch,
                'createdAt': FieldValue.serverTimestamp(),
              })
              .catchError((Object error) {
                debugPrint('Telemetry batch not sent: $error');
              }),
        );
        _queue.removeRange(0, batch.length);
        _persistRemove(<String>[
          for (final Map<String, Object?> e in batch) e['id']! as String,
        ]);
      }
    } catch (error) {
      debugPrint('Telemetry.flush: $error');
    } finally {
      _flushing = false;
    }
  }

  /// Photos and voice notes this phone holds (they are also in the account's
  /// cloud storage) — the storage cost per account. Once a day.
  static Future<void> _addStorageFootprintOncePerDay() async {
    final DateTime now = DateTime.now();
    final String today = '${now.year}-${now.month}-${now.day}';
    if (_storageDay == today) return;
    _storageDay = today;
    Future<(int, int)> sizeOf(Future<Directory> dir) async {
      int count = 0;
      int bytes = 0;
      try {
        final Directory d = await dir;
        if (!d.existsSync()) return (0, 0);
        await for (final FileSystemEntity e in d.list()) {
          if (e is File) {
            count++;
            bytes += await e.length();
          }
        }
      } catch (_) {}
      return (count, bytes);
    }

    final (int photos, int photosB) = await sizeOf(
      PhotoPickerService.ensurePhotosDirectory(),
    );
    final (int voice, int voiceB) = await sizeOf(VoiceNoteStore.directory());
    _record(<String, Object?>{
      't': 'meter',
      'f': AppFeature.app.name,
      'x': <String, Object?>{
        'photos': photos,
        'photosB': photosB,
        'voice': voice,
        'voiceB': voiceB,
      },
    });
  }

  /// Signing out: what is queued belongs to the account that is leaving and
  /// is sent under it first if possible; nothing carries over.
  static Future<void> forget() async {
    await flush();
    _queue.clear();
    _meter.clear();
    _storageDay = null;
    final Box<dynamic>? box = _box;
    if (box != null) {
      final List<Object?> keys = box.keys
          .where((Object? k) => k is String && k.startsWith('e:'))
          .toList();
      Zone.root.scheduleMicrotask(() async {
        try {
          await box.deleteAll(keys);
        } catch (_) {}
      });
    }
  }

  @visibleForTesting
  static List<Map<String, Object?>> get queued =>
      List<Map<String, Object?>>.unmodifiable(_queue);

  @visibleForTesting
  static void resetForTest() {
    _queue.clear();
    _meter.clear();
    _loaded = false;
    _started = false;
    _timer?.cancel();
    _timer = null;
    debugSink = null;
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      Telemetry._onLifecycle(state);
}
