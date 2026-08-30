import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/apple_sign_in_credentials.dart';

void main() {
  group('Apple Firebase credentials', () {
    test(
      'uses the dedicated Apple sign-in method and keeps the first name',
      () {
        final OAuthCredential credential = createAppleFirebaseCredential(
          idToken: 'apple-id-token',
          rawNonce: 'raw-nonce',
          givenName: 'שרה',
          familyName: 'כהן',
        );

        expect(credential.providerId, 'apple.com');
        expect(credential.signInMethod, 'apple.com');
        expect(credential.signInMethod, isNot('oauth'));
        expect(credential.asMap(), <String, dynamic>{
          'providerId': 'apple.com',
          'signInMethod': 'apple.com',
          'idToken': 'apple-id-token',
          'accessToken': null,
          'secret': null,
          'rawNonce': 'raw-nonce',
          'serverAuthCode': null,
          'familyName': 'כהן',
          'givenName': 'שרה',
          'middleName': null,
          'nickname': null,
          'namePrefix': null,
          'nameSuffix': null,
        });
      },
    );

    test('uses Firebase replacement credential after a failed link', () {
      final AuthCredential updated = createAppleFirebaseCredential(
        idToken: 'updated-token',
        rawNonce: 'updated-nonce',
      );
      final FirebaseAuthException error = FirebaseAuthException(
        code: 'credential-already-in-use',
        credential: updated,
      );

      expect(resolveAppleCredentialAfterLinkFailure(error), same(updated));
    });

    test(
      'never replays Apple credential when Firebase gives no replacement',
      () {
        final FirebaseAuthException error = FirebaseAuthException(
          code: 'credential-already-in-use',
        );

        expect(
          () => resolveAppleCredentialAfterLinkFailure(error),
          throwsA(
            isA<FirebaseAuthException>().having(
              (FirebaseAuthException value) => value.code,
              'code',
              'apple-updated-credential-missing',
            ),
          ),
        );
      },
    );
  });
}
