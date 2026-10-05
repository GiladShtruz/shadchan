import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/idea_recency.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';

/// The ideas list's order, how long a couple went out, and the home search
/// filter's rule.
void main() {
  final DateTime t0 = DateTime(2026, 9, 1, 12);

  MatchIdea idea(
    String id, {
    DateTime? created,
    String a = 'm',
    String b = 'f',
  }) {
    return MatchIdea(
      id: id,
      personAId: a,
      personBId: b,
      status: MatchStatus.idea,
      currentHandler: CurrentHandler.me,
      createdAt: created ?? t0,
      updatedAt: created ?? t0,
    );
  }

  group('IdeaRecency', () {
    test('a status change and a person status change both count', () {
      final MatchIdea old = idea('old', a: 'm1', b: 'f1');
      final MatchIdea newer = idea(
        'newer',
        created: t0.add(const Duration(days: 2)),
        a: 'm2',
        b: 'f2',
      );
      final Map<String, DateTime> recency = IdeaRecency.of(
        matches: <MatchIdea>[old, newer],
        statusEvents: <MatchStatusEvent>[],
        personEvents: <PersonEvent>[
          PersonEvent(
            id: 'e',
            personId: 'f1',
            type: PersonEventType.statusChanged,
            text: '',
            createdAt: t0.add(const Duration(days: 5)),
          ),
        ],
      );
      expect(recency['old'], t0.add(const Duration(days: 5)));
      expect(recency['newer'], t0.add(const Duration(days: 2)));

      final Map<String, DateTime> byIdea = IdeaRecency.of(
        matches: <MatchIdea>[old],
        statusEvents: <MatchStatusEvent>[
          MatchStatusEvent(
            id: 's',
            matchId: 'old',
            fromStatus: MatchStatus.idea,
            toStatus: MatchStatus.checking,
            createdAt: t0.add(const Duration(days: 3)),
          ),
        ],
        personEvents: <PersonEvent>[],
      );
      expect(byIdea['old'], t0.add(const Duration(days: 3)));
    });

    test('a note on a person is not an update', () {
      final Map<String, DateTime> recency = IdeaRecency.of(
        matches: <MatchIdea>[idea('x')],
        statusEvents: <MatchStatusEvent>[],
        personEvents: <PersonEvent>[
          PersonEvent(
            id: 'n',
            personId: 'm',
            type: PersonEventType.values.firstWhere(
              (PersonEventType type) => type != PersonEventType.statusChanged,
            ),
            text: '',
            createdAt: t0.add(const Duration(days: 9)),
          ),
        ],
      );
      expect(recency['x'], t0);
    });
  });

  group('dating span', () {
    late Directory directory;
    late MatchRepository repository;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('dating_span_');
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(MatchIdeaAdapter());
      }
      repository = MatchRepository(
        await Hive.openBox<MatchIdea>('span_matches'),
        await Hive.openBox<MatchNote>('span_notes'),
      );
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('going out starts the clock and stopping keeps the span', () {
      final MatchIdea match = idea('a');
      repository.noteDatingSpan(
        match,
        from: MatchStatus.checking,
        to: MatchStatus.dating,
        at: t0,
      );
      expect(match.datingStartedAt, t0);
      expect(match.datingEndedAt, isNull);

      match.status = MatchStatus.dating;
      final DateTime stopped = t0.add(const Duration(days: 21));
      repository.noteDatingSpan(
        match,
        from: MatchStatus.dating,
        to: MatchStatus.dated,
        at: stopped,
      );
      expect(match.datingStartedAt, t0);
      expect(match.datingEndedAt, stopped);
      expect(match.datingSpan(), const Duration(days: 21));
    });

    test('going back out within a day is the same stretch', () {
      final MatchIdea match = idea('b')
        ..datingStartedAt = t0
        ..datingEndedAt = t0.add(const Duration(days: 10));
      repository.noteDatingSpan(
        match,
        from: MatchStatus.dated,
        to: MatchStatus.dating,
        at: t0.add(const Duration(days: 10, hours: 2)),
      );
      expect(match.datingStartedAt, t0);
      expect(match.datingEndedAt, isNull);
    });

    test('going out again much later starts a new stretch', () {
      final MatchIdea match = idea('c')
        ..datingStartedAt = t0
        ..datingEndedAt = t0.add(const Duration(days: 10));
      final DateTime again = t0.add(const Duration(days: 60));
      repository.noteDatingSpan(
        match,
        from: MatchStatus.idea,
        to: MatchStatus.dating,
        at: again,
      );
      expect(match.datingStartedAt, again);
    });
  });

  group('PeopleFilterState.matches', () {
    Person person({int? age, Region? region, MaritalStatus? marital}) {
      return Person(
        id: 'p',
        firstName: 'שם',
        lastName: 'משפחה',
        gender: Gender.female,
        manualAge: age,
        region: region,
        maritalStatus: marital,
        createdAt: t0,
        updatedAt: t0,
      );
    }

    test('an empty filter passes everybody', () {
      const PeopleFilterState none = PeopleFilterState(
        gender: null,
        ageRange: null,
        religiousLevels: <ReligiousLevel>[],
        profileStatuses: <ProfileStatus>[],
      );
      expect(none.isEmpty, isTrue);
      expect(none.matches(person()), isTrue);
    });

    test('a range or a region only matches a card that records one', () {
      const PeopleFilterState filter = PeopleFilterState(
        gender: Gender.female,
        ageRange: RangeValues(24, 30),
        religiousLevels: <ReligiousLevel>[],
        profileStatuses: <ProfileStatus>[],
        regions: <Region>[Region.south],
      );
      expect(filter.matches(person(age: 26, region: Region.south)), isTrue);
      expect(filter.matches(person(age: 26)), isFalse);
      expect(filter.matches(person(region: Region.south)), isFalse);
      expect(filter.matches(person(age: 35, region: Region.south)), isFalse);
    });
  });
}
