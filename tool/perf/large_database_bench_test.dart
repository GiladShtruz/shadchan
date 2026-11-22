// A benchmark, not a test: a synthetic large database (2,500 friends, 600
// ideas, 250 personal cards, 15,000 history lines by default) and the time
// one home redraw takes over it. Kept out of `test/` so the suite stays fast.
//
//   flutter test tool/perf/large_database_bench_test.dart
//   flutter test --enable-vmservice tool/perf/large_database_bench_test.dart \
//     --plain-name "home rebuild"        # adds a CPU profile of the redraws
//   flutter test tool/perf/... --dart-define=PEOPLE=5000 --dart-define=CARDS=500
//
// Timings are JIT on the machine that runs it — compare before/after on one
// machine, never with a phone. See docs/performance-2026-11-22.md.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:isolate';
import 'dart:developer' as developer;
import 'dart:math';

// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service.dart' as vm;
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart' as vmio;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/self_identity.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/utils/enums.dart';

const int kPeople = int.fromEnvironment('PEOPLE', defaultValue: 2500);
const int kMatches = int.fromEnvironment('MATCHES', defaultValue: 600);
const int kCards = int.fromEnvironment('CARDS', defaultValue: 250);
const int kEvents = int.fromEnvironment('EVENTS', defaultValue: 15000);

void main() {
  late Directory dir;
  late PersonRepository people;
  late MatchRepository matches;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('bench_');
    Hive.init(dir.path);
    Hive.registerAdapter(PersonAdapter());
    Hive.registerAdapter(RegionAdapter());
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(MatchStatusAdapter());
    Hive.registerAdapter(CurrentHandlerAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    Hive.registerAdapter(MaritalStatusAdapter());
    Hive.registerAdapter(PersonEventAdapter());
    Hive.registerAdapter(PersonEventTypeAdapter());
    Hive.registerAdapter(MatchStatusEventAdapter());
    final Box<Person> pBox = await Hive.openBox<Person>('people');
    final Box<MatchIdea> mBox = await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
    final Box<PersonEvent> eBox = await Hive.openBox<PersonEvent>(
      'person_events',
    );
    final Box<MatchStatusEvent> sBox = await Hive.openBox<MatchStatusEvent>(
      'match_status_events',
    );
    final Box<dynamic> settings = await Hive.openBox<dynamic>('settings');
    await (await Hive.openBox<dynamic>(AccountSyncLedger.boxName)).putAll(
      <String, Object?>{
        'meta.initialPullDone': true,
        'meta.version': AccountSyncLedger.version,
      },
    );
    await settings.putAll(<String, Object?>{
      'userName': 'בודק',
      'userGender': 'male',
      'userIsSingle': false,
      'signIn.hasAccount': 'true',
      'signIn.promptAnswered': 'true',
      'community.inWhatsAppGroup': 'true',
      'firstVisit.addFriends': 'true',
      'firstVisit.friendProfile': 'true',
    });
    final Random r = Random(7);
    const List<String> names = <String>[
      'אבי',
      'משה',
      'יוסי',
      'דוד',
      'שרה',
      'רחל',
      'לאה',
      'נועה',
      'תמר',
      'אורי',
    ];
    final DateTime now = DateTime.now();
    final Map<String, Person> ps = <String, Person>{};
    for (int i = 0; i < kPeople; i++) {
      final bool male = i.isEven;
      ps['p$i'] = Person(
        id: 'p$i',
        firstName: '${names[r.nextInt(names.length)]}$i',
        lastName: 'כהן',
        gender: male ? Gender.male : Gender.female,
        createdAt: now.subtract(Duration(days: r.nextInt(700))),
        updatedAt: now.subtract(Duration(days: r.nextInt(300))),
        manualAge: 20 + r.nextInt(15),
        manualAgeUpdatedAt: now,
        religiousLevel: ReligiousLevel.values[r.nextInt(4)],
        phone: '05${(10000000 + i).toString()}',
        description: 'כרטיס ארוך ' * 30,
        cardOwnerUid: i < kCards ? 'owner$i' : null,
      );
    }
    await pBox.putAll(ps);
    final Map<String, MatchIdea> ms = <String, MatchIdea>{};
    for (int i = 0; i < kMatches; i++) {
      ms['m$i'] = MatchIdea(
        id: 'm$i',
        personAId: 'p${(i * 2) % kPeople}',
        personBId: 'p${(i * 2 + 1) % kPeople}',
        status: MatchStatus.values[r.nextInt(MatchStatus.values.length)],
        currentHandler: CurrentHandler.me,
        createdAt: now.subtract(Duration(days: r.nextInt(400))),
        updatedAt: now.subtract(Duration(days: r.nextInt(100))),
      );
    }
    await mBox.putAll(ms);
    final Map<String, PersonEvent> es = <String, PersonEvent>{};
    for (int i = 0; i < kEvents; i++) {
      es['e$i'] = PersonEvent(
        id: 'e$i',
        personId: 'p${i % (kCards * 2)}',
        type: i.isEven
            ? PersonEventType.cardSynced
            : PersonEventType.statusChanged,
        text: 'עדכן את הכרטיס',
        createdAt: now.subtract(Duration(minutes: r.nextInt(200000))),
      );
    }
    await eBox.putAll(es);
    final Map<String, MatchStatusEvent> ss = <String, MatchStatusEvent>{};
    for (int i = 0; i < kMatches * 4; i++) {
      ss['s$i'] = MatchStatusEvent(
        id: 's$i',
        matchId: 'm${i % kMatches}',
        fromStatus: MatchStatus.idea,
        toStatus: MatchStatus.values[r.nextInt(MatchStatus.values.length)],
        createdAt: now.subtract(Duration(minutes: r.nextInt(200000))),
      );
    }
    await sBox.putAll(ss);
    SelfIdentity.update(phone: '0541234567', uid: 'me');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  int time(void Function() f, {int reps = 5}) {
    final Stopwatch sw = Stopwatch()..start();
    for (int i = 0; i < reps; i++) {
      f();
    }
    return sw.elapsedMicroseconds ~/ reps;
  }

  test('repository reads', () {
    final PersonRepository repo = PersonRepository(Hive.box<Person>('people'))
      ..requireVerifiedCardAccess()
      ..setVerifiedCardOwners(<String>{
        for (int i = 0; i < kCards; i++) 'owner$i',
      });
    print('count: ${time(() => repo.count)}us');
    print('databaseCount: ${time(() => repo.databaseCount)}us');
    print(
      'getAll (cold): ${time(() {
        repo.notifyListeners();
        repo.getAll();
      })}us',
    );
    print('getAll (warm): ${time(() => repo.getAll())}us');
    print('search: ${time(() => repo.search('אבי'))}us');
    final Stopwatch sw = Stopwatch()..start();
    final Set<String> grow = <String>{};
    for (int i = 0; i < kCards; i++) {
      grow.add('owner$i');
      repo.setVerifiedCardOwners(Set<String>.of(grow));
      repo.getAll();
      repo.count;
    }
    print('$kCards card arrivals one by one: ${sw.elapsedMilliseconds}ms');
  });

  test('network publish fingerprint (share all, 40 readers)', () {
    final List<Person> all = Hive.box<Person>('people').values.toList();
    final List<String> readers = <String>[for (int i = 0; i < 40; i++) 'r$i'];
    final Stopwatch sw = Stopwatch()..start();
    final String fp = SyncStateStore.fingerprint(<String, Object?>{
      'owner': 'x',
      for (final Person p in all)
        p.id: <Object?>[
          SharedCardCodec.values(p, ownerUid: 'me', ownerName: 'x'),
          readers,
          p.photosPaths,
        ],
    });
    print(
      'publish fingerprint over ${all.length}: ${sw.elapsedMilliseconds}ms (${fp.length})',
    );
  });

  testWidgets('home rebuild', (WidgetTester tester) async {
    people = PersonRepository(
      Hive.box<Person>('people'),
      null,
      Hive.box<PersonEvent>('person_events'),
    );
    matches = MatchRepository(
      Hive.box<MatchIdea>('matches'),
      Hive.box<MatchNote>('match_notes'),
      Hive.box<MatchStatusEvent>('match_status_events'),
    );
    AppRouter.router.go('/home');
    await tester.pumpWidget(_app(people, matches));
    final Stopwatch first = Stopwatch()..start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    print('first home frames: ${first.elapsedMilliseconds}ms');
    final List<int> samples = <int>[];
    for (int i = 0; i < 5; i++) {
      final Stopwatch sw = Stopwatch()..start();
      people.notifyListeners();
      await tester.pump();
      samples.add(sw.elapsedMilliseconds);
    }
    print('home rebuild after a people change: $samples ms');
    final List<int> m = <int>[];
    for (int i = 0; i < 5; i++) {
      final Stopwatch sw = Stopwatch()..start();
      matches.notifyListeners();
      await tester.pump();
      m.add(sw.elapsedMilliseconds);
    }
    print('home rebuild after an ideas change: $m ms');
    // Scrolling the home page with nothing changing underneath: every frame.
    final Finder scroll = find.byType(Scrollable).first;
    final List<int> frames = <int>[];
    for (int dir = 0; dir < 2; dir++) {
      for (int i = 0; i < 30; i++) {
        final Stopwatch sw = Stopwatch()..start();
        await tester.drag(scroll, Offset(0, dir == 0 ? -60 : 60));
        await tester.pump(const Duration(milliseconds: 16));
        frames.add(sw.elapsedMilliseconds);
      }
    }
    frames.sort();
    print(
      'scroll frames: median ${frames[frames.length ~/ 2]}ms, '
      'p90 ${frames[(frames.length * 9) ~/ 10]}ms, max ${frames.last}ms',
    );
    await tester.runAsync(() async {
      final developer.ServiceProtocolInfo info =
          await developer.Service.getInfo();
      if (info.serverUri == null) {
        print('no vm service');
        return;
      }
      final Uri ws = info.serverWebSocketUri!;
      final vm.VmService service = await vmio.vmServiceConnectUri(
        ws.toString(),
      );
      final String isolateId = developer.Service.getIsolateId(Isolate.current)!;
      await service.clearCpuSamples(isolateId);
      final int t0 = (await service.getVMTimelineMicros()).timestamp!;
      final int t1 = (await service.getVMTimelineMicros()).timestamp!;
      _profileT = (service, isolateId, t0, t1);
    });
    for (int i = 0; i < 10; i++) {
      people.notifyListeners();
      await tester.pump();
      matches.notifyListeners();
      await tester.pump();
    }
    await tester.runAsync(() async {
      if (_profileT == null) return;
      final (vm.VmService service, String isolateId, int t0, _) = _profileT!;
      final int t1 = (await service.getVMTimelineMicros()).timestamp!;
      final vm.CpuSamples samples = await service.getCpuSamples(
        isolateId,
        t0,
        t1 - t0,
      );
      final Map<String, int> incl = <String, int>{};
      final Map<String, int> excl = <String, int>{};
      final List<vm.ProfileFunction> fns = samples.functions!;
      String name(int i) {
        final dynamic f = fns[i].function;
        final String n = f is vm.FuncRef
            ? '${f.owner is vm.ClassRef ? (f.owner as vm.ClassRef).name : ''}.${f.name}'
            : '$f';
        final String url = fns[i].resolvedUrl ?? '';
        return '$n  ${url.replaceFirst('package:shadchan/', 'S:')}';
      }

      for (final vm.CpuSample s in samples.samples!) {
        final List<int> stack = s.stack!;
        if (stack.isEmpty) continue;
        excl.update(name(stack.first), (int v) => v + 1, ifAbsent: () => 1);
        for (final String n in stack.map(name).toSet()) {
          incl.update(n, (int v) => v + 1, ifAbsent: () => 1);
        }
      }
      final int total = samples.samples!.length;
      print('samples: $total');
      print(fns.take(5).map((f) => f.resolvedUrl).toList());
      List<MapEntry<String, int>> top(Map<String, int> m) =>
          (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .take(70)
              .toList();
      print('--- inclusive (shadchan only)');
      for (final MapEntry<String, int> e in top(<String, int>{
        for (final MapEntry<String, int> e in incl.entries)
          if (e.key.contains('S:') || e.key.contains('shadchan/'))
            e.key: e.value,
      })) {
        print('${(100 * e.value / total).toStringAsFixed(1)}%  ${e.key}');
      }
      print('--- exclusive');
      for (final MapEntry<String, int> e in top(excl).take(30)) {
        print('${(100 * e.value / total).toStringAsFixed(1)}%  ${e.key}');
      }
      await service.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}

(vm.VmService, String, int, int)? _profileT;

Widget _app(PersonRepository people, MatchRepository matches) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PersonRepository>.value(value: people),
      ChangeNotifierProvider<MatchRepository>.value(value: matches),
      ChangeNotifierProvider<ThemeModeProvider>(
        create: (_) => ThemeModeProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<UserProfileProvider>(
        create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<PersonalCardProvider>(
        create: (_) => PersonalCardProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<PersonalAreaProvider>(
        create: (_) => PersonalAreaProvider(enabled: false),
      ),
      ChangeNotifierProvider<CardAccessProvider>(
        create: (BuildContext context) => CardAccessProvider(
          people: context.read<PersonRepository>(),
          enabled: false,
        ),
      ),
      ChangeNotifierProvider<InboxProvider>(
        create: (_) => InboxProvider(enabled: false),
      ),
      ChangeNotifierProvider<AccountProvider>(
        create: (_) => AccountProvider(connect: () async {}),
      ),
      ChangeNotifierProvider<SyncProvider>(
        create: (_) =>
            SyncProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      ChangeNotifierProvider<TipsProvider>(
        create: (_) =>
            TipsProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      ChangeNotifierProvider<CommunityProvider>(
        create: (_) => CommunityProvider(connect: () async {}),
      ),
      ChangeNotifierProvider<SupportInboxProvider>(
        create: (_) =>
            SupportInboxProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
    ],
    child: const App(checkForUpdates: false),
  );
}
