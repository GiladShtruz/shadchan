import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/account_service.dart';

void main() {
  group('account deletion reauthentication', () {
    test('Apple takes precedence so its token can be revoked', () {
      expect(
        AccountService.deletionAuthMethod(<String>[
          'google.com',
          'apple.com',
          'password',
        ], appleAvailable: true),
        AccountDeletionAuthMethod.apple,
      );
    });

    test('Google is used before password when both are linked', () {
      expect(
        AccountService.deletionAuthMethod(<String>[
          'password',
          'google.com',
        ], appleAvailable: false),
        AccountDeletionAuthMethod.google,
      );
    });

    test('password-only account requires password reauthentication', () {
      expect(
        AccountService.deletionAuthMethod(<String>[
          'password',
        ], appleAvailable: false),
        AccountDeletionAuthMethod.password,
      );
    });

    test('Apple account cannot be deleted where Apple flow is unavailable', () {
      expect(
        AccountService.deletionAuthMethod(<String>[
          'apple.com',
        ], appleAvailable: false),
        AccountDeletionAuthMethod.unsupported,
      );
    });
  });
}
