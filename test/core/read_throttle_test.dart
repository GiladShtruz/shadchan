import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/read_throttle.dart';

/// The clocks that keep the app from asking the server the same thing over
/// and over (2026-11-22, see `docs/firebase-costs-2026-11-22.md`).
void main() {
  final DateTime t0 = DateTime(2026, 11, 22, 10);

  group('ReadThrottle.isDue', () {
    test('never done, or done long enough ago, is due', () {
      expect(
        ReadThrottle.isDue(
          last: null,
          every: const Duration(hours: 1),
          now: t0,
        ),
        isTrue,
      );
      expect(
        ReadThrottle.isDue(
          last: t0.subtract(const Duration(hours: 1)),
          every: const Duration(hours: 1),
          now: t0,
        ),
        isTrue,
      );
    });

    test('done a moment ago is not due', () {
      expect(
        ReadThrottle.isDue(
          last: t0.subtract(const Duration(minutes: 59)),
          every: const Duration(hours: 1),
          now: t0,
        ),
        isFalse,
      );
    });

    test('a clock in the future (the phone time changed) never blocks', () {
      expect(
        ReadThrottle.isDue(
          last: t0.add(const Duration(days: 3)),
          every: const Duration(hours: 1),
          now: t0,
        ),
        isTrue,
      );
    });
  });

  group('publishing "last active"', () {
    test('at most once an hour while nothing changed', () {
      expect(
        PersonalCardService.activityWorthWriting(
          last: t0.subtract(const Duration(minutes: 30)),
          lastCount: '40',
          count: 40,
          now: t0,
        ),
        isFalse,
      );
      expect(
        PersonalCardService.activityWorthWriting(
          last: t0.subtract(const Duration(hours: 1)),
          lastCount: '40',
          count: 40,
          now: t0,
        ),
        isTrue,
      );
    });

    test('a new database size goes out after ten minutes, not at once', () {
      expect(
        PersonalCardService.activityWorthWriting(
          last: t0.subtract(const Duration(minutes: 5)),
          lastCount: '40',
          count: 41,
          now: t0,
        ),
        isFalse,
      );
      expect(
        PersonalCardService.activityWorthWriting(
          last: t0.subtract(const Duration(minutes: 10)),
          lastCount: '40',
          count: 41,
          now: t0,
        ),
        isTrue,
      );
    });

    test('the first one on this phone always goes out', () {
      expect(
        PersonalCardService.activityWorthWriting(
          last: null,
          lastCount: null,
          count: 3,
          now: t0,
        ),
        isTrue,
      );
    });
  });

  test(
    'the clocks and the shared-card record never travel with the account',
    () {
      expect(
        AccountSyncCodec.isSyncedSetting('serverReads.activity.at'),
        isFalse,
      );
      expect(AccountSyncCodec.isSyncedSetting('serverReads.tips.at'), isFalse);
      expect(AccountSyncCodec.isSyncedSetting('network.held.uid1'), isFalse);
      // An ordinary setting still does.
      expect(AccountSyncCodec.isSyncedSetting('home.boardSeen'), isTrue);
    },
  );
}
