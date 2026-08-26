import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shadchan/firebase_options.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Signing the matchmaker in with Google, on top of the anonymous account
/// [FirebaseBootstrap] already keeps.
///
/// Why this exists at all: the anonymous uid is a *device* identity. It lives
/// in the Keychain / app storage and dies with an uninstall, so anything hung
/// off it — a cloud backup above all — would be unrecoverable exactly when it
/// is needed. Google Sign-In gives the same person the same uid on the next
/// phone, which is what makes a backup a backup rather than a second copy that
/// is lost with the first.
///
/// The anonymous account is *upgraded*, not replaced: `linkWithCredential`
/// keeps the existing uid, so anything already written under it (today the AI
/// quota, tomorrow the backup) stays where it is instead of needing a
/// migration.
abstract final class AccountService {
  /// The project's **web** OAuth client id, from `oauth_client` with
  /// `client_type: 3` in `android/app/google-services.json`.
  ///
  /// Android's Credential Manager mints the id token for this audience rather
  /// than for the Android client, and Firebase will only accept a token issued
  /// to one of the project's own clients. The Android plugin can also read it
  /// from the `default_web_client_id` resource the google-services Gradle
  /// plugin generates, but a mismatch there fails as an opaque platform error
  /// at the moment of signing in — naming it here keeps the audience visible
  /// next to the code that depends on it.
  static const String _serverClientId =
      '769854167286-sjvi4i4petocs4mi1ousrpp7nuq38k8m.apps.googleusercontent.com';

  static Future<void>? _googleInitialization;

  /// `GoogleSignIn.instance.initialize` must run once before anything else on
  /// the plugin, and must not run twice. A failed attempt clears itself so a
  /// later sign-in can retry.
  static Future<void> _ensureGoogleInitialized() {
    return _googleInitialization ??= _initializeGoogle();
  }

  static Future<void> _initializeGoogle() async {
    try {
      await GoogleSignIn.instance.initialize(
        // iOS resolves its own client from GoogleService-Info.plist, but only
        // when it is passed in; Android has no iOS client and must not get one.
        clientId: Platform.isIOS
            ? DefaultFirebaseOptions.ios.iosClientId
            : null,
        serverClientId: _serverClientId,
      );
    } catch (_) {
      _googleInitialization = null;
      rethrow;
    }
  }

  /// Opens the Google account picker and attaches the chosen account to the
  /// Firebase user.
  ///
  /// Never throws: every failure comes back as a [AccountSignInResult] with a
  /// Hebrew sentence, because every caller is a button.
  static Future<AccountSignInResult> signInWithGoogle() async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return const AccountSignInResult.failure(
        'לא הצלחנו להתחבר. יש לוודא חיבור לאינטרנט ולנסות שוב.',
      );
    }

    try {
      await _ensureGoogleInitialized();

      // False on platforms with no interactive flow (the web plugin, which
      // renders its own button). Checked rather than assumed so the failure is
      // a sentence instead of an exception.
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        return const AccountSignInResult.failure(
          'התחברות עם Google אינה נתמכת במכשיר הזה.',
        );
      }

      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        return const AccountSignInResult.failure(
          'ההתחברות לא הושלמה. כדאי לנסות שוב.',
          details:
              'google/no-id-token\n'
              'החשבון נבחר אך לא הוחזר idToken — סימן שמזהה הלקוח (serverClientId) '
              'או טביעת האצבע של החתימה אינם רשומים בפרויקט.',
        );
      }

      await _attachToFirebase(GoogleAuthProvider.credential(idToken: idToken));
      return const AccountSignInResult.success();
    } on GoogleSignInException catch (error) {
      final String details = _describe(
        'google',
        error.code.name,
        error.description,
        error.details,
      );
      debugPrint('ACCOUNT google sign-in failed: $details');
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return AccountSignInResult.canceled(details);
      }
      return AccountSignInResult.failure(
        _googleMessage(error.code),
        details: details,
      );
    } on FirebaseAuthException catch (error) {
      final String details = _describe(
        'firebase',
        error.code,
        error.message,
        null,
      );
      debugPrint('ACCOUNT firebase sign-in failed: $details');
      return AccountSignInResult.failure(
        _firebaseMessage(error.code),
        details: details,
      );
    } catch (error, stackTrace) {
      debugPrint('ACCOUNT sign-in failed: $error\n$stackTrace');
      return AccountSignInResult.failure(
        'לא הצלחנו להתחבר. כדאי לנסות שוב.',
        details: _describe(
          'unexpected',
          error.runtimeType.toString(),
          '$error',
          null,
        ),
      );
    }
  }

  /// The technical one-liner behind a Hebrew sentence.
  ///
  /// It exists because the interesting half of an Android sign-in failure is in
  /// the platform's own text and nowhere else: a release build signed with a
  /// certificate the Firebase project does not know answers the account picker
  /// with `10: … Developer console is not set up correctly`, and every code
  /// path above would otherwise flatten that into "כדאי לנסות שוב".
  static String _describe(
    String source,
    String code,
    String? description,
    Object? extra,
  ) {
    final StringBuffer buffer = StringBuffer('$source/$code');
    if (description != null && description.isNotEmpty) {
      buffer.write('\n$description');
    }
    if (extra != null) {
      buffer.write('\n$extra');
    }
    return buffer.toString();
  }

  /// Whether "המשך עם Apple" may be drawn at all.
  ///
  /// **iOS and macOS only, deliberately.** Apple's own sheet exists there and
  /// needs nothing but the entitlement the Runner target already carries. On
  /// Android the same package falls back to Apple's *web* flow, which needs a
  /// Services ID and a return URL registered in the Apple Developer portal and
  /// in the Firebase console — and until they are, the button opens a browser
  /// that ends on `invalid_client`. A button that cannot work is worse than no
  /// button, so Android is offered Google and an address instead. Turning it on
  /// later is this getter plus the console work, and nothing else in the app.
  ///
  /// It is also the reason iOS *must* keep this: App Store review requires
  /// Sign in with Apple wherever a third-party sign-in is offered.
  static bool get isAppleAvailable => Platform.isIOS || Platform.isMacOS;

  /// Opens Apple's sign-in sheet and attaches the account to the Firebase user.
  ///
  /// **This is not `AppleAuthProvider`, and that is the whole fix.** It used to
  /// go through `linkWithProvider(AppleAuthProvider())`, on the reading that
  /// one provider flow serves every platform. It does not: `signInWithProvider`
  /// is Firebase's *generic OAuth* path, and for `apple.com` that means the web
  /// flow — a browser sheet posting to a Services ID and a return URL that only
  /// exist once somebody has registered them in the Apple Developer portal.
  /// Neither is registered for this project, so on an iPhone the button opened
  /// a web page and came back with nothing. There was no crash and no Hebrew
  /// error worth showing; it simply never signed anybody in.
  ///
  /// The flow below is the one Firebase's own Flutter documentation prescribes:
  /// Apple's native sheet through `ASAuthorizationAppleIDProvider`, and the
  /// identity token it returns exchanged for a Firebase credential.
  ///
  /// **The nonce is not optional.** Apple signs the *hash* of it into the
  /// token, and Firebase re-derives the hash from the raw value handed to
  /// `credential`. Sending the raw nonce to Apple, or omitting it, is rejected
  /// as `invalid-credential` — which is the other way this can look like "Apple
  /// sign-in is broken".
  ///
  /// `email` and `fullName` are asked for because Apple only ever hands them
  /// over on the *first* authorisation for a given app; not asking means never
  /// being able to.
  ///
  /// Never throws, for the same reason [signInWithGoogle] does not: every
  /// caller is a button.
  static Future<AccountSignInResult> signInWithApple() async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return const AccountSignInResult.failure(
        'לא הצלחנו להתחבר. יש לוודא חיבור לאינטרנט ולנסות שוב.',
      );
    }
    if (!isAppleAvailable) {
      return const AccountSignInResult.failure(
        'התחברות עם Apple אינה נתמכת במכשיר הזה.',
      );
    }

    try {
      final String rawNonce = _newNonce();
      final AuthorizationCredentialAppleID apple =
          await SignInWithApple.getAppleIDCredential(
            scopes: <AppleIDAuthorizationScopes>[
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
            nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
          );

      final String? idToken = apple.identityToken;
      if (idToken == null) {
        return const AccountSignInResult.failure(
          'ההתחברות לא הושלמה. כדאי לנסות שוב.',
          details:
              'apple/no-identity-token\n'
              'Apple אישרה את הבקשה אך לא החזירה identityToken.',
        );
      }

      await _attachToFirebase(
        OAuthProvider(
          'apple.com',
        ).credential(idToken: idToken, rawNonce: rawNonce),
      );
      return const AccountSignInResult.success();
    } on SignInWithAppleAuthorizationException catch (error) {
      final String details = _describe(
        'apple',
        error.code.name,
        error.message,
        null,
      );
      debugPrint('ACCOUNT apple sign-in failed: $details');
      // Closing Apple's own sheet is an answer, not a failure, and must stay
      // silent.
      if (error.code == AuthorizationErrorCode.canceled) {
        return AccountSignInResult.canceled(details);
      }
      return AccountSignInResult.failure(
        _appleAuthorizationMessage(error.code),
        details: details,
      );
    } on SignInWithAppleNotSupportedException catch (error) {
      return AccountSignInResult.failure(
        'התחברות עם Apple אינה נתמכת במכשיר הזה.',
        details: _describe('apple', 'not-supported', error.message, null),
      );
    } on FirebaseAuthException catch (error) {
      final String details = _describe(
        'firebase-apple',
        error.code,
        error.message,
        null,
      );
      debugPrint('ACCOUNT apple sign-in failed: $details');
      return AccountSignInResult.failure(
        _appleMessage(error.code),
        details: details,
      );
    } catch (error, stackTrace) {
      debugPrint('ACCOUNT apple sign-in failed: $error\n$stackTrace');
      return AccountSignInResult.failure(
        'לא הצלחנו להתחבר. כדאי לנסות שוב.',
        details: _describe(
          'unexpected',
          error.runtimeType.toString(),
          '$error',
          null,
        ),
      );
    }
  }

  /// A fresh random string for one Apple authorisation.
  ///
  /// Cryptographically random, because its whole job is to make the token
  /// Apple signs unusable for any other sign-in attempt.
  static String _newNonce([int length = 32]) {
    const String alphabet =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  // --- An address and a password ------------------------------------------

  /// The shortest password Firebase will accept, said in Hebrew before it is
  /// refused in English.
  static const int minPasswordLength = 6;

  /// Signs in to an account that already exists.
  ///
  /// **Not `link`, on purpose.** An address and a password are what somebody
  /// arriving on a *new phone* types, and their records are already in the
  /// account behind them; linking would attach the address to this device's
  /// throwaway anonymous uid and leave the real account untouched. Registration
  /// — [registerWithEmail] — is the one that upgrades in place.
  static Future<AccountSignInResult> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _email(() async {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    });
  }

  /// Creates a new account from an address and a password.
  ///
  /// The anonymous account is upgraded in place where there is one, for the
  /// same reason Google's is: anything already written under that uid — the AI
  /// quota above all — stays where it is instead of needing a migration.
  static Future<AccountSignInResult> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _email(() async {
      final AuthCredential credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      final User? current = FirebaseAuth.instance.currentUser;
      if (current != null && current.isAnonymous) {
        await current.linkWithCredential(credential);
        return;
      }
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    });
  }

  /// Sends the "forgotten password" mail. Answers `success` when it went out.
  static Future<AccountSignInResult> sendPasswordReset(String email) {
    return _email(
      () => FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim()),
    );
  }

  /// The three address flows share one shape: bring Firebase up, run the call,
  /// and turn every way it can fail into a Hebrew sentence.
  static Future<AccountSignInResult> _email(Future<void> Function() run) async {
    await FirebaseBootstrap.ensureReady();
    if (!FirebaseBootstrap.isReady) {
      return const AccountSignInResult.failure(
        'לא הצלחנו להתחבר. יש לוודא חיבור לאינטרנט ולנסות שוב.',
      );
    }

    try {
      await run();
      return const AccountSignInResult.success();
    } on FirebaseAuthException catch (error) {
      final String details = _describe(
        'email',
        error.code,
        error.message,
        null,
      );
      debugPrint('ACCOUNT email auth failed: $details');
      return AccountSignInResult.failure(
        _emailMessage(error.code),
        details: details,
      );
    } catch (error, stackTrace) {
      debugPrint('ACCOUNT email auth failed: $error\n$stackTrace');
      return AccountSignInResult.failure(
        'לא הצלחנו להתחבר. כדאי לנסות שוב.',
        details: _describe(
          'unexpected',
          error.runtimeType.toString(),
          '$error',
          null,
        ),
      );
    }
  }

  /// Upgrades the anonymous account in place when it can, and falls back to a
  /// plain sign-in when it cannot.
  ///
  /// `credential-already-in-use` is the ordinary case, not an error: it means
  /// this Google account already has a Firebase account from a previous
  /// install or another phone. Signing into *that* account is exactly what
  /// someone restoring a backup wants — the throwaway anonymous uid on this
  /// device is what should be abandoned, not the account holding their data.
  static Future<void> _attachToFirebase(AuthCredential credential) async {
    final User? current = FirebaseAuth.instance.currentUser;
    if (current == null || !current.isAnonymous) {
      await FirebaseAuth.instance.signInWithCredential(credential);
      return;
    }

    try {
      await current.linkWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'credential-already-in-use' &&
          error.code != 'email-already-in-use' &&
          error.code != 'provider-already-linked') {
        rethrow;
      }
      await FirebaseAuth.instance.signInWithCredential(credential);
    }
  }

  /// Signs out of Google and drops back to a fresh anonymous account.
  ///
  /// It drops back rather than leaving the app unauthenticated because the AI
  /// import still needs *some* uid to call Gemini through; signing out of the
  /// Google account should cost the backup, not the rest of the app.
  static Future<void> signOut() async {
    if (FirebaseBootstrap.isReady) {
      await FirebaseAuth.instance.signOut();
    }
    try {
      await _ensureGoogleInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (error) {
      // Firebase is already signed out at this point, which is the part that
      // matters; a stale Google session only means the picker will preselect
      // the account next time.
      debugPrint('ACCOUNT google sign-out failed: $error');
    }
    await FirebaseBootstrap.restoreAnonymousSession();
  }

  static String _googleMessage(GoogleSignInExceptionCode code) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled ||
      GoogleSignInExceptionCode.interrupted => 'ההתחברות לא הושלמה.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'ההתחברות עם Google אינה זמינה כרגע.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'לא הצלחנו לפתוח את מסך ההתחברות. כדאי לנסות שוב.',
      _ => 'לא הצלחנו להתחבר. כדאי לנסות שוב.',
    };
  }

  static String _appleAuthorizationMessage(AuthorizationErrorCode code) {
    return switch (code) {
      AuthorizationErrorCode.canceled => 'ההתחברות לא הושלמה.',
      AuthorizationErrorCode.notHandled ||
      AuthorizationErrorCode.notInteractive =>
        'לא הצלחנו לפתוח את מסך ההתחברות של Apple. כדאי לנסות שוב.',
      AuthorizationErrorCode.invalidResponse =>
        'Apple החזירה תשובה שלא הצלחנו לקרוא. כדאי לנסות שוב.',
      _ => 'לא הצלחנו להתחבר עם Apple. כדאי לנסות שוב.',
    };
  }

  static String _emailMessage(String code) {
    return switch (code) {
      'invalid-email' => 'כתובת המייל אינה תקינה.',
      'email-already-in-use' =>
        'הכתובת הזו כבר רשומה. אפשר להתחבר איתה עם הסיסמה שנבחרה.',
      'weak-password' =>
        'הסיסמה קצרה מדי. צריך לפחות $minPasswordLength תווים.',
      // Firebase stopped distinguishing "no such user" from "wrong password" on
      // purpose — telling somebody an address is not registered is telling
      // whoever is holding the phone which addresses are. One sentence covers
      // all three codes, as it should.
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'המייל או הסיסמה אינם נכונים.',
      'user-disabled' => 'החשבון הזה חסום.',
      'too-many-requests' =>
        'היו יותר מדי ניסיונות. כדאי לנסות שוב בעוד כמה דקות.',
      'network-request-failed' => 'אין חיבור לאינטרנט. יש להתחבר ולנסות שוב.',
      'operation-not-allowed' =>
        'ההתחברות עם מייל וסיסמה עדיין לא הופעלה בפרויקט.',
      _ => 'לא הצלחנו להתחבר. כדאי לנסות שוב.',
    };
  }

  static String _appleMessage(String code) {
    return switch (code) {
      'account-exists-with-different-credential' =>
        'לכתובת הזו כבר יש חשבון עם דרך התחברות אחרת.',
      'network-request-failed' => 'אין חיבור לאינטרנט. יש להתחבר ולנסות שוב.',
      'operation-not-allowed' => 'ההתחברות עם Apple עדיין לא הופעלה בפרויקט.',
      'user-disabled' => 'החשבון הזה חסום.',
      _ => 'לא הצלחנו להתחבר. כדאי לנסות שוב.',
    };
  }

  static String _firebaseMessage(String code) {
    return switch (code) {
      'account-exists-with-different-credential' =>
        'לכתובת הזו כבר יש חשבון עם דרך התחברות אחרת.',
      'network-request-failed' => 'אין חיבור לאינטרנט. יש להתחבר ולנסות שוב.',
      'operation-not-allowed' => 'ההתחברות עם Google עדיין לא הופעלה בפרויקט.',
      'user-disabled' => 'החשבון הזה חסום.',
      _ => 'לא הצלחנו להתחבר. כדאי לנסות שוב.',
    };
  }
}

/// What came back from a sign-in attempt.
///
/// [canceled] is separate from [failure] so a closed account picker is silent
/// — it is the user's own answer, not something that went wrong.
enum AccountSignInOutcome { success, canceled, failure }

class AccountSignInResult {
  const AccountSignInResult.success()
    : outcome = AccountSignInOutcome.success,
      message = null,
      details = null;

  const AccountSignInResult.canceled([this.details])
    : outcome = AccountSignInOutcome.canceled,
      message = null;

  const AccountSignInResult.failure(String this.message, {this.details})
    : outcome = AccountSignInOutcome.failure;

  final AccountSignInOutcome outcome;

  /// A Hebrew sentence to show, on [AccountSignInOutcome.failure] only.
  final String? message;

  /// The untranslated platform error, for the "פרטים טכניים" dialog.
  ///
  /// Kept apart from [message] on purpose: nobody should be shown a Credential
  /// Manager stack trace by default, and nobody debugging a release build
  /// should have to go without one.
  final String? details;
}
