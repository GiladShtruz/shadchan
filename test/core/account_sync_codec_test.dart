import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/account_sync_codec.dart';

void main() {
  group('fingerprint', () {
    test('ignores key order at every depth, and sync metadata', () {
      final String a = AccountSyncCodec.fingerprint(<String, Object?>{
        'id': 'p1',
        'contacts': <Object?>[
          <String, Object?>{'name': 'א', 'phone': '1'},
        ],
      });
      final String b = AccountSyncCodec.fingerprint(<String, Object?>{
        '_w': 123,
        '_d': 'device',
        'contacts': <Object?>[
          <String, Object?>{'phone': '1', 'name': 'א'},
        ],
        'id': 'p1',
      });
      expect(a, b);
    });

    test('a whole number is the same as an int or a double', () {
      expect(
        AccountSyncCodec.fingerprint(<String, Object?>{'h': 170}),
        AccountSyncCodec.fingerprint(<String, Object?>{'h': 170.0}),
      );
    });
  });

  group('decide', () {
    const SyncBase base = SyncBase(local: 'a', remote: 'a');

    test('only the remote moved: take it', () {
      expect(
        AccountSyncCodec.decide(local: 'a', remote: 'b', base: base),
        SyncDecision.takeRemote,
      );
    });

    test('only the local moved: send it', () {
      expect(
        AccountSyncCodec.decide(local: 'b', remote: 'a', base: base),
        SyncDecision.pushLocal,
      );
    });

    test('a new record on either side is an insert, not a conflict', () {
      expect(
        AccountSyncCodec.decide(local: 'x', remote: null, base: null),
        SyncDecision.pushLocal,
      );
      expect(
        AccountSyncCodec.decide(local: null, remote: 'x', base: null),
        SyncDecision.takeRemote,
      );
    });

    test('a deletion on an untouched side is passed on', () {
      expect(
        AccountSyncCodec.decide(local: null, remote: 'a', base: base),
        SyncDecision.pushLocal,
      );
      expect(
        AccountSyncCodec.decide(local: 'a', remote: null, base: base),
        SyncDecision.takeRemote,
      );
    });

    test('an edit beats a deletion, whichever side made it', () {
      expect(
        AccountSyncCodec.decide(local: 'b', remote: null, base: base),
        SyncDecision.pushLocal,
      );
      expect(
        AccountSyncCodec.decide(local: null, remote: 'b', base: base),
        SyncDecision.takeRemote,
      );
    });

    test('two edits: the later wins', () {
      expect(
        AccountSyncCodec.decide(
          local: 'b',
          remote: 'c',
          base: base,
          localChangedAt: 2000,
          remoteWrittenAt: 1000,
        ),
        SyncDecision.pushLocal,
      );
      expect(
        AccountSyncCodec.decide(
          local: 'b',
          remote: 'c',
          base: base,
          localChangedAt: 1000,
          remoteWrittenAt: 2000,
        ),
        SyncDecision.takeRemote,
      );
    });

    test('a copy that never round-trips exactly is not a change', () {
      expect(
        AccountSyncCodec.decide(
          local: 'l',
          remote: 'r',
          base: const SyncBase(local: 'l', remote: 'r'),
        ),
        SyncDecision.inSync,
      );
    });
  });

  group('settings', () {
    test('device-only settings never travel', () {
      for (final String key in <String>[
        'signIn.hasAccount',
        'cloudSyncFingerprints',
        'accountSync.anything',
        'faceAlign./a/b.jpg',
        'migratedBirthDatesToAges',
        'invite.from',
        'contactHashes.print',
      ]) {
        expect(AccountSyncCodec.isSyncedSetting(key), isFalse, reason: key);
      }
      for (final String key in <String>[
        'userName',
        'home.board',
        'tags.library',
        'personReminder.p1',
        'notifications.reminderLog',
        'themeMode',
      ]) {
        expect(AccountSyncCodec.isSyncedSetting(key), isTrue, reason: key);
      }
    });

    test(
      'photo paths travel as names and come back as this phone\'s paths',
      () {
        final Map<String, Object?> remote = AccountSyncCodec.settingToRemote(
          AccountSyncCodec.profileCardPhotosKey,
          <String>['/data/a/photos/one.jpg', '/data/a/photos/two.jpg'],
        )!;
        expect(remote['v'], '["one.jpg","two.jpg"]');
        final ({String key, Object? value})? back =
            AccountSyncCodec.settingFromRemote(remote, '/var/b/photos');
        expect(back!.value, <String>[
          '/var/b/photos/one.jpg',
          '/var/b/photos/two.jpg',
        ]);
      },
    );

    test('a value keeps its type', () {
      final ({String key, Object? value})? back =
          AccountSyncCodec.settingFromRemote(
            AccountSyncCodec.settingToRemote('userIsSingle', true)!,
            '/p',
          );
      expect(back!.value, isTrue);
    });
  });
}
