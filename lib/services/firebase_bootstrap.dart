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

/// Whether App Check is wired up at all.
///
/// Off while the Play Integrity side of the project is still unconfigured. A
/// registered provider that cannot attest is worse than no provider: the first
/// exchange is refused, the SDK throttles itself, and every AI call after it
/// fails with "Too many attempts" — so the feature is simply gone for everyone
/// who installed from the store. Skipping `activate` sends the request with no
/// App Check token instead, which the backend accepts for as long as
/// enforcement stays off in the console. Those two therefore switch together:
/// build with `--dart-define=APP_CHECK_ENABLED=true` only once enforcement is
/// meant to be on.
const bool _appCheckEnabled = bool.fromEnvironment('APP_CHECK_ENABLED');

/// Brings Firebase up so the AI import flows have an authenticated channel to
/// Gemini. Firebase is used *only* as that channel — no person, note, photo or
/// match ever leaves Hive, so the app stays exactly as local-first as it was.
///
/// Every failure here is swallowed and recorded in [isReady] rather than
/// thrown. A device with no network, no Play Services, or a project that is
/// still half-configured must still get the whole app; it just won't be
/// offered the AI import option. Startup correctness beats the feature.
abstract final class FirebaseBootstrap {
  static Object? _failure;

  /// Whether Firebase came up far enough for AI calls to be attempted.
  ///
  /// Listenable, because startup does not wait for it: the AI entry points are
  /// built before this is known and have to switch themselves on when it
  /// lands, rather than staying disabled for the life of the session.
  static final ValueNotifier<bool> readyListenable = ValueNotifier<bool>(false);

  static bool get isReady => readyListenable.value;

  /// What went wrong when [isReady] is false. Kept for a diagnostics line in
  /// Settings; never shown as a blocking error.
  static Object? get failure => _failure;

  /// The result of this process's **first** App Check token exchange: null once
  /// it succeeded, a message while it has not.
  ///
  /// It is recorded here because the first refusal is the only one that says
  /// anything. After it, the SDK throttles itself and answers every later call
  /// — including the one inside the AI request, which is the one the user sees
  /// — with "Too many attempts", a sentence about our own rate limiter rather
  /// than about the device. Reports were arriving with the second error and no
  /// trace of the first.
  static String? get appCheckError => _appCheckError;

  static String? _appCheckError = 'לא נבדק';

  /// The uid for this device, or null when Firebase is not ready.
  ///
  /// Anonymous auth is on from day one: it gives every device a stable uid for
  /// App Check and the per-user AI quota before anyone has signed in to
  /// anything. Signing in with Google upgrades that same account through
  /// `linkWithCredential` (see `AccountService`), so this uid survives the
  /// upgrade rather than being replaced.
  static String? get uid =>
      isReady ? FirebaseAuth.instance.currentUser?.uid : null;

  /// A backstop, not a budget. Nothing waits on this — the deadline only
  /// exists so a step that hangs forever eventually records a failure instead
  /// of leaving the feature in limbo with no explanation.
  static const Duration _deadline = Duration(seconds: 30);

  static Future<void>? _pending;

  /// Brings Firebase up, once, the first time something actually needs it.
  ///
  /// Deliberately not called from startup. Even unawaited, `initializeApp`,
  /// App Check activation and the auth restore all do heavy platform-channel
  /// work that competes with building the first frame — and awaiting them was
  /// worse still, opening the app to a white screen when a step hung instead
  /// of failing. Nothing outside the AI import needs Firebase, so it waits
  /// until an AI screen asks for it and reports itself through
  /// [readyListenable].
  ///
  /// Safe to call repeatedly: concurrent callers share one attempt, and a
  /// failed attempt can be retried by calling again.
  static Future<void> ensureReady() {
    if (isReady) {
      return Future<void>.value();
    }
    return _pending ??= _initialize();
  }

  static Future<void> _initialize() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      await _connect().timeout(_deadline);
      _failure = null;
      readyListenable.value = true;
      debugPrint(
        'AI_IMPORT firebase ready in ${watch.elapsedMilliseconds}ms uid=$uid',
      );
    } catch (error, stackTrace) {
      _failure = error;
      readyListenable.value = false;
      debugPrint(
        'AI_IMPORT firebase FAILED after ${watch.elapsedMilliseconds}ms: '
        '$error\n$stackTrace',
      );
      // Cleared so a later attempt can retry — the usual cause is no network,
      // which is exactly the kind of thing that fixes itself.
      _pending = null;
    }
  }

  static Future<void> _connect() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await _activateAppCheck();
    await _ensureSignedIn();
  }

  /// Activates App Check, when this build has it turned on, before any
  /// Firebase AI call — so that Gemini access is bound to genuine installs of
  /// this app rather than to anyone who extracts the config out of the APK.
  ///
  /// Returning early is never an error: it leaves the AI calls unattested,
  /// which is the same position the app was in before App Check existed.
  static Future<void> _activateAppCheck() async {
    if (!_appCheckEnabled) {
      debugPrint('AI_IMPORT App Check disabled at build time');
      _appCheckError = 'מבוטל';
      return;
    }

    final String? debugToken = _appCheckDebugToken.trim().isEmpty
        ? null
        : _appCheckDebugToken.trim();

    // A debug build with no registered token cannot attest, and trying anyway
    // is not a no-op: the exchange is refused with a 403 that surfaces as a
    // failure of the AI call itself, then the SDK rate-limits and every later
    // attempt returns "Too many attempts". Skipping is honest about what this
    // build can do. Release builds always attest through Play Integrity, and
    // pass a token here via
    // `--dart-define=APP_CHECK_DEBUG_TOKEN=…` when a debug build needs to.
    if (kDebugMode && debugToken == null) {
      debugPrint(
        'AI_IMPORT App Check skipped: debug build with no APP_CHECK_DEBUG_TOKEN',
      );
      _appCheckError = 'דולג (debug בלי טוקן)';
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? AndroidDebugProvider(debugToken: debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? AppleDebugProvider(debugToken: debugToken)
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    _probeAppCheck();
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  }

  /// Asks for a token now, only to find out whether asking works.
  ///
  /// Deliberately not awaited: nothing here needs the token — the AI call
  /// fetches its own — and Play Integrity can take seconds, which would be
  /// seconds added to every AI screen for a diagnostic. What matters is only
  /// that this is the *first* request of the process, so it is the one that
  /// gets the real answer rather than the throttled one.
  static void _probeAppCheck() {
    FirebaseAppCheck.instance.getToken().then(
      (String? token) {
        _appCheckError = token == null ? 'לא הוחזר טוקן' : null;
      },
      onError: (Object error) {
        _appCheckError = '$error';
        debugPrint('AI_IMPORT App Check attestation failed: $error');
      },
    );
  }

  /// Signs back in anonymously after a sign-out.
  ///
  /// The app is never deliberately left without a uid: App Check and the AI
  /// import both need one, and signing out of a Google account is meant to
  /// cost the cloud backup, not the rest of the app. A failure is swallowed
  /// for the same reason every other failure here is — the caller is a button
  /// in Settings, not a gate on the app working.
  static Future<void> restoreAnonymousSession() async {
    if (!isReady) {
      return;
    }
    try {
      await _ensureSignedIn();
    } catch (error) {
      debugPrint('AI_IMPORT anonymous re-sign-in failed: $error');
    }
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
