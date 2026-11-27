import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/score_ledger.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/enums.dart';

/// The scoring rules, one QA scenario per test.
///
/// Friend from the contacts = 1 · personal card = 2 in all · idea = 1 ·
/// dating = 5 · engaged = 50, every event once only, and the per-friend
/// figure adds the pair events to *both* friends.
void main() {
  late Directory dir;
  final DateTime now = DateTime(2026, 12, 10, 12);
  final DateTime day = DateTime(2026, 12, 9, 10);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('score_ledger');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('settings');
    ScoreLedger.resetForTest();
  });

  tearDown(() async {
    await Hive.close();
    ScoreLedger.resetForTest();
    await dir.delete(recursive: true);
  });

  Person friend(
    String id, {
    String? source,
    String? phone,
    String? card,
    DateTime? created,
  }) {
    return Person(
      id: id,
      firstName: 'שם$id',
      lastName: 'משפחה',
      gender: Gender.male,
      phone: phone,
      source: source,
      cardOwnerUid: card,
      createdAt: created ?? day,
      updatedAt: created ?? day,
    );
  }

  MatchIdea idea(
    String id,
    String a,
    String b, {
    MatchStatus status = MatchStatus.idea,
    DateTime? updated,
  }) {
    return MatchIdea(
      id: id,
      personAId: a,
      personBId: b,
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: day,
      updatedAt: updated ?? day,
    );
  }

  MatchStatusEvent moved(
    String id,
    String matchId,
    MatchStatus to,
    DateTime at, {
    MatchStatus from = MatchStatus.idea,
  }) {
    return MatchStatusEvent(
      id: id,
      matchId: matchId,
      fromStatus: from,
      toStatus: to,
      createdAt: at,
    );
  }

  int total({
    List<Person> people = const <Person>[],
    List<MatchIdea> matches = const <MatchIdea>[],
    List<MatchStatusEvent> events = const <MatchStatusEvent>[],
    DateTime? at,
  }) {
    return ActivityStats.breakdownBetween(
      start: DateTime(2000),
      end: DateTime(2100),
      people: people,
      matches: matches,
      matchStatusEvents: events,
      now: at ?? now,
    ).points;
  }

  test('1. a friend added from the contacts is one point', () {
    final Person p = friend('a', source: 'סריקה', phone: '0521234567');
    expect(total(people: <Person>[p]), 1);
    expect(ScoreLedger.pointsFor(p), 1);
  });

  test('2. a friend added by hand, by AI or by a share earns nothing', () {
    expect(
      total(
        people: <Person>[
          friend('a'),
          friend('b', source: 'ייבוא AI'),
          friend('c', source: 'רעיון משותף עם דנה'),
        ],
      ),
      0,
    );
  });

  test('3. a contacts friend who then approves their card totals 2, not 3', () {
    final Person p = friend('a', source: 'סריקה', phone: '0521234567');
    expect(total(people: <Person>[p]), 1);
    p.cardOwnerUid = 'owner-1';
    ScoreLedger.recordCard(p);
    expect(total(people: <Person>[p]), 2);
    expect(ScoreLedger.pointsFor(p), 2);
    expect(
      ScoreLedger.events
          .firstWhere((e) => e.type == ScoreEventType.card)
          .points,
      1,
    );
  });

  test('4. a card with no earlier contacts friend is 2 at once', () {
    final Person p = friend('a', source: 'כרטיס אישי', card: 'owner-1');
    ScoreLedger.recordCard(p);
    expect(total(people: <Person>[p]), 2);
    expect(ScoreLedger.pointsFor(p), 2);
  });

  test('5. an idea is +1 overall and +1 on each of the two friends', () {
    final Person a = friend('a', source: 'סריקה', phone: '0521111111');
    final Person b = friend('b', card: 'owner-b');
    final List<Person> people = <Person>[a, b];
    final int before = total(people: people);
    final int after = total(
      people: people,
      matches: <MatchIdea>[idea('m1', 'a', 'b')],
    );
    expect(after - before, 1);
    expect(ScoreLedger.pointsFor(a), 1 + 1);
    expect(ScoreLedger.pointsFor(b), 2 + 1);
  });

  test('6-7. dating +5 and engaged +50, once overall and on each card', () {
    final Person a = friend('a', source: 'סריקה', phone: '0521111111');
    final Person b = friend('b', source: 'סריקה', phone: '0522222222');
    final MatchIdea m = idea('m1', 'a', 'b', status: MatchStatus.married);
    final List<MatchStatusEvent> events = <MatchStatusEvent>[
      moved('e1', 'm1', MatchStatus.dating, DateTime(2026, 12, 9, 11)),
      moved(
        'e2',
        'm1',
        MatchStatus.married,
        DateTime(2026, 12, 9, 12),
        from: MatchStatus.dating,
      ),
    ];
    expect(
      total(people: <Person>[a, b], matches: <MatchIdea>[m], events: events),
      1 + 1 + 1 + 5 + 50,
    );
    expect(ScoreLedger.pointsFor(a), 1 + 1 + 5 + 50);
    expect(ScoreLedger.pointsFor(b), 1 + 1 + 5 + 50);
  });

  test('8. status back and forth never pays twice', () {
    final List<Person> people = <Person>[friend('a'), friend('b')];
    final MatchIdea m = idea('m1', 'a', 'b', status: MatchStatus.dating);
    final List<MatchStatusEvent> events = <MatchStatusEvent>[
      moved('e1', 'm1', MatchStatus.dating, DateTime(2026, 12, 1)),
      moved(
        'e2',
        'm1',
        MatchStatus.idea,
        DateTime(2026, 12, 3),
        from: MatchStatus.dating,
      ),
      moved('e3', 'm1', MatchStatus.dating, DateTime(2026, 12, 5)),
    ];
    final int points = total(
      people: people,
      matches: <MatchIdea>[m],
      events: events,
    );
    expect(points, 1 + 5);
    // Out of "יוצאים" for good: the five stay, no second five later.
    m.status = MatchStatus.dated;
    expect(
      total(people: people, matches: <MatchIdea>[m], events: events),
      1 + 5,
    );
  });

  test('9. deleting a friend and adding them again earns nothing more', () {
    final Person first = friend('a', source: 'סריקה', phone: '0521234567');
    expect(total(people: <Person>[first]), 1);
    // Deleted, then the same contact added again — a new record, same phone.
    final Person again = friend('a2', source: 'סריקה', phone: '052-123-4567');
    expect(total(people: <Person>[again]), 1);
    expect(ScoreLedger.pointsFor(again), 1);
  });

  test('a revoked and re-approved card earns nothing twice', () {
    final Person p = friend('a', source: 'כרטיס אישי', card: 'owner-1');
    ScoreLedger.recordCard(p);
    p.cardOwnerUid = null; // access revoked
    expect(total(people: <Person>[p]), 2);
    p.cardOwnerUid = 'owner-1'; // approved again
    ScoreLedger.recordCard(p);
    expect(total(people: <Person>[p]), 2);
  });

  test('a card-first friend later re-added from the contacts stays at 2', () {
    final Person p = friend(
      'a',
      source: 'כרטיס אישי',
      phone: '0521234567',
      card: 'owner-1',
    );
    ScoreLedger.recordCard(p);
    final Person readded = friend('a2', source: 'סריקה', phone: '0521234567');
    expect(total(people: <Person>[readded]), 2);
  });

  test('10. an approved shared idea scores like any idea (one per side)', () {
    // The partner's friend arrives as a hidden record on this side.
    final Person mine = friend('a', source: 'סריקה', phone: '0521111111');
    final Person theirs = Person(
      id: 'h',
      firstName: 'חבר',
      lastName: 'משותף',
      gender: Gender.female,
      source: 'רעיון משותף עם דנה',
      hidden: true,
      createdAt: day,
      updatedAt: day,
    );
    expect(
      total(
        people: <Person>[mine, theirs],
        matches: <MatchIdea>[idea('m1', 'a', 'h')],
      ),
      1 + 1,
    );
  });

  test('11. a proposal not yet approved is not an idea, and earns nothing', () {
    // Nothing exists locally until the other side approves.
    expect(total(people: <Person>[friend('a')]), 0);
  });

  test('a mis-tap taken back within a day is retracted', () {
    final List<Person> people = <Person>[friend('a'), friend('b')];
    final MatchIdea m = idea('m1', 'a', 'b', status: MatchStatus.dating);
    final DateTime marked = DateTime(2026, 12, 10, 9);
    final List<MatchStatusEvent> marking = <MatchStatusEvent>[
      moved('e1', 'm1', MatchStatus.dating, marked),
    ];
    expect(
      total(people: people, matches: <MatchIdea>[m], events: marking),
      1 + 5,
    );
    m.status = MatchStatus.idea;
    final List<MatchStatusEvent> undone = <MatchStatusEvent>[
      ...marking,
      moved(
        'e2',
        'm1',
        MatchStatus.idea,
        DateTime(2026, 12, 10, 9, 5),
        from: MatchStatus.dating,
      ),
    ];
    expect(total(people: people, matches: <MatchIdea>[m], events: undone), 1);
  });

  test('friends from before the rules changed keep their point', () {
    final Person old = friend('a', created: DateTime(2026, 8, 1));
    expect(total(people: <Person>[old]), 1);
    expect(ScoreLedger.events.single.legacy, isTrue);
  });

  test(
    '12. events are stored as settings, one per event, and recountable',
    () async {
      total(
        people: <Person>[friend('a', source: 'סריקה', phone: '0521234567')],
      );
      await Future<void>.delayed(Duration.zero);
      final Box<dynamic> settings = Hive.box<dynamic>('settings');
      final List<String> keys = settings.keys
          .whereType<String>()
          .where((String k) => k.startsWith(ScoreLedger.prefix))
          .toList();
      expect(keys, hasLength(1));
      // Read back from disk alone, the total is the same.
      ScoreLedger.forgetCache();
      expect(
        ActivityStats.fromEvents(
          ScoreLedger.events,
          start: DateTime(2000),
          end: DateTime(2100),
        ).points,
        1,
      );
    },
  );
}
