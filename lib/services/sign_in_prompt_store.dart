import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// Whether the matchmaker has been asked, once, to connect an account — and
/// when it is fair to mention it again.
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
  static const String _remindedAtKey = 'signIn.remindedAtFriends';

  /// The database size at which a matchmaker who skipped is reminded, gently
  /// and once, that nothing they have built is backed up.
  ///
  /// Twenty-five, because that is roughly where a list stops being an
  /// experiment and starts being work somebody would be upset to lose. Earlier
  /// than that the reminder is a sales pitch about a database of four people.
  static const int remindFromFriends = 25;

  /// How much the database has to grow before the reminder may come back.
  ///
  /// It is measured in friends rather than in days on purpose: a matchmaker who
  /// has not added anybody since being asked has not acquired a new reason to
  /// be asked, however long ago it was.
  static const int remindAgainAfterFriends = 75;

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

  /// Whether the one-time sign-in screen has had an answer — signing in, or
  /// choosing to carry on without.
  ///
  /// False for everybody on the launch after this feature ships, which is the
  /// point: existing matchmakers see the screen once too.
  static bool get hasAnswered =>
      _read(_answeredKey) == true || _read(_answeredKey) == 'true';

  /// Records that the question has been answered, however it was answered.
  ///
  /// **Signing in and skipping both count.** The screen is not a gate to get
  /// past, and somebody who chose to stay local must not be shown it again on
  /// every launch until they give in.
  static void markAnswered() => _write(_answeredKey, true);

  // --- The gentle reminder afterwards --------------------------------------

  /// The database size the last reminder was shown at, or zero.
  static int get remindedAtFriends {
    final Object? raw = _read(_remindedAtKey);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  /// Whether it is fair to mention signing in again at [friends] friends.
  ///
  /// Never on the launch somebody skipped — [hasAnswered] alone does not gate
  /// this, [remindFromFriends] does, and a database that small belongs to
  /// somebody who has just arrived.
  static bool shouldRemind(int friends) {
    if (friends < remindFromFriends) {
      return false;
    }
    final int last = remindedAtFriends;
    if (last == 0) {
      return true;
    }
    return friends - last >= remindAgainAfterFriends;
  }

  static void markReminded(int friends) =>
      _write(_remindedAtKey, friends <= 0 ? 1 : friends);
}
