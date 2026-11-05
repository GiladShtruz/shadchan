import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/hive_adapters.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_engine.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/account_sync_remote.dart';
import 'package:shadchan/utils/enums.dart';

/// One account, in memory: what Firestore and Storage would hold under
/// `users/{uid}`, with listeners that hear every write as the server would
/// confirm it.
class FakeAccount implements AccountSyncRemote {
  final Map<SyncCollection, Map<String, RemoteDocument>> docs =
      <SyncCollection, Map<String, RemoteDocument>>{};
  final Map<String, List<int>> files = <String, List<int>>{};
  final List<(SyncCollection, StreamController<List<RemoteChange>>)> _watchers =
      <(SyncCollection, StreamController<List<RemoteChange>>)>[];
  int _clock = 1000000;
  bool offline = false;
  Map<String, Object?>? legacyProfile;
  int writes = 0;

  Map<String, RemoteDocument> of(SyncCollection collection) =>
      docs.putIfAbsent(collection, () => <String, RemoteDocument>{});

  @override
  Future<Map<String, RemoteDocument>> fetchAll(
    SyncCollection collection,
  ) async {
    if (offline) {
      throw const SocketException('offline');
    }
    return Map<String, RemoteDocument>.of(of(collection));
  }

  @override
  Stream<List<RemoteChange>> watch(
    SyncCollection collection,
    int? afterMicros,
  ) {
    final StreamController<List<RemoteChange>> controller =
        StreamController<List<RemoteChange>>();
    _watchers.add((collection, controller));
    final List<RemoteChange> initial = <RemoteChange>[
      for (final MapEntry<String, RemoteDocument> e in of(collection).entries)
        if (afterMicros == null || (e.value.writtenAtMicros ?? 0) > afterMicros)
          RemoteChange(id: e.key, document: e.value),
    ];
    scheduleMicrotask(() {
      if (initial.isNotEmpty) {
        controller.add(initial);
      }
    });
    controller.onCancel = () {
      _watchers.removeWhere((entry) => entry.$2 == controller);
    };
    return controller.stream;
  }

  @override
  void write(
    List<RemoteWrite> writes, {
    required String deviceId,
    required void Function(List<String> paths, Object error) onFailed,
  }) {
    this.writes += writes.length;
    for (final RemoteWrite write in writes) {
      final RemoteDocument document = RemoteDocument(
        data: write.data == null
            ? null
            : <String, Object?>{...write.data!, '_d': deviceId},
        writtenAtMicros: ++_clock,
      );
      of(write.collection)[write.id] = document;
      for (final entry in List.of(_watchers)) {
        if (entry.$1 == write.collection) {
          entry.$2.add(<RemoteChange>[
            RemoteChange(id: write.id, document: document),
          ]);
        }
      }
    }
  }

  @override
  Future<Map<String, Object?>?> fetchLegacyProfile() async => legacyProfile;

  @override
  Future<int?> fileSize(String key) async => files[key]?.length;

  @override
  Future<void> upload(String key, File file, String contentType) async {
    files[key] = file.readAsBytesSync();
  }

  @override
  Future<bool> download(String key, File target) async {
    final List<int>? bytes = files[key];
    if (bytes == null) {
      return false;
    }
    target.writeAsBytesSync(bytes);
    return true;
  }

  @override
  Future<void> deleteFile(String key) async {
    files.remove(key);
  }

  final List<SyncConflict> conflicts = <SyncConflict>[];

  @override
  Future<void> waitForWrites() async {
    if (offline) {
      throw const SocketException('offline');
    }
  }

  @override
  Future<int?> countLive(SyncCollection collection) async =>
      of(collection).values.where((RemoteDocument d) => d.data != null).length;

  @override
  void saveConflict(SyncConflict conflict) => conflicts.add(conflict);
}

/// One phone: its own boxes, ledger and folders.
class Device {
  Device._(this.name, this.boxes, this.ledger, this.photos, this.voice);

  final String name;
  final Map<SyncCollection, Box<dynamic>> boxes;
  final AccountSyncLedger ledger;
  final Directory photos;
  final Directory voice;
  AccountSyncEngine? engine;
  int now = DateTime(2026, 10, 6).millisecondsSinceEpoch;
  final List<AccountSyncChanges> announced = <AccountSyncChanges>[];

  static int _count = 0;

  static Future<Device> open(String name, Directory root) async {
    final String tag = '${name}_${_count++}';
    final Map<SyncCollection, Box<dynamic>> boxes =
        <SyncCollection, Box<dynamic>>{};
    for (final SyncCollection collection in SyncCollection.values) {
      boxes[collection] = await Hive.openBox<dynamic>('${collection.box}_$tag');
    }
    final Box<dynamic> ledgerBox = await Hive.openBox<dynamic>('ledger_$tag');
    final Directory photos = Directory('${root.path}/$tag/photos')
      ..createSync(recursive: true);
    final Directory voice = Directory('${root.path}/$tag/voice')
      ..createSync(recursive: true);
    return Device._(name, boxes, AccountSyncLedger(ledgerBox), photos, voice);
  }

  Box<dynamic> get people => boxes[SyncCollection.people]!;
  Box<dynamic> get settings => boxes[SyncCollection.settings]!;

  Future<void> connect(FakeAccount account) async {
    await ledger.bindTo('uid-1');
    engine = AccountSyncEngine(
      ledger: ledger,
      remote: account,
      boxes: boxes,
      photosDirectory: photos.path,
      voiceDirectory: voice.path,
      flushDelay: const Duration(milliseconds: 10),
      nowMillis: () => now,
      onRemoteApplied: announced.add,
    );
    await engine!.start();
    await settle();
  }

  Future<void> settle() async {
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await engine?.flush();
    }
  }
}

Person person(
  String id,
  String first, {
  String? city,
  String? phone,
  List<String>? photos,
}) {
  final DateTime at = DateTime(2026, 1, 1);
  return Person(
    id: id,
    firstName: first,
    lastName: 'כהן',
    gender: Gender.male,
    city: city,
    phone: phone,
    photosPaths: photos ?? <String>[],
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('account_sync_test_');
    Hive.init(root.path);
    registerHiveAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('a friend added on one phone appears on the other', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    await a.connect(account);
    await b.connect(account);

    await a.people.put('p1', person('p1', 'דוד'));
    await a.settle();
    await b.settle();

    expect((b.people.get('p1') as Person).firstName, 'דוד');
    expect(
      b.announced.any((c) => c.collections.contains(SyncCollection.people)),
      isTrue,
    );

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test('a second phone signing in reads the whole database', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.people.put('p2', person('p2', 'שרה'));
    await a.settings.put('home.board', '[1]');
    await a.connect(account);

    final Device b = await Device.open('b', root);
    await b.connect(account);
    expect(b.people.length, 2);
    expect(b.settings.get('home.board'), '[1]');
    expect(b.ledger.initialPullDone, isTrue);

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test('edits and deletions travel both ways while both are open', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.connect(account);
    await b.connect(account);

    await b.people.put('p1', person('p1', 'דוד', city: 'ירושלים'));
    await b.settle();
    await a.settle();
    expect((a.people.get('p1') as Person).city, 'ירושלים');

    await a.people.delete('p1');
    await a.settle();
    await b.settle();
    expect(b.people.containsKey('p1'), isFalse);
    // A tombstone, not a hole: a third phone that still had the record would
    // learn it is gone rather than sending it back.
    expect(account.of(SyncCollection.people)['p1']!.data, isNull);

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test(
    'a deleted record does not come back from a phone that was away',
    () async {
      final FakeAccount account = FakeAccount();
      final Device a = await Device.open('a', root);
      final Device b = await Device.open('b', root);
      await a.people.put('p1', person('p1', 'דוד'));
      await a.connect(account);
      await b.connect(account);
      await b.engine!.stop();

      await a.people.delete('p1');
      await a.settle();

      // B comes back with the record untouched since it last agreed.
      final AccountSyncEngine again = AccountSyncEngine(
        ledger: b.ledger,
        remote: account,
        boxes: b.boxes,
        photosDirectory: b.photos.path,
        voiceDirectory: b.voice.path,
        flushDelay: const Duration(milliseconds: 10),
      );
      b.engine = again;
      await again.start();
      await b.settle();
      expect(b.people.containsKey('p1'), isFalse);
      expect(account.of(SyncCollection.people)['p1']!.data, isNull);

      await a.engine!.stop();
      await again.stop();
    },
  );

  test('an edit beats a deletion made on the other phone', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.connect(account);
    await b.connect(account);
    await b.engine!.stop();

    // B edits while away; A deletes.
    await b.people.put('p1', person('p1', 'דוד', city: 'חיפה'));
    await a.people.delete('p1');
    await a.settle();

    final AccountSyncEngine again = AccountSyncEngine(
      ledger: b.ledger,
      remote: account,
      boxes: b.boxes,
      photosDirectory: b.photos.path,
      voiceDirectory: b.voice.path,
      flushDelay: const Duration(milliseconds: 10),
    );
    b.engine = again;
    await again.start();
    await b.settle();
    await a.settle();

    expect((b.people.get('p1') as Person).city, 'חיפה');
    expect((a.people.get('p1') as Person).city, 'חיפה');

    await a.engine!.stop();
    await again.stop();
  });

  test('moving into the account keeps both phones\' records', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    await a.people.put('pa', person('pa', 'אברהם'));
    await b.people.put('pb', person('pb', 'בנימין'));

    await a.connect(account);
    await b.connect(account);
    await a.settle();

    expect(a.people.keys.toSet(), <String>{'pa', 'pb'});
    expect(b.people.keys.toSet(), <String>{'pa', 'pb'});

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test('device-only settings stay on the device', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    await a.settings.put('signIn.hasAccount', 'true');
    await a.settings.put('faceAlign./x/y.jpg', '0.5');
    await a.settings.put('tags.library', '["חברים מהישיבה"]');
    await a.connect(account);

    final Iterable<Object?> keys = account
        .of(SyncCollection.settings)
        .values
        .map((RemoteDocument d) => d.data?['k']);
    expect(keys, contains('tags.library'));
    expect(keys, isNot(contains('signIn.hasAccount')));
    expect(keys, isNot(contains('faceAlign./x/y.jpg')));

    await a.engine!.stop();
  });

  test(
    'stopping before clearing the phone deletes nothing in the account',
    () async {
      final FakeAccount account = FakeAccount();
      final Device a = await Device.open('a', root);
      await a.people.put('p1', person('p1', 'דוד'));
      await a.connect(account);

      await a.engine!.stop();
      await a.people.clear();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(account.of(SyncCollection.people)['p1']!.data, isNotNull);
    },
  );

  test('nothing is sent before the account has been read', () async {
    final FakeAccount account = FakeAccount()..offline = true;
    final Device a = await Device.open('a', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.connect(account);

    expect(a.engine!.isPulled, isFalse);
    expect(account.writes, 0);

    account.offline = false;
    await a.engine!.resume();
    await a.settle();
    expect(a.engine!.isPulled, isTrue);
    expect(account.of(SyncCollection.people)['p1']!.data, isNotNull);

    await a.engine!.stop();
  });

  test('photos go up as files and come down on the other phone', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    final File photo = File('${a.photos.path}/face.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    await a.people.put('p1', person('p1', 'דוד', photos: <String>[photo.path]));
    await a.connect(account);
    await a.engine!.syncFiles();
    expect(account.files['photos/face.jpg'], <int>[1, 2, 3]);
    // The record carries the name, never this phone's path.
    expect(account.of(SyncCollection.people)['p1']!.data!['photos'], <String>[
      'face.jpg',
    ]);

    await b.connect(account);
    await b.engine!.syncFiles();
    final Person there = b.people.get('p1') as Person;
    expect(there.photosPaths.single, '${b.photos.path}/face.jpg');
    expect(File(there.photosPaths.single).readAsBytesSync(), <int>[1, 2, 3]);

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test('the older version\'s profile fills an account with none', () async {
    final FakeAccount account = FakeAccount()
      ..legacyProfile = <String, Object?>{'name': 'רחל'};
    final Device a = await Device.open('a', root);
    Map<String, Object?>? handed;
    await a.ledger.bindTo('uid-1');
    final AccountSyncEngine engine = AccountSyncEngine(
      ledger: a.ledger,
      remote: account,
      boxes: a.boxes,
      photosDirectory: a.photos.path,
      voiceDirectory: a.voice.path,
      onLegacyProfile: (Map<String, Object?> profile) async => handed = profile,
    );
    await engine.start();
    expect(handed?['name'], 'רחל');
    await engine.stop();
  });

  test('of two edits made apart, the later one wins on both phones', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.connect(account);
    await b.connect(account);
    await b.engine!.stop();

    // B edits first, offline; A edits later and sends it.
    b.now = DateTime(2026, 10, 6, 10).millisecondsSinceEpoch;
    await b.people.put('p1', person('p1', 'דוד', city: 'בני ברק'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await a.people.put('p1', person('p1', 'דוד', city: 'צפת'));
    await a.settle();

    final AccountSyncEngine again = AccountSyncEngine(
      ledger: b.ledger,
      remote: account,
      boxes: b.boxes,
      photosDirectory: b.photos.path,
      voiceDirectory: b.voice.path,
      flushDelay: const Duration(milliseconds: 10),
      // B's clock is behind the server's stamp on A's write.
      nowMillis: () => 0,
    );
    b.engine = again;
    await again.start();
    await b.settle();
    await a.settle();

    expect((b.people.get('p1') as Person).city, 'צפת');
    expect((a.people.get('p1') as Person).city, 'צפת');

    await a.engine!.stop();
    await again.stop();
  });

  test(
    'an idea travels with who was asked and how long the couple dated',
    () async {
      final FakeAccount account = FakeAccount();
      final Device a = await Device.open('a', root);
      final Device b = await Device.open('b', root);
      final DateTime at = DateTime(2026, 9, 1);
      await a.boxes[SyncCollection.matches]!.put(
        'm1',
        MatchIdea(
            id: 'm1',
            personAId: 'p1',
            personBId: 'p2',
            status: MatchStatus.dating,
            currentHandler: CurrentHandler.me,
            createdAt: at,
            updatedAt: at,
          )
          ..askedMaleAt = at
          ..checkInEveryDays = 14
          ..datingStartedAt = at,
      );
      await a.connect(account);
      await b.connect(account);

      final MatchIdea there =
          b.boxes[SyncCollection.matches]!.get('m1') as MatchIdea;
      expect(there.status, MatchStatus.dating);
      expect(there.askedMaleAt, at);
      expect(there.checkInEveryDays, 14);
      expect(there.datingStartedAt, at);

      await a.engine!.stop();
      await b.engine!.stop();
    },
  );

  test('a voice note reaches the other phone with its recording', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    File('${a.voice.path}/rec_1.m4a').writeAsBytesSync(<int>[9, 9]);
    await a.boxes[SyncCollection.personNotes]!.put(
      'n1',
      PersonNote(
        id: 'n1',
        personId: 'p1',
        text: 'הקלטה',
        createdAt: DateTime(2026, 10, 1),
        isAutomatic: false,
        audioFile: 'rec_1.m4a',
        audioDurationMs: 3000,
      ),
    );
    await a.connect(account);
    await a.engine!.syncFiles();
    expect(account.files['voice/rec_1.m4a'], <int>[9, 9]);

    await b.connect(account);
    await b.engine!.syncFiles();
    expect(File('${b.voice.path}/rec_1.m4a').readAsBytesSync(), <int>[9, 9]);

    // Deleting the note on A takes the recording out of the account too.
    await a.boxes[SyncCollection.personNotes]!.delete('n1');
    await a.settle();
    await a.engine!.syncFiles();
    expect(account.files.containsKey('voice/rec_1.m4a'), isFalse);

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test(
    'the same friend added on a phone without the account is joined by phone',
    () async {
      final FakeAccount account = FakeAccount();
      final Device a = await Device.open('a', root);
      await a.people.put(
        'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
        person(
          'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
          'דוד',
          phone: '+972-50-123-4567',
        ),
      );
      await a.connect(account);

      // A phone that was used without an account knows the same friend under
      // another id, with a city the account lacks and a note about him.
      const String localId = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
      final Device b = await Device.open('b', root);
      await b.people.put(
        localId,
        person(localId, 'דוד', city: 'צפת', phone: '050 123 4567'),
      );
      await b.boxes[SyncCollection.personNotes]!.put(
        'n1',
        PersonNote(
          id: 'n1',
          personId: localId,
          text: 'אוהב טיולים',
          createdAt: DateTime(2026, 10, 1),
          isAutomatic: false,
        ),
      );
      await b.settings.put('personReminder.$localId', '2026-12-01');
      await b.connect(account);
      await a.settle();

      expect(b.people.length, 1);
      final Person joined =
          b.people.get('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa') as Person;
      expect(joined.city, 'צפת');
      final PersonNote note =
          b.boxes[SyncCollection.personNotes]!.get('n1') as PersonNote;
      expect(note.personId, 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
      expect(
        b.settings.get('personReminder.aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'),
        '2026-12-01',
      );
      expect(b.settings.containsKey('personReminder.$localId'), isFalse);
      // The account never hears of the second id, and has one person.
      expect(
        account
            .of(SyncCollection.people)
            .values
            .where((RemoteDocument d) => d.data != null)
            .length,
        1,
      );
      expect(
        (a.people.get('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa') as Person).city,
        'צפת',
      );
      expect(account.conflicts, isEmpty);
      expect(b.ledger.stats['duplicatesMerged'], 1);

      await a.engine!.stop();
      await b.engine!.stop();
    },
  );

  test('a shared phone with a different gender is not joined', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    await a.people.put('r1', person('r1', 'דוד', phone: '0501234567'));
    await a.connect(account);

    final Device b = await Device.open('b', root);
    await b.people.put(
      'l1',
      person('l1', 'שרה', phone: '0501234567')..gender = Gender.female,
    );
    await b.connect(account);
    expect(b.people.length, 2);

    await a.engine!.stop();
    await b.engine!.stop();
  });

  test('the losing edit of a conflict is kept in the account', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    final Device b = await Device.open('b', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.connect(account);
    await b.connect(account);
    await b.engine!.stop();

    await b.people.put('p1', person('p1', 'דוד', city: 'בני ברק'));
    await a.people.put('p1', person('p1', 'דוד', city: 'צפת'));
    await a.settle();

    final AccountSyncEngine again = AccountSyncEngine(
      ledger: b.ledger,
      remote: account,
      boxes: b.boxes,
      photosDirectory: b.photos.path,
      voiceDirectory: b.voice.path,
      flushDelay: const Duration(milliseconds: 10),
      nowMillis: () => 0,
    );
    b.engine = again;
    await again.start();
    await b.settle();

    expect((b.people.get('p1') as Person).city, 'צפת');
    expect(account.conflicts, hasLength(1));
    expect(account.conflicts.single.lostSide, 'local');
    expect(account.conflicts.single.lost['city'], 'בני ברק');
    expect(account.conflicts.single.kept['city'], 'צפת');

    await a.engine!.stop();
    await again.stop();
  });

  test('verification counts every collection and every file', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    File('${a.photos.path}/face.jpg').writeAsBytesSync(<int>[1, 2, 3]);
    await a.people.put(
      'p1',
      person('p1', 'דוד', photos: <String>['${a.photos.path}/face.jpg']),
    );
    await a.people.put('p2', person('p2', 'יוסף'));
    await a.connect(account);

    final SyncVerification? result = await a.engine!.verify();
    expect(result, isNotNull);
    expect(result!.ok, isTrue);
    expect(result.local[SyncCollection.people], 2);
    expect(result.account[SyncCollection.people], 2);
    expect(result.filesPending, 0);
    expect(a.ledger.migrationVerified, isTrue);
    expect(a.ledger.log.any((String l) => l.contains('verify ok')), isTrue);

    // Offline: not verified, not failed — postponed.
    account.offline = true;
    expect(await a.engine!.verify(), isNull);

    await a.engine!.stop();
  });

  test('a missing account record fails verification', () async {
    final FakeAccount account = FakeAccount();
    final Device a = await Device.open('a', root);
    await a.people.put('p1', person('p1', 'דוד'));
    await a.connect(account);
    // The server lost it (or refused it) without telling this device.
    account.of(SyncCollection.people).remove('p1');

    final SyncVerification? result = await a.engine!.verify();
    expect(result!.ok, isFalse);
    expect(a.ledger.migrationVerified, isFalse);

    await a.engine!.stop();
  });

  test('ids are rewritten inside keys, values and nested maps', () {
    const String from = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
    const String to = 'cccccccc-3333-4333-8333-cccccccccccc';
    expect(
      AccountSyncEngine.rewriteId(
        <String, Object?>{
          'person:$from': <Object?>[from, 'x'],
          'k': 'reminder.$from',
        },
        from,
        to,
      ),
      <String, Object?>{
        'person:$to': <Object?>[to, 'x'],
        'k': 'reminder.$to',
      },
    );
    // A short id only where it is the whole value.
    expect(AccountSyncEngine.rewriteId('p12', 'p1', 'q'), 'p12');
    expect(AccountSyncEngine.rewriteId('p1', 'p1', 'q'), 'q');
    expect(AccountSyncEngine.phoneKey('+972 50-123-4567'), '0501234567');
    expect(AccountSyncEngine.phoneKey('123'), isNull);
  });
}
