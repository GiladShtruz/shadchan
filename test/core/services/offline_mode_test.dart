import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/hive_adapters.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/services/offline_cache.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/enums.dart';

/// Offline: the last synced copy is shown, and nothing is saved.
void main() {
  late Directory directory;
  late Box<Person> people;
  late PersonRepository personRepository;
  late MatchRepository matchRepository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('offline_mode_');
    Hive.init(directory.path);
    registerHiveAdapters();
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    ConnectivityStatus.debugSetOffline(false);
    OfflineGuard.debugReset();
    OfflineCache.debugForgetPending();
    people = await Hive.openBox<Person>('people');
    final Box<PersonNote> personNotes = await Hive.openBox<PersonNote>(
      'person_notes',
    );
    final Box<PersonEvent> personEvents = await Hive.openBox<PersonEvent>(
      'person_events',
    );
    final Box<MatchIdea> matches = await Hive.openBox<MatchIdea>('matches');
    final Box<MatchNote> notes = await Hive.openBox<MatchNote>('match_notes');
    final Box<MatchStatusEvent> statusEvents =
        await Hive.openBox<MatchStatusEvent>('match_status_events');
    for (final Box<dynamic> box in <Box<dynamic>>[
      people,
      personNotes,
      personEvents,
      matches,
      notes,
      statusEvents,
      Hive.box<dynamic>('settings'),
    ]) {
      await box.clear();
    }
    personRepository = PersonRepository(people, personNotes, personEvents);
    matchRepository = MatchRepository(matches, notes, statusEvents)
      ..resolvePerson = personRepository.getById;
  });

  tearDown(() => ConnectivityStatus.debugSetOffline(false));

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  group('the guard', () {
    test('online, writes go ahead', () {
      expect(OfflineGuard.blocking, isFalse);
      expect(OfflineGuard.ensureCanWrite, returnsNormally);
    });

    test('offline, a write is refused', () {
      ConnectivityStatus.debugSetOffline(true);
      expect(OfflineGuard.blocking, isTrue);
      expect(OfflineGuard.ensureCanWrite, throwsA(isA<OfflineWriteBlocked>()));
    });

    test('the app\'s own writes are never refused', () async {
      ConnectivityStatus.debugSetOffline(true);
      final bool blocked = await OfflineGuard.exempt(
        () async => OfflineGuard.blocking,
      );
      expect(blocked, isFalse);
    });

    test('the message is the one asked for, in both genders', () {
      expect(OfflineGuard.messageTemplate.contains('במצב לא מקוון'), isTrue);
      expect(OfflineGuard.messageTemplate.contains('עריכות לא יישמרו'), isTrue);
    });
  });

  group('the repositories', () {
    test('offline, adding a friend saves nothing', () async {
      ConnectivityStatus.debugSetOffline(true);
      await expectLater(
        personRepository.add(_person('p1')),
        throwsA(isA<OfflineWriteBlocked>()),
      );
      expect(people.isEmpty, isTrue);
    });

    test('offline, a note and a status change are refused', () async {
      await personRepository.add(_person('p1'));
      ConnectivityStatus.debugSetOffline(true);

      await expectLater(
        personRepository.addNote('p1', 'הערה'),
        throwsA(isA<OfflineWriteBlocked>()),
      );
      await expectLater(
        personRepository.updateProfileStatus('p1', ProfileStatus.busy),
        throwsA(isA<OfflineWriteBlocked>()),
      );
      expect(personRepository.getNotesForPerson('p1'), isEmpty);
      expect(
        personRepository.getById('p1')!.profileStatus,
        ProfileStatus.available,
      );
    });

    test('offline, an idea is not opened', () async {
      await personRepository.add(_person('m', gender: Gender.male));
      await personRepository.add(_person('f', gender: Gender.female));
      ConnectivityStatus.debugSetOffline(true);

      await expectLater(
        matchRepository.create('m', 'f'),
        throwsA(isA<OfflineWriteBlocked>()),
      );
      expect(matchRepository.getAll(), isEmpty);
    });

    test('everything already there is still readable offline', () async {
      await personRepository.add(_person('p1'));
      ConnectivityStatus.debugSetOffline(true);
      expect(personRepository.getById('p1'), isNotNull);
      expect(personRepository.search('דוד'), hasLength(1));
    });

    test('back online, the same write goes through', () async {
      ConnectivityStatus.debugSetOffline(true);
      await expectLater(
        personRepository.add(_person('p1')),
        throwsA(isA<OfflineWriteBlocked>()),
      );
      ConnectivityStatus.debugSetOffline(false);
      await personRepository.add(_person('p1'));
      expect(personRepository.getById('p1'), isNotNull);
    });
  });

  group('friends\' personal cards', () {
    Future<void> seedSyncedCard() async {
      final Person card = _person('card')..cardOwnerUid = 'owner-1';
      await people.put(card.id, card);
      // As in the app: synced cards wait for the server before they are drawn.
      personRepository.requireVerifiedCardAccess();
    }

    test('online, an unconfirmed card waits for the server', () async {
      await seedSyncedCard();
      OfflineCache.saveVerifiedCardOwners(<String>['owner-1']);
      expect(personRepository.getById('card'), isNull);
    });

    test(
      'offline, a card confirmed last time is shown as last synced',
      () async {
        await seedSyncedCard();
        OfflineCache.saveVerifiedCardOwners(<String>['owner-1']);
        ConnectivityStatus.debugSetOffline(true);
        expect(personRepository.getById('card'), isNotNull);
        expect(
          personRepository.getAll().map((Person p) => p.id),
          contains('card'),
        );
      },
    );

    test('offline, a card never confirmed stays hidden', () async {
      await seedSyncedCard();
      OfflineCache.saveVerifiedCardOwners(<String>['someone-else']);
      ConnectivityStatus.debugSetOffline(true);
      expect(personRepository.getById('card'), isNull);
    });

    test('the repository redraws when the connection changes', () async {
      await seedSyncedCard();
      int notified = 0;
      personRepository.addListener(() => notified++);
      ConnectivityStatus.debugSetOffline(true);
      expect(notified, 1);
    });
  });

  group('the community figures', () {
    test('a window\'s last answer is shown offline', () async {
      const CommunityTotals answer = CommunityTotals(
        points: 120,
        activeMatchmakers: 9,
        friends: 40,
        ideas: 12,
        couples: 3,
        engagements: 1,
        newMatchmakers: 2,
      );
      OfflineCache.write(
        'community.totals.week.'
        '${CommunityPeriods.keyFor(CommunityPeriod.week)}',
        answer.toJson(),
      );
      CommunityService.invalidate();
      ConnectivityStatus.debugSetOffline(true);

      final CommunityTotals shown = await CommunityService.totals(
        CommunityPeriod.week,
      );
      expect(shown.resolved, isTrue);
      expect(shown.points, 120);
      expect(shown.activeMatchmakers, 9);
      expect(shown.newMatchmakers, 2);
    });

    test('a window with nothing stored is unknown, not zero', () async {
      CommunityService.invalidate();
      ConnectivityStatus.debugSetOffline(true);
      final CommunityTotals shown = await CommunityService.totals(
        CommunityPeriod.month,
      );
      expect(shown.resolved, isFalse);
    });

    test('a stored board keeps the reader\'s rank only for the same score', () {
      const CommunityLeaderboard board = CommunityLeaderboard(
        top: <CommunityRankEntry>[
          CommunityRankEntry(uid: 'a', name: 'רחל', points: 50),
        ],
        myRank: 4,
        myPoints: 20,
        activeMatchmakers: 12,
      );
      final CommunityLeaderboard same = CommunityLeaderboard.fromJson(
        board.toJson(),
        myPoints: 20,
      )!;
      expect(same.top.single.name, 'רחל');
      expect(same.myRank, 4);
      expect(same.activeMatchmakers, 12);

      final CommunityLeaderboard moved = CommunityLeaderboard.fromJson(
        board.toJson(),
        myPoints: 25,
      )!;
      expect(moved.myRank, isNull);
      expect(moved.myPoints, 25);
    });
  });
}

Person _person(String id, {Gender gender = Gender.male}) {
  final DateTime now = DateTime(2026, 11, 1);
  return Person(
    id: id,
    firstName: 'דוד',
    lastName: 'כהן',
    gender: gender,
    createdAt: now,
    updatedAt: now,
  );
}
