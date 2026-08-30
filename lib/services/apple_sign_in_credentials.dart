import 'package:firebase_auth/firebase_auth.dart';

/// Builds the native Apple credential shape expected by Firebase Auth.
///
/// `OAuthProvider('apple.com').credential` looks similar, but it creates a
/// generic `oauth` sign-in method. On Apple platforms that takes a different
/// native Firebase branch and can be rejected as an invalid OAuth response.
/// The dedicated builder below reaches Firebase's Apple-specific branch and
/// carries the name Apple returns only on the first authorization.
OAuthCredential createAppleFirebaseCredential({
  required String idToken,
  required String rawNonce,
  String? givenName,
  String? familyName,
}) {
  return AppleAuthProvider.credentialWithIDToken(
    idToken,
    rawNonce,
    AppleFullPersonName(givenName: givenName, familyName: familyName),
  );
}

/// Returns Firebase's replacement after an Apple link attempt consumes the
/// original credential.
///
/// Apple credentials are single-use. When linking one to the bootstrap
/// anonymous user reports that the Apple identity already belongs to an
/// existing Firebase account, the original credential must not be submitted
/// again. Firebase puts a fresh credential on the exception for the follow-up
/// sign-in. Failing closed when it is absent is safer than an invalid replay.
AuthCredential resolveAppleCredentialAfterLinkFailure(
  FirebaseAuthException error,
) {
  final AuthCredential? updatedCredential = error.credential;
  if (updatedCredential != null) {
    return updatedCredential;
  }
  throw FirebaseAuthException(
    code: 'apple-updated-credential-missing',
    message:
        'Firebase did not return the updated Apple credential required after '
        'the link attempt.',
  );
}
