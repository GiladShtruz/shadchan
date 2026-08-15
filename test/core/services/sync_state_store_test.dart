import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/sync_state_store.dart';

/// The ledger is what decides which records a backup sends. Its failure mode
/// is silent — a record whose change it misses is simply never uploaded, and
/// nobody finds out until a restore — so the rules are pinned down here rather
/// than left to the shape of a sync run nobody can execute offline.
void main() {
  late Directory directory;
  late Box<dynamic> box;
  late SyncStateStore store;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('shadchan_sync_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await box.clear();
    store = SyncStateStore(box);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('A record with the same content keeps the same fingerprint', () {
    final Map<String, Object?> record = <String, Object?>{
      'id': 'p1',
      'firstName': 'שרה',
      'manualAge': 24,
    };

    expect(
      SyncStateStore.fingerprint(record),
      SyncStateStore.fingerprint(Map<String, Object?>.of(record)),
    );
  });

  test('Key order does not change the fingerprint', () {
    // A serializer that grows a field in the middle would otherwise mark every
    // record in the database as changed and trigger one pointless full upload.
    expect(
      SyncStateStore.fingerprint(<String, Object?>{
        'id': 'p1',
        'city': 'ירושלים',
        'manualAge': 24,
      }),
      SyncStateStore.fingerprint(<String, Object?>{
        'manualAge': 24,
        'id': 'p1',
        'city': 'ירושלים',
      }),
    );
  });

  test('Any edited field changes the fingerprint', () {
    final String before = SyncStateStore.fingerprint(<String, Object?>{
      'id': 'n1',
      'text': 'דיברתי עם האמא',
      'isAutomatic': false,
    });

    // A note carries no `updatedAt`, so an edit like this is invisible to any
    // timestamp-based scheme. That is exactly why the fingerprint is over the
    // content.
    expect(
      SyncStateStore.fingerprint(<String, Object?>{
        'id': 'n1',
        'text': 'דיברתי עם האמא שלה',
        'isAutomatic': false,
      }),
      isNot(before),
    );
    expect(
      SyncStateStore.fingerprint(<String, Object?>{
        'id': 'n1',
        'text': 'דיברתי עם האמא',
        'isAutomatic': true,
      }),
      isNot(before),
    );
  });

  test('A null field is not the same as a missing one', () {
    expect(
      SyncStateStore.fingerprint(<String, Object?>{'id': 'p1', 'city': null}),
      isNot(SyncStateStore.fingerprint(<String, Object?>{'id': 'p1'})),
    );
  });

  test('Committing records the fingerprints and the time', () async {
    expect(store.lastSyncedAt, isNull);
    expect(store.fingerprints, isEmpty);

    await store.commit(<String, String>{'people/p1': 'abc'});

    expect(store.fingerprints, <String, String>{'people/p1': 'abc'});
    expect(store.lastSyncedAt, isNotNull);
  });

  test('Switching accounts throws the ledger away', () async {
    expect(await store.fingerprintsFor('uid-a'), isEmpty);
    await store.commit(<String, String>{'people/p1': 'abc'});

    // The same account keeps its ledger, so the next sync sends only changes.
    expect(await store.fingerprintsFor('uid-a'), <String, String>{
      'people/p1': 'abc',
    });

    // A different account has a different Firestore tree. Trusting the old
    // ledger against it would leave the new account's backup missing every
    // record that happened to be unchanged.
    expect(await store.fingerprintsFor('uid-b'), isEmpty);
    expect(store.lastSyncedAt, isNull);
  });

  test('A corrupt ledger reads as empty rather than throwing', () async {
    await box.put('cloudSyncFingerprints', 'not a map at all');

    expect(store.fingerprints, isEmpty);
  });
}
