import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_promote.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/home_stats_banner.dart';

/// The rules that decide what the home screen shows.
///
/// These are asserted rather than left to the widget tree because the whole
/// design rests on them: a block drawn at the wrong stage is an empty box in
/// front of a new user, and a reproachful number is worse than no number.
void main() {
  final DateTime now = DateTime(2026, 8, 13);

  Person person({
    required String id,
    DateTime? created,
    DateTime? updated,
    Gender gender = Gender.male,
  }) {
    return Person(
      id: id,
      firstName: 'שם$id',
      lastName: 'משפחה',
      gender: gender,
      manualAge: 27,
      createdAt: created ?? now,
      updatedAt: updated ?? now,
    );
  }

  MatchIdea match({
    required String id,
    required String a,
    required String b,
    MatchStatus status = MatchStatus.idea,
    DateTime? updated,
  }) {
    return MatchIdea(
      id: id,
      personAId: a,
      personBId: b,
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: now,
      updatedAt: updated ?? now,
    );
  }

  group('stages', () {
    test('the boundaries fall exactly where the brief puts them', () {
      expect(HomeStage.forCount(0), HomeStage.starting);
      expect(HomeStage.forCount(9), HomeStage.starting);
      expect(HomeStage.forCount(10), HomeStage.building);
      expect(HomeStage.forCount(24), HomeStage.building);
      expect(HomeStage.forCount(25), HomeStage.balancing);
      expect(HomeStage.forCount(49), HomeStage.balancing);
      expect(HomeStage.forCount(50), HomeStage.managing);
      expect(HomeStage.forCount(99), HomeStage.managing);
      expect(HomeStage.forCount(100), HomeStage.full);
      expect(HomeStage.forCount(4000), HomeStage.full);
    });

    test('a nearly empty database is shown no idea areas at all', () {
      expect(HomeStage.starting.showsIdeaAreas, isFalse);
      expect(HomeStage.building.showsIdeaAreas, isTrue);
    });

    test('the import tool leaves the home screen at fifty friends', () {
      expect(HomeStage.forCount(49).showsImportTool, isTrue);
      expect(HomeStage.forCount(50).showsImportTool, isFalse);
      expect(HomeStage.forCount(120).showsImportTool, isFalse);
    });

    test('the automatic suggestions only lead from a hundred friends', () {
      expect(HomeStage.forCount(99).leadsWithAutomaticIdeas, isFalse);
      expect(HomeStage.forCount(100).leadsWithAutomaticIdeas, isTrue);
    });

    test('the target stops being a headline once it is passed', () {
      expect(HomeStage.forCount(99).showsTarget, isTrue);
      expect(HomeStage.forCount(100).showsTarget, isFalse);
    });
  });

  group('milestones', () {
    test('the target advances in stages rather than jumping to a hundred', () {
      expect(HomeMilestone.forCount(0).target, 10);
      expect(HomeMilestone.forCount(9).target, 10);
      expect(HomeMilestone.forCount(10).target, 25);
      expect(HomeMilestone.forCount(30).target, 50);
      expect(HomeMilestone.forCount(70).target, 100);
      expect(HomeMilestone.forCount(100).target, isNull);
    });

    test('progress is measured against the current stage, not the last', () {
      expect(HomeMilestone.forCount(5).progress, closeTo(0.5, 0.001));
      expect(HomeMilestone.forCount(20).progress, closeTo(0.8, 0.001));
    });

    test('the message names the milestone ahead and never a shortfall', () {
      expect(HomeMilestone.forCount(9).message, contains('10'));
      expect(HomeMilestone.forCount(0).message, isNot(contains('0 ')));
      expect(HomeMilestone.forCount(100).isReached, isTrue);
    });
  });

  group('the numbers banner', () {
    test('a personal fact always wins over a general one', () {
      final line = HomeStatsBanner.build(
        matches: <MatchIdea>[
          match(id: 'm', a: 'a', b: 'b', status: MatchStatus.dating),
        ],
        friends: 3,
        now: now,
      );
      expect(line.isPersonal, isTrue);
      expect(line.text, contains('יוצא'));
    });

    test(
      'with nothing to celebrate it encourages instead of showing a nil',
      () {
        final line = HomeStatsBanner.build(
          matches: const <MatchIdea>[],
          friends: 0,
          now: now,
        );
        expect(line.isPersonal, isFalse);
        expect(line.text, isNot(contains('0')));
      },
    );

    test('it never reports a decline or an empty month', () {
      for (int friends = 0; friends < 200; friends += 7) {
        final line = HomeStatsBanner.build(
          matches: const <MatchIdea>[],
          friends: friends,
          now: now,
        );
        expect(line.text, isNot(contains('ירידה')));
        expect(line.text, isNot(contains('פחות')));
      }
    });
  });

  group('שווה לקדם', () {
    test('every card carries a reason', () {
      final List<Person> people = <Person>[
        person(id: '1', created: now.subtract(const Duration(days: 400))),
        person(id: '2', created: now.subtract(const Duration(days: 3))),
        person(
          id: '3',
          created: now.subtract(const Duration(days: 400)),
          updated: now.subtract(const Duration(days: 200)),
        ),
      ];
      final List<HomePromoteItem> items = HomePromote.build(
        people: people,
        matches: const <MatchIdea>[],
        personById: (String id) => null,
        now: now,
      );

      expect(items, isNotEmpty);
      for (final HomePromoteItem item in items) {
        expect(item.reason.trim(), isNotEmpty);
        expect(item.title.trim(), isNotEmpty);
      }
    });

    test('it never offers more than five at once', () {
      final List<Person> people = <Person>[
        for (int i = 0; i < 30; i++)
          person(id: '$i', created: now.subtract(const Duration(days: 400))),
      ];
      final List<HomePromoteItem> items = HomePromote.build(
        people: people,
        matches: const <MatchIdea>[],
        personById: (String id) => null,
        now: now,
      );
      expect(items.length, lessThanOrEqualTo(HomePromote.maxItems));
    });

    test('consecutive visits are given different items', () {
      final List<Person> people = <Person>[
        for (int i = 0; i < 20; i++)
          person(id: '$i', created: now.subtract(const Duration(days: 400))),
      ];
      List<String> idsFor(int rotation) => HomePromote.build(
        people: people,
        matches: const <MatchIdea>[],
        personById: (String id) => null,
        now: now,
        rotation: rotation,
      ).map((HomePromoteItem item) => item.id).toList();

      expect(idsFor(1), isNot(equals(idsFor(2))));
    });

    test('a stale profile is judged on its last real edit', () {
      final Person fresh = person(
        id: 'fresh',
        created: now.subtract(const Duration(days: 400)),
        updated: now.subtract(const Duration(days: 2)),
      );
      final Person stale = person(
        id: 'stale',
        created: now.subtract(const Duration(days: 400)),
        updated: now.subtract(const Duration(days: 300)),
      );
      final List<HomePromoteItem> items = HomePromote.build(
        people: <Person>[fresh, stale],
        matches: const <MatchIdea>[],
        personById: (String id) => null,
        now: now,
      );
      final HomePromoteItem staleItem = items.firstWhere(
        (HomePromoteItem item) => item.person?.id == 'stale',
      );
      expect(staleItem.reason, contains('לא עודכן'));
    });

    test('an old note is a reason of its own', () {
      final Person friend = person(
        id: 'noted',
        created: now.subtract(const Duration(days: 400)),
        updated: now.subtract(const Duration(days: 5)),
      );
      final List<HomePromoteItem> items = HomePromote.build(
        people: <Person>[friend],
        matches: <MatchIdea>[match(id: 'm', a: 'noted', b: 'other')],
        personById: (String id) => null,
        notes: <PersonNote>[
          PersonNote(
            id: 'n',
            personId: 'noted',
            text: 'שווה לבדוק שוב',
            createdAt: now.subtract(const Duration(days: 300)),
            isAutomatic: false,
          ),
        ],
        now: now,
      );
      expect(
        items.any((HomePromoteItem item) => item.reason.contains('הערה ישנה')),
        isTrue,
      );
    });
  });
}
