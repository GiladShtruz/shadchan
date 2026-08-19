import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/services/tips_service.dart';

/// Who is signed in, for the screens that have to say so.
///
/// Deliberately the only place in the UI layer that touches `FirebaseAuth`.
/// Firebase does not exist at startup — [FirebaseBootstrap] brings it up the
/// first time something asks — so every read here is guarded by
/// `FirebaseBootstrap.isReady`; touching `FirebaseAuth.instance` before that
/// throws `No Firebase App '[DEFAULT]' has been created`.
class AccountProvider extends ChangeNotifier {
  /// Creating this provider is what starts Firebase, because the screen that
  /// watches it has to show whether an account is connected. That is off the
  /// startup path by construction: `MultiProvider` builds it on the first
  /// watch, which is the first time Settings is opened, not the first frame.
  ///
  /// [connect] exists only so a widget test can build the screen without it.
  /// `Firebase.initializeApp` never completes inside `testWidgets`' fake-async
  /// zone — the platform channel has no other side to reply from — so
  /// `ensureReady`'s 30-second deadline is left pending and fails the test with
  /// a pending timer. Passing `() async {}` skips the attempt; `isReady` is
  /// false either way, which is the state under test.
  AccountProvider({Future<void> Function()? connect})
    : _connect = connect ?? FirebaseBootstrap.ensureReady {
    FirebaseBootstrap.readyListenable.addListener(_handleReadyChanged);
    _handleReadyChanged();
    unawaited(_connect());
  }

  final Future<void> Function() _connect;

  StreamSubscription<User?>? _userChanges;
  User? _user;
  bool _isBusy = false;

  /// Whether Firebase came up at all. False means no network, no Play
  /// Services, or a half-configured project — the account section shows why
  /// rather than a button that cannot work.
  bool get isFirebaseReady => FirebaseBootstrap.isReady;

  /// Whether a real, durable account is connected. An anonymous user is not
  /// one: it is a device identity that dies with the install, which is the
  /// whole reason signing in exists.
  bool get isSignedIn {
    final User? user = _user;
    return user != null && !user.isAnonymous;
  }

  /// True while a sign-in or sign-out is in flight, so the tile can show a
  /// spinner and refuse a second tap.
  bool get isBusy => _isBusy;

  /// The Google address, which is the one thing that identifies the account to
  /// the person looking at it.
  ///
  /// Read from the Google provider entry rather than from `user.email`: an
  /// anonymous account upgraded through `linkWithCredential` keeps its own
  /// null profile fields, and only the linked provider carries the name and
  /// photo.
  String? get email => _google?.email ?? _user?.email;

  /// Whether this is the account that reviews community tips.
  ///
  /// A display gate only. The rule that actually matters is in
  /// `firestore.rules`, which checks the same verified address on the server —
  /// flipping this in a patched client buys a screen full of buttons that every
  /// write refuses.
  bool get isTipsAdmin => isSignedIn && TipsService.isAdminEmail(email);

  /// Whether this account may open the support console.
  ///
  /// Unlike [isTipsAdmin] this cannot be answered from a constant: the whole
  /// point of the console is that administrators are added by address without a
  /// new build, so the answer lives in Firestore and is re-read whenever the
  /// signed-in user changes. Until that read returns it is false, which shows
  /// one settings row a moment late rather than showing it to the wrong person.
  bool get isSupportAdmin => _isSupportAdmin;

  bool _isSupportAdmin = false;

  String? get displayName => _google?.displayName ?? _user?.displayName;

  String? get photoUrl => _google?.photoURL ?? _user?.photoURL;

  UserInfo? get _google {
    for (final UserInfo info in _user?.providerData ?? const <UserInfo>[]) {
      if (info.providerId == 'google.com') {
        return info;
      }
    }
    return null;
  }

  /// Whether "המשך עם Apple" may be drawn. See
  /// [AccountService.isAppleAvailable] for why it is not everywhere.
  bool get isAppleAvailable => AccountService.isAppleAvailable;

  Future<AccountSignInResult> signIn() =>
      _signIn(AccountService.signInWithGoogle);

  Future<AccountSignInResult> signInWithApple() =>
      _signIn(AccountService.signInWithApple);

  Future<AccountSignInResult> _signIn(
    Future<AccountSignInResult> Function() attempt,
  ) async {
    if (_isBusy) {
      return const AccountSignInResult.canceled();
    }
    _setBusy(true);
    try {
      final AccountSignInResult result = await attempt();
      _refreshUser();
      return result;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    if (_isBusy) {
      return;
    }
    _setBusy(true);
    try {
      await AccountService.signOut();
      _refreshUser();
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }

  /// Subscribes to auth once Firebase is up, and stays subscribed. `isReady`
  /// can also go back to false after a failed retry, so this handles both
  /// directions rather than assuming a one-way transition.
  void _handleReadyChanged() {
    if (!FirebaseBootstrap.isReady) {
      _userChanges?.cancel();
      _userChanges = null;
      _setUser(null);
      return;
    }
    if (_userChanges != null) {
      return;
    }
    // `userChanges` rather than `authStateChanges`: linking Google onto the
    // anonymous account does not change *which* user is signed in, only what
    // that user now carries, so the auth-state stream stays silent through the
    // one event this screen exists to show.
    _userChanges = FirebaseAuth.instance.userChanges().listen(_setUser);
    _refreshUser();
  }

  void _refreshUser() {
    _setUser(
      FirebaseBootstrap.isReady ? FirebaseAuth.instance.currentUser : null,
    );
  }

  void _setUser(User? user) {
    _user = user;
    notifyListeners();
    unawaited(_refreshSupportAdmin());
  }

  Future<void> _refreshSupportAdmin() async {
    final bool next = isSignedIn && await SupportService.isAdmin(email);
    if (_isSupportAdmin == next || _disposed) {
      return;
    }
    _isSupportAdmin = next;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    FirebaseBootstrap.readyListenable.removeListener(_handleReadyChanged);
    _userChanges?.cancel();
    super.dispose();
  }
}
