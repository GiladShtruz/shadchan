import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// Whether this device has an account on it.
///
/// **Local, and deliberately not derived from the account.** The router has to
/// answer "does this launch open on the sign-in screen?" on the *first frame*,
/// and the honest answer to "is somebody signed in?" is a Firebase round trip.
/// Reading it there would drag `Firebase.initializeApp`, App Check and the auth
/// restore onto the cold start, which is exactly what `FirebaseBootstrap`'s
/// whole design exists to avoid. So the gate is a flag this device writes when
/// the question is answered, either way, and [SignInScreen] takes itself out of
/// the way if an account turns out to be connected after all.
///
/// Every write goes through [persistHomeSetting] for the reason documented on
/// `CommunityProfileStore`: a `Box.put` started inside a widget test's
/// fake-async zone is never driven to completion and hangs `Hive.close()`
/// forever. `_pending` covers the frame between writing a value and it landing
/// in the box.
abstract final class SignInPromptStore {
  static const String _answeredKey = 'signIn.promptAnswered';
  static const String _hasAccountKey = 'signIn.hasAccount';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static final Map<String, Object?> _pending = <String, Object?>{};

  static Object? _read(String key) => _pending[key] ?? _box?.get(key);

  static void _write(String key, Object value) {
    _pending[key] = value;
    persistHomeSetting(key, value.toString());
  }

  /// Drops the write-through cache.
  ///
  /// A test process runs many launches through one static, and `_pending`
  /// outlives the Hive box it shadows — so a test that clears the box and
  /// expects a fresh install would otherwise still read the previous test's
  /// answer. Nothing in the app calls this: in a real process `_pending` and
  /// the box always agree.
  @visibleForTesting
  static void resetForTest() => _pending.clear();

  /// Whether this device is holding a signed-in account.
  ///
  /// **This is the gate now.** The flag it replaced — `hasAnswered` — recorded
  /// that the question had been *asked*, because the answer was allowed to be
  /// "no". The app has no local-only mode any more: every record belongs to an
  /// account, so what the router needs to know on the first frame is whether
  /// there is one.
  ///
  /// False for everybody on the launch after this ships, including matchmakers
  /// who signed in months ago — and that is deliberate rather than tolerated.
  /// `SignInScreen` sees `AccountProvider.isSignedIn` come back true a moment
  /// later, writes this flag and steps aside, so an existing account costs one
  /// frame of a screen nobody has to touch. Guessing instead would mean either
  /// letting a signed-out install through or making a signed-in one sign in
  /// again.
  static bool get hasAccount =>
      _read(_hasAccountKey) == true || _read(_hasAccountKey) == 'true';

  /// Records that an account is connected on this device.
  static void markSignedIn() {
    _write(_hasAccountKey, true);
    // Kept in step for the sake of anything still reading the old flag, and so
    // that a downgrade to a build with the optional gate does not re-ask.
    _write(_answeredKey, true);
  }

  /// Records that the account was disconnected, which sends the next launch —
  /// and the current one — back to [SignInScreen].
  static void markSignedOut() => _write(_hasAccountKey, false);
}
