import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the app can reach the server right now.
///
/// **Two questions, asked in order.** The operating system knows at once when
/// the phone has no network at all (`connectivity_plus`), and that answer is
/// taken as it comes. But "connected to Wi-Fi" is not "online" — a hotel
/// login page, a router with no line behind it — so a phone that says it has a
/// network is then asked to actually reach Google's servers, the same ones the
/// sync talks to. Only a failed reach, twice, makes the app offline.
///
/// **Leaning towards online on purpose.** Being called offline blocks every
/// edit in the app (see `OfflineGuard`), while being called online a few
/// seconds too long costs nothing: Firestore keeps whatever was written in its
/// own queue and sends it when it can. So a single slow answer never flips the
/// state, and anything that cannot be decided leaves it where it was.
///
/// Nothing starts until [start] is called, after the first frame. Under
/// `flutter test` nothing calls it and the app is simply online.
abstract final class ConnectivityStatus {
  /// True while the app cannot reach the server. Listened to by the banner,
  /// the repositories (which then show cached personal cards) and the sync
  /// scheduler (which catches up the moment it turns false).
  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  static bool get isOffline => offline.value;

  /// How often an offline app tries again. Short: coming back online is what
  /// the user is waiting for, and one HEAD request is nothing.
  static const Duration offlineRetry = Duration(seconds: 8);

  /// How often an online app checks that it still is, for the case the
  /// operating system does not report — the line behind the router dropping.
  static const Duration onlineRecheck = Duration(minutes: 2);

  static const Duration _probeTimeout = Duration(seconds: 6);

  /// Hosts that answer anything at all when the internet is there. The first
  /// is the sync's own server; any HTTP answer, even an error page, is proof.
  static const List<String> _probeUrls = <String>[
    'https://firestore.googleapis.com/',
    'https://www.google.com/generate_204',
  ];

  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static Timer? _timer;
  static bool _started = false;
  static bool _checking = false;
  static bool _recheckAfter = false;

  /// Begins watching. Safe to call more than once.
  static Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      _subscription = Connectivity().onConnectivityChanged.listen(
        _onChanged,
        onError: (Object _) {},
      );
      _onChanged(await Connectivity().checkConnectivity());
    } on Object catch (error) {
      // No plugin (a platform without one): decide by reaching alone.
      debugPrint('ConnectivityStatus: $error');
      unawaited(check());
    }
  }

  /// Asks again now — on app resume, and whenever something suspects the
  /// connection came back.
  static Future<void> check() async {
    if (_checking) {
      _recheckAfter = true;
      return;
    }
    _checking = true;
    try {
      bool reached = await _reach();
      if (!reached) {
        // One failed reach is a slow network as often as it is no network.
        await Future<void>.delayed(const Duration(seconds: 2));
        reached = await _reach();
      }
      _set(offline: !reached);
    } finally {
      _checking = false;
    }
    if (_recheckAfter) {
      _recheckAfter = false;
      unawaited(check());
    }
  }

  static void _onChanged(List<ConnectivityResult> results) {
    final bool noNetwork =
        results.isEmpty ||
        results.every((ConnectivityResult r) => r == ConnectivityResult.none);
    if (noNetwork) {
      _set(offline: true);
      return;
    }
    unawaited(check());
  }

  static Future<bool> _reach() async {
    for (final String url in _probeUrls) {
      final HttpClient client = HttpClient()..connectionTimeout = _probeTimeout;
      try {
        final HttpClientRequest request = await client
            .headUrl(Uri.parse(url))
            .timeout(_probeTimeout);
        final HttpClientResponse response = await request.close().timeout(
          _probeTimeout,
        );
        await response.drain<void>().catchError((Object _) {});
        return true;
      } on Object {
        // Try the next host.
      } finally {
        client.close(force: true);
      }
    }
    return false;
  }

  static void _set({required bool offline}) {
    if (ConnectivityStatus.offline.value != offline) {
      ConnectivityStatus.offline.value = offline;
    }
    _schedule();
  }

  static void _schedule() {
    _timer?.cancel();
    if (!_started) {
      return;
    }
    _timer = Timer(isOffline ? offlineRetry : onlineRecheck, () {
      unawaited(check());
    });
  }

  /// Test seam: puts the app in or out of offline mode without a network.
  @visibleForTesting
  static void debugSetOffline(bool value) {
    offline.value = value;
  }

  /// Stops watching. For tests.
  @visibleForTesting
  static Future<void> debugReset() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    offline.value = false;
  }
}
