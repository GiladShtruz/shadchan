import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/hive_adapters.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/account_health_service.dart';
import 'package:shadchan/services/account_switch.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/migration_snapshot.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/account_health_lookup.dart';

void main() {
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('account_isolation_');
    Hive.init(root.path);
    registerHiveAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('signing out removes every synced setting, so the next account cannot '
      'inherit one', () async {
    final Box<dynamic> settings = await Hive.openBox<dynamic>('settings');
    await settings.putAll(<String, Object?>{
      // The account's: a tag library, a board note, a reminder, a template.
      'tags.library': <String>['חסידי'],
      'home.boardNotes': '{"person:p1":"להתקשר"}',
      'personReminder.p1': '2026-12-01',
      'whatsappDetailsMessage': 'שלום',
      // The device's: the sign-in gate and an import cache stay.
      'signIn.promptAnswered': 'true',
      'contactHashes.print': 'abc',
      'migratedBirthDatesToAges': true,
    });

    await AccountSwitch.clearAccountCopy();

    for (final String key in settings.keys.whereType<String>()) {
      expect(
        AccountSyncCodec.isSyncedSetting(key),
        isFalse,
        reason: '$key belongs to the account and was left behind',
      );
    }
    expect(settings.get('signIn.promptAnswered'), 'true');
    expect(settings.get('contactHashes.print'), 'abc');
    await settings.close();
  });

  group('migration snapshot', () {
    late Directory folder;

    setUp(() {
      folder = Directory(
        '${root.path}/snapshots_${DateTime.now().microsecondsSinceEpoch}',
      );
      MigrationSnapshot.directoryProvider = () async => folder;
    });

    test('is taken in the backup format, and let go once verified', () async {
      final Box<dynamic> people = await Hive.openBox<dynamic>('snap_people');
      final Box<dynamic> settings = await Hive.openBox<dynamic>(
        'snap_settings',
      );
      final DateTime at = DateTime(2026, 1, 1);
      await people.put(
        'p1',
        Person(
          id: 'p1',
          firstName: 'דוד',
          lastName: 'כהן',
          gender: Gender.male,
          photosPaths: <String>[],
          createdAt: at,
          updatedAt: at,
        ),
      );
      await settings.put('tags.library', <String>['א']);
      await settings.put('signIn.promptAnswered', 'true');
      final Map<SyncCollection, Box<dynamic>> boxes =
          <SyncCollection, Box<dynamic>>{
            SyncCollection.people: people,
            SyncCollection.settings: settings,
          };

      expect(MigrationSnapshot.hasRecords(boxes), isTrue);
      final File? file = await MigrationSnapshot.take('uid-1', boxes);
      expect(file, isNotNull);
      final Map<String, dynamic> json =
          jsonDecode(file!.readAsStringSync()) as Map<String, dynamic>;
      expect(json['version'], 2);
      expect((json['people'] as List<dynamic>).single['firstName'], 'דוד');
      expect((json['settings'] as Map<String, dynamic>).keys, <String>[
        'tags.library',
      ]);
      expect(await MigrationSnapshot.list('uid-1'), hasLength(1));
      expect(await MigrationSnapshot.list('uid-2'), isEmpty);

      await MigrationSnapshot.release('uid-1');
      expect(await MigrationSnapshot.list('uid-1'), isEmpty);
      await people.close();
      await settings.close();
    });

    test('expires after its time', () async {
      folder.createSync(recursive: true);
      final int old = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      final int fresh = DateTime(2026, 11, 1).millisecondsSinceEpoch;
      File('${folder.path}/u_$old.json').writeAsStringSync('{}');
      File('${folder.path}/u_$fresh.json').writeAsStringSync('{}');
      await MigrationSnapshot.expire(now: DateTime(2026, 11, 5));
      final List<String> left = folder
          .listSync()
          .map((FileSystemEntity e) => e.uri.pathSegments.last)
          .toList();
      expect(left, <String>['u_$fresh.json']);
    });
  });

  test('the health report carries numbers and codes, never records', () async {
    final AccountSyncLedger ledger = AccountSyncLedger(
      await Hive.openBox<dynamic>('health_ledger'),
    );
    await ledger.addLog('verify ok people=3/3');
    await ledger.bumpStat('conflicts');
    await ledger.setMigration(<String, Object?>{
      'startedAt': '2026-11-01T00:00:00.000Z',
      'verifiedAt': '2026-11-01T00:01:00.000Z',
    });
    final Map<String, Object?> report = AccountHealthService.deviceReport(
      ledger: ledger,
      counts: <SyncCollection, int>{SyncCollection.people: 3},
      running: true,
      lastError: const FileSystemException('secret path /data/דוד.jpg'),
    );
    expect(report['counts'], <String, Object?>{'people': 3});
    expect(report['conflicts'], 1);
    expect(report['lastError'], 'FileSystemException');
    expect(
      (report['migration']! as Map<String, Object?>)['verifiedAt'],
      isNotNull,
    );
    expect(report['log'], hasLength(1));
    expect(jsonEncode(report).contains('דוד'), isFalse);
  });

  testWidgets('support finds an account and reads its devices', (
    WidgetTester tester,
  ) async {
    final List<String> asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AccountHealthLookup(
              find: (String query) async {
                asked.add(query);
                return AccountHealth.fromJson(<String, dynamic>{
                  'uid': 'uid-1',
                  'email': 'a@example.com',
                  'emailVerified': true,
                  'providers': <String>['password', 'google.com'],
                  'devices': <String, Object?>{
                    'd1': <String, Object?>{
                      'device': 'Pixel 8',
                      'initialPullDone': true,
                      'migration': <String, Object?>{
                        'verifiedAt': '2026-11-01T00:01:00.000Z',
                      },
                      'counts': <String, Object?>{'people': 120, 'matches': 8},
                      'writeFailures': 0,
                    },
                  },
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'A@example.com ');
    await tester.tap(find.text('חיפוש'));
    await tester.pumpAndSettle();

    expect(asked, <String>['A@example.com']);
    expect(find.text('uid-1'), findsOneWidget);
    expect(find.text('מייל וסיסמה, Google'), findsOneWidget);
    expect(find.text('120 / 8'), findsOneWidget);
    expect(find.textContaining('הושלמה ואומתה'), findsOneWidget);
  });
}
