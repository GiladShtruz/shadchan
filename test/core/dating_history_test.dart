import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';

/// "זוגות שהתחילו לצאת" is the one figure in the app that is a *history* rather
/// than a state, and the only one that can be edited by hand. Both of those
/// make it easy to get wrong in ways nobody notices for months, so the rules are
/// asserted here: the day-long qualifying period, the one-way door, and the
/// fallback that keeps couples from before the status ledger existed in the
/// count.
void main() {
  final DateTime now = DateTime(2026, 8, 15, 12);

  MatchIdea match(
    String id, {
    MatchStatus status = MatchStatus.dating,
    DateTime? updated,
  }) {
    return MatchIdea(
      id: id,
      personAId: 'a-$id',
      personBId: 'b-$id',
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updated ?? now.subtract(const Duration(days: 30)),
    );
  }

  MatchStatusEvent event(
    String matchId,
    MatchStatus to,
    DateTime at, {
    MatchStatus? from,
  }) {
    return MatchStatusEvent(
      id: '$matchId-${to.name}-${at.millisecondsSinceEpoch}',
      matchId: matchId,
      fromStatus: from,
      toStatus: to,
      createdAt: at,
    );
  }

  List<DatingCoupleRecord> historyOf(
    List<MatchIdea> matches,
    List<MatchStatusEvent> events, {
    Set<String> excluded = const <String>{},
  }) {
    return DatingHistory.all(
      matches: matches,
      statusEvents: events,
      excludedMatchIds: excluded,
      now: now,
    );
  }

  test('a couple marked dating for more than a day is counted', () {
    final DateTime started = now.subtract(const Duration(days: 10));
    final List<DatingCoupleRecord> found = historyOf(
      <MatchIdea>[match('m', updated: started)],
      <MatchStatusEvent>[event('m', MatchStatus.dating, started)],
    );

    expect(found, hasLength(1));
    expect(found.single.startedAt, started);
    // Read from the ledger, so the date is exact rather than inferred.
    expect(found.single.estimated, isFalse);
  });

  test('a mis-tap corrected within the day never enters the count', () {
    final DateTime tapped = now.subtract(const Duration(days: 10));
    final List<DatingCoupleRecord> found = historyOf(
      <MatchIdea>[match('m', status: MatchStatus.idea)],
      <MatchStatusEvent>[
        event('m', MatchStatus.dating, tapped),
        event(
          'm',
          MatchStatus.idea,
          tapped.add(const Duration(hours: 2)),
          from: MatchStatus.dating,
        ),
      ],
    );

    expect(found, isEmpty);
  });

  test('a couple marked dating an hour ago is not counted yet', () {
    final DateTime tapped = now.subtract(const Duration(hours: 1));
    expect(
      historyOf(
        <MatchIdea>[match('m', updated: tapped)],
        <MatchStatusEvent>[event('m', MatchStatus.dating, tapped)],
      ),
      isEmpty,
    );
  });

  test('a couple who stopped dating stays in the count', () {
    final DateTime started = now.subtract(const Duration(days: 60));
    final List<DatingCoupleRecord> found = historyOf(
      <MatchIdea>[match('m', status: MatchStatus.dated)],
      <MatchStatusEvent>[
        event('m', MatchStatus.dating, started),
        event(
          'm',
          MatchStatus.dated,
          started.add(const Duration(days: 20)),
          from: MatchStatus.dating,
        ),
      ],
    );

    expect(found, hasLength(1));
    expect(found.single.startedAt, started);
  });

  test('a wedding is in the count too — they went out to get there', () {
    expect(
      historyOf(<MatchIdea>[
        match('m', status: MatchStatus.married),
      ], const <MatchStatusEvent>[]),
      hasLength(1),
    );
  });

  test('a proposal that never went out is not in the count', () {
    expect(
      historyOf(<MatchIdea>[
        match('idea', status: MatchStatus.idea),
        match('checking', status: MatchStatus.checking),
        match('waiting', status: MatchStatus.unavailable),
        match('rejected', status: MatchStatus.rejected),
      ], const <MatchStatusEvent>[]),
      isEmpty,
    );
  });

  test('couples from before the ledger existed are still counted', () {
    // The status ledger only started being written on 2026-08-14. Reading it
    // alone would report an almost empty history on every install that has been
    // in use for longer than that.
    final List<DatingCoupleRecord> found = historyOf(<MatchIdea>[
      match('old', updated: now.subtract(const Duration(days: 200))),
    ], const <MatchStatusEvent>[]);

    expect(found, hasLength(1));
    // Flagged, because the date is the proposal's last update rather than the
    // moment they were marked — the UI has to say "בערך".
    expect(found.single.estimated, isTrue);
  });

  test('the ledger overrules the status when it has an opinion', () {
    // Marked dating, undone inside the hour, and the proposal happens to sit at
    // "יוצאים" again for an unrelated reason later. The ledger's record of the
    // correction is what decides, so the fallback must not quietly re-add them.
    final DateTime tapped = now.subtract(const Duration(days: 5));
    expect(
      historyOf(
        <MatchIdea>[match('m', updated: now.subtract(const Duration(days: 5)))],
        <MatchStatusEvent>[
          event('m', MatchStatus.dating, tapped),
          event(
            'm',
            MatchStatus.idea,
            tapped.add(const Duration(minutes: 30)),
            from: MatchStatus.dating,
          ),
        ],
      ),
      isEmpty,
    );
  });

  test('a couple removed by hand leaves the count and the list', () {
    final DateTime started = now.subtract(const Duration(days: 10));
    final List<MatchIdea> matches = <MatchIdea>[
      match('keep', updated: started),
      match('wrong', updated: started),
    ];
    final List<MatchStatusEvent> events = <MatchStatusEvent>[
      event('keep', MatchStatus.dating, started),
      event('wrong', MatchStatus.dating, started),
    ];

    expect(historyOf(matches, events), hasLength(2));
    final List<DatingCoupleRecord> after = historyOf(
      matches,
      events,
      excluded: <String>{'wrong'},
    );
    expect(after, hasLength(1));
    expect(after.single.match.id, 'keep');
  });

  test('the list runs newest first', () {
    final List<DatingCoupleRecord> found = historyOf(<MatchIdea>[
      match('older', updated: now.subtract(const Duration(days: 90))),
      match('newer', updated: now.subtract(const Duration(days: 3))),
    ], const <MatchStatusEvent>[]);

    expect(found.map((DatingCoupleRecord r) => r.match.id), <String>[
      'newer',
      'older',
    ]);
  });
}
