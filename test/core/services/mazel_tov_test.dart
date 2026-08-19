import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/dating_status_memory.dart';
import 'package:shadchan/utils/enums.dart';

/// The two halves of "פרגון בין שדכנים" that do not need a network: what a
/// received bracha becomes in the journal, and how many times the phone is
/// allowed to buzz about one wedding.
void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('mazel_tov_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MatchIdeaAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MatchNoteAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GenderAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MatchStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(CurrentHandlerAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    people = await Hive.openBox<Person>('people');
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await people.clear();
    await matches.clear();
    await notes.clear();
    await Hive.box<dynamic>('settings').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows keeps the box files locked. Harmless — it is a temp dir.
    }
  });

  MatchRepository repository() => MatchRepository(matches, notes);

  Future<void> seed(String matchId) async {
    final DateTime now = DateTime(2026, 8, 19);
    await matches.put(
      matchId,
      MatchIdea(
        id: matchId,
        personAId: 'male',
        personBId: 'female',
        status: MatchStatus.married,
        currentHandler: CurrentHandler.me,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  group('a bracha in the journal', () {
    test('is filed against the proposal it is about', () async {
      await seed('m1');
      final MatchRepository repo = repository();

      final bool written = await repo.addMazelTov(
        matchId: 'm1',
        text: 'מזל טוב! שיזכו לבנות בית נאמן בישראל',
        fromName: 'שרה',
      );

      expect(written, isTrue);
      final List<MatchNote> journal = repo.getNotesForMatch('m1');
      expect(journal, hasLength(1));
      expect(journal.single.text, 'מזל טוב! שיזכו לבנות בית נאמן בישראל');
      // The name is what turns the line from an automatic status note into
      // somebody's good wishes, and it is what the journal draws in gold.
      expect(journal.single.mazelTovFrom, 'שרה');
    });

    test(
      'from a matchmaker who publishes no name still has a sender',
      () async {
        await seed('m1');
        final MatchRepository repo = repository();

        await repo.addMazelTov(matchId: 'm1', text: 'ישר כוח!', fromName: '  ');

        expect(repo.getNotesForMatch('m1').single.mazelTovFrom, 'שדכן מהקהילה');
      },
    );

    test(
      'for a proposal that no longer exists is dropped, not filed',
      () async {
        final MatchRepository repo = repository();

        final bool written = await repo.addMazelTov(
          matchId: 'deleted',
          text: 'מזל טוב',
          fromName: 'שרה',
        );

        expect(written, isFalse);
        expect(notes.values, isEmpty);
      },
    );
  });

  group('the notification', () {
    test('fires once per wedding, however many brachot arrive', () {
      expect(CommunityPromptsStore.hasNotifiedMazelTov('m1'), isFalse);

      CommunityPromptsStore.markMazelTovNotified('m1');

      // The second, third and tenth message about the same couple are still
      // filed in the journal — they simply do not buzz the phone again.
      expect(CommunityPromptsStore.hasNotifiedMazelTov('m1'), isTrue);
      expect(CommunityPromptsStore.hasNotifiedMazelTov('m2'), isFalse);
    });

    test('a delivered message is never filed twice', () {
      expect(CommunityPromptsStore.hasDeliveredMazelTov('msg1'), isFalse);
      CommunityPromptsStore.markMazelTovDelivered('msg1');
      expect(CommunityPromptsStore.hasDeliveredMazelTov('msg1'), isTrue);
    });
  });

  group('what a candidate was before the couple went out', () {
    test('is remembered and put back', () async {
      await DatingStatusMemory.remember(
        matchId: 'm1',
        personId: 'p1',
        status: ProfileStatus.onBreak,
      );

      expect(
        DatingStatusMemory.restoreFor(matchId: 'm1', personId: 'p1'),
        ProfileStatus.onBreak,
      );

      await DatingStatusMemory.forget(matchId: 'm1', personId: 'p1');
      expect(
        DatingStatusMemory.restoreFor(matchId: 'm1', personId: 'p1'),
        ProfileStatus.available,
      );
    });

    test('defaults to פנוי for every couple from before this existed', () {
      expect(
        DatingStatusMemory.restoreFor(matchId: 'old', personId: 'p1'),
        ProfileStatus.available,
      );
    });

    test(
      'is kept per proposal, so two dates do not overwrite each other',
      () async {
        await DatingStatusMemory.remember(
          matchId: 'm1',
          personId: 'p1',
          status: ProfileStatus.onBreak,
        );
        await DatingStatusMemory.remember(
          matchId: 'm2',
          personId: 'p1',
          status: ProfileStatus.available,
        );

        expect(
          DatingStatusMemory.restoreFor(matchId: 'm1', personId: 'p1'),
          ProfileStatus.onBreak,
        );
        expect(
          DatingStatusMemory.restoreFor(matchId: 'm2', personId: 'p1'),
          ProfileStatus.available,
        );
      },
    );

    test(
      'never remembers תפוס or מזל טוב — there is nothing to undo',
      () async {
        await DatingStatusMemory.remember(
          matchId: 'm1',
          personId: 'p1',
          status: ProfileStatus.busy,
        );
        await DatingStatusMemory.remember(
          matchId: 'm1',
          personId: 'p2',
          status: ProfileStatus.mazelTov,
        );

        expect(
          DatingStatusMemory.restoreFor(matchId: 'm1', personId: 'p1'),
          ProfileStatus.available,
        );
        expect(
          DatingStatusMemory.restoreFor(matchId: 'm1', personId: 'p2'),
          ProfileStatus.available,
        );
      },
    );
  });

  group('the whole round trip', () {
    test('a candidate on a break goes back on their break', () async {
      final DateTime now = DateTime(2026, 8, 19);
      for (final ({String id, Gender gender}) side
          in <({String id, Gender gender})>[
            (id: 'male', gender: Gender.male),
            (id: 'female', gender: Gender.female),
          ]) {
        await people.put(
          side.id,
          Person(
            id: side.id,
            firstName: side.id,
            lastName: '',
            gender: side.gender,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await matches.put(
        'm1',
        MatchIdea(
          id: 'm1',
          personAId: 'male',
          personBId: 'female',
          status: MatchStatus.idea,
          currentHandler: CurrentHandler.me,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final PersonRepository personRepository = PersonRepository(people);
      final MatchRepository matchRepository = MatchRepository(matches, notes)
        ..resolvePerson = personRepository.getById
        ..markPersonBusy = ((String personId, String matchId) =>
            personRepository.updateProfileStatus(
              personId,
              ProfileStatus.busy,
              causedByMatchId: matchId,
            ))
        ..restorePersonStatus =
            ((String personId, ProfileStatus status, String matchId) =>
                personRepository.updateProfileStatus(
                  personId,
                  status,
                  causedByMatchId: matchId,
                ));
      personRepository.onPersonStatusChanged =
          matchRepository.syncMatchesForPerson;

      // She is taking a break when the proposal moves to "יוצאים".
      await personRepository.updateProfileStatus(
        'female',
        ProfileStatus.onBreak,
      );
      await matchRepository.updateStatus('m1', MatchStatus.dating);
      expect(
        personRepository.getById('female')!.profileStatus,
        ProfileStatus.busy,
      );

      await matchRepository.updateStatus('m1', MatchStatus.dated);

      // He was available and goes back to available; she was on a break and is
      // put back on it rather than quietly returned to the pool.
      expect(
        personRepository.getById('male')!.profileStatus,
        ProfileStatus.available,
      );
      expect(
        personRepository.getById('female')!.profileStatus,
        ProfileStatus.onBreak,
      );
    });
  });
}
