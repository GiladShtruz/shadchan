import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/support_service.dart';

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

  /// Whether this is an account that reviews community tips.
  ///
  /// The same people who may open the feedback console, because approving a tip
  /// is one of the things done there — `firestore.rules` asks exactly the same
  /// question of the verified token.
  bool get isTipsAdmin => isSupportAdmin;

  /// Whether this account may open the feedback console.
  ///
  /// This cannot be answered from a constant: the whole point of the console is
  /// that administrators are added by address without a new build, so the
  /// answer lives in Firestore and is re-read whenever the signed-in user
  /// changes. Until that read returns it is false, which shows one settings row
  /// a moment late rather than showing it to the wrong person.
  ///
  /// A display gate only. The rule that actually matters is in
  /// `firestore.rules`, which checks the same verified address on the server —
  /// flipping this in a patched client buys a screen full of buttons that every
  /// write refuses.
  bool get isSupportAdmin => _isSupportAdmin;

  bool _isSupportAdmin = false;

  String? get displayName => _google?.displayName ?? _user?.displayName;

  /// The sign-in methods attached to this account: `google.com`, `apple.com`,
  /// `password`.
  Set<String> get providerIds => <String>{
    for (final UserInfo info in _user?.providerData ?? const <UserInfo>[])
      info.providerId,
  };

  bool get hasPassword => providerIds.contains('password');

  /// The address the account is known by — the one any of its methods share.
  String? get accountEmail {
    final String? own = _user?.email;
    if (own != null && own.isNotEmpty) {
      return own;
    }
    for (final UserInfo info in _user?.providerData ?? const <UserInfo>[]) {
      final String? email = info.email;
      if (email != null && email.isNotEmpty) {
        return email;
      }
    }
    return null;
  }

  bool get emailVerified => _user?.emailVerified ?? false;

  /// When the account will be erased, while it is waiting for deletion.
  DateTime? get deletionDue => _deletionDue;
  DateTime? _deletionDue;

  /// Asks Firebase again whether the address was verified, and lifts the gate
  /// when it was.
  Future<bool> refreshVerification() async {
    final bool verified = await AccountService.refreshVerification();
    _refreshUser();
    if (verified) {
      SignInPromptStore.setMustVerifyEmail(false);
    }
    return verified;
  }

  Future<AccountSignInResult> resendVerification() =>
      _signIn(AccountService.resendVerification);

  Future<AccountSignInResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _signIn(
    () => AccountService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    ),
  );

  Future<AccountSignInResult> linkGoogle() =>
      _signIn(AccountService.linkGoogle);

  Future<AccountSignInResult> linkApple() => _signIn(AccountService.linkApple);

  Future<AccountSignInResult> linkPassword(String password) =>
      _signIn(() => AccountService.linkPassword(password));

  Future<AccountSignInResult> unlink(String providerId) =>
      _signIn(() => AccountService.unlink(providerId));

  /// Re-reads whether this account is waiting for deletion. Run whenever the
  /// signed-in user changes, so a phone that was away hears about a deletion
  /// another phone asked for.
  Future<void> refreshDeletionState() async {
    if (!isSignedIn) {
      return;
    }
    try {
      final DateTime? due = await AccountService.pendingDeletion();
      _deletionDue = due;
      SignInPromptStore.setDeletionPending(due != null);
      notifyListeners();
    } on Object catch (error) {
      debugPrint('ACCOUNT deletion state unreadable: $error');
    }
  }

  /// Takes the account back out of deletion.
  Future<bool> cancelDeletion() async {
    final bool done = await AccountService.cancelDeletion();
    if (done) {
      _deletionDue = null;
      SignInPromptStore.setDeletionPending(false);
      notifyListeners();
    }
    return done;
  }

  String? get photoUrl => _google?.photoURL ?? _user?.photoURL;

  /// Email/password accounts need their password typed before deletion. The
  /// provider id comes from Firebase itself, not from whichever button was
  /// last pressed, so it remains correct after an app restart.
  bool get deletionRequiresPassword {
    final User? user = _user;
    if (user == null) {
      return false;
    }
    return AccountService.deletionAuthMethod(
          user.providerData.map((UserInfo info) => info.providerId),
        ) ==
        AccountDeletionAuthMethod.password;
  }

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

  /// The third way in, and the only one that needs no other company's account.
  ///
  /// Kept on the same [_signIn] path as the two providers so a spinner, a
  /// refused second tap and the refreshed user all behave identically however
  /// somebody signed in.
  Future<AccountSignInResult> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _signIn(
      () => AccountService.signInWithEmail(email: email, password: password),
    );
  }

  Future<AccountSignInResult> registerWithEmail({
    required String email,
    required String password,
  }) async {
    final AccountSignInResult result = await _signIn(
      () => AccountService.registerWithEmail(email: email, password: password),
    );
    if (result.outcome == AccountSignInOutcome.success) {
      // Said here rather than only worked out from the account: an anonymous
      // session upgraded into this account carries the anonymous one's
      // creation date, which can be older than the rule's starting date.
      SignInPromptStore.setMustVerifyEmail(true);
    }
    return result;
  }

  /// Sends the reset mail. Not a sign-in, but it shares the busy flag so the
  /// form cannot be worked while it is in flight.
  Future<AccountSignInResult> sendPasswordReset(String email) =>
      _signIn(() => AccountService.sendPasswordReset(email));

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

  Future<AccountDeletionResult> deleteAccount({
    required Future<bool> Function() deleteRemoteData,
    String? password,
    bool scheduleOnly = false,
  }) async {
    if (_isBusy) {
      return const AccountDeletionResult.canceled();
    }
    _setBusy(true);
    try {
      final AccountDeletionResult result = await AccountService.deleteAccount(
        deleteRemoteData: deleteRemoteData,
        password: password,
        scheduleOnly: scheduleOnly,
      );
      _refreshUser();
      return result;
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
    _userChanges = FirebaseAuth.instance.userChanges().listen((User? user) {
      _setUser(user, fromStream: true);
    });
    _refreshUser();
  }

  void _refreshUser() {
    _setUser(
      FirebaseBootstrap.isReady ? FirebaseAuth.instance.currentUser : null,
    );
  }

  void _setUser(User? user, {bool fromStream = false}) {
    final String? previousUid = _user?.uid;
    _user = user;
    if (fromStream &&
        user != null &&
        !user.isAnonymous &&
        user.uid != previousUid) {
      unawaited(refreshDeletionState());
    }
    if (fromStream) {
      _reconcileGate(user);
    }
    notifyListeners();
    unawaited(_refreshSupportAdmin());
  }

  /// Keeps the router's first-frame gate honest about this device.
  ///
  /// **The gate is a local flag, and a local flag can go stale.**
  /// `SignInPromptStore.hasAccount` is what decides on the very first frame
  /// whether the app opens on [SignInScreen] — it has to be local, because the
  /// honest answer is a Firebase round trip and asking for one there would drag
  /// the whole auth restore onto the cold start. The cost of that is a flag
  /// that goes on saying "yes" after the account it describes is gone: a
  /// deleted account, a revoked token, a sign-out that happened on another
  /// device. What is left is somebody using the app with an anonymous uid —
  /// which is precisely the state the app no longer has: nothing they do
  /// reaches the cloud backup, nothing they do reaches the community figures,
  /// and no screen tells them so.
  ///
  /// So the truth is written back whenever auth speaks. Only from the stream,
  /// never from [_refreshUser]: `currentUser` is null for the first second of
  /// every launch while the session is read back off disk, and marking a
  /// perfectly good account signed-out there would send everybody through the
  /// sign-in screen once per launch.
  void _reconcileGate(User? user) {
    if (user == null) {
      // Mid-transition. `FirebaseBootstrap` signs back in anonymously after a
      // sign-out, so the settled signed-out state is the anonymous one below
      // and this frame says nothing either way.
      return;
    }
    if (user.isAnonymous) {
      if (SignInPromptStore.hasAccount) {
        SignInPromptStore.markSignedOut();
      }
      return;
    }
    if (!SignInPromptStore.hasAccount) {
      SignInPromptStore.markSignedIn();
    }
    if (AccountService.mustVerifyEmail(user)) {
      SignInPromptStore.setMustVerifyEmail(true);
    } else if (!AccountService.couldNeedVerification(user)) {
      SignInPromptStore.setMustVerifyEmail(false);
    }
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
