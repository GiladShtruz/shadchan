import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/firebase_options.dart';

/// A debug App Check token, passed at build time so a debug build can talk to
/// Firebase without Play Integrity:
/// `flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=<token from the console>`.
const String _appCheckDebugToken = String.fromEnvironment(
  'APP_CHECK_DEBUG_TOKEN',
);

/// Brings Firebase up so the AI import flows have an authenticated channel to
/// Gemini. Firebase is used *only* as that channel — no person, note, photo or
/// match ever leaves Hive, so the app stays exactly as local-first as it was.
///
/// Every failure here is swallowed and recorded in [isReady] rather than
/// thrown. A device with no network, no Play Services, or a project that is
/// still half-configured must still get the whole app; it just won't be
/// offered the AI import option. Startup correctness beats the feature.
abstract final class FirebaseBootstrap {
  static bool _isReady = false;
  static Object? _failure;

  /// Whether Firebase came up far enough for AI calls to be attempted. The
  /// "הוספה באמצעות AI" entry points check this before offering themselves.
  static bool get isReady => _isReady;

  /// What went wrong when [isReady] is false. Kept for a diagnostics line in
  /// Settings; never shown as a blocking error.
  static Object? get failure => _failure;

  /// The anonymous uid for this device, or null when Firebase is not ready.
  ///
  /// Anonymous auth is on from day one even though nothing is signed in yet:
  /// it gives every device a stable uid for App Check and the future per-user
  /// AI quota, and when Google Sign-In is added later it becomes a
  /// `linkWithCredential` that keeps the same uid instead of a migration.
  static String? get uid =>
      _isReady ? FirebaseAuth.instance.currentUser?.uid : null;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await _activateAppCheck();
      await _ensureSignedIn();
      _isReady = true;
      _failure = null;
    } catch (error, stackTrace) {
      _isReady = false;
      _failure = error;
      debugPrint('Firebase bootstrap failed: $error\n$stackTrace');
    }
  }

  /// App Check must be active before any Firebase AI call, so that Gemini
  /// access is bound to genuine installs of this app rather than to anyone who
  /// extracts the config out of the APK.
  static Future<void> _activateAppCheck() async {
    final String? debugToken = _appCheckDebugToken.trim().isEmpty
        ? null
        : _appCheckDebugToken.trim();

    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? AndroidDebugProvider(debugToken: debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? AppleDebugProvider(debugToken: debugToken)
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  }

  /// Waits for a persisted session to be restored before creating a new one.
  ///
  /// On iOS, Firebase Auth restores the user from the Keychain asynchronously,
  /// so `currentUser` is still null right after `initializeApp()`. Reading it
  /// synchronously races the restore and calls `signInAnonymously()` on every
  /// launch — which always mints a *new* uid and overwrites the stored session.
  /// Awaiting the first auth-state event lets the restore finish; the timeout
  /// keeps a stalled stream from holding up startup.
  static Future<void> _ensureSignedIn() async {
    final User? restoredUser = await FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => FirebaseAuth.instance.currentUser,
        );
    if (restoredUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  }
}
