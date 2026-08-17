import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/monthly_stats.dart';

void main() {
  final MonthPeriod august = MonthPeriod(
    start: DateTime(2026, 8, 1),
    end: DateTime(2026, 9, 1),
    label: '',
    shortLabel: '',
  );

  MatchIdea match(String id, MatchStatus status, DateTime updatedAt) {
    return MatchIdea(
      id: id,
      personAId: 'a-$id',
      personBId: 'b-$id',
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  test('weddings metric is an all-time total', () {
    final List<MatchIdea> matches = <MatchIdea>[
      match('old', MatchStatus.married, DateTime(2020, 1, 1)),
      match('new', MatchStatus.married, DateTime(2026, 8, 1)),
      match('dating', MatchStatus.dating, DateTime(2026, 8, 1)),
    ];
    const MonthStats monthly = MonthStats(
      ideas: 3,
      people: 4,
      dating: 1,
      weddings: 1,
    );

    final MonthStats displayed = MonthlyStats.withAllTimeTotals(
      monthly,
      matches,
      const <MatchStatusEvent>[],
    );
    expect(displayed.weddings, 2);
    expect(MonthlyStatMetric.weddings.title, 'חתונות בכל הזמנים');

    final List<MatchIdea> detailed = MonthlyStats.matchesFor(
      MonthlyStatMetric.weddings,
      august,
      matches,
    );
    expect(
      detailed.map((MatchIdea item) => item.id),
      containsAll(<String>['old', 'new']),
    );
  });

  test('the dating metric is an all-time total too', () {
    // A couple who started dating years ago, one who stopped, and one wedding —
    // all three went out, so all three are part of what this matchmaker did,
    // whichever month the screen happens to be showing.
    final List<MatchIdea> matches = <MatchIdea>[
      match('long-ago', MatchStatus.dating, DateTime(2021, 3, 4)),
      match('stopped', MatchStatus.dated, DateTime(2024, 6, 1)),
      match('married', MatchStatus.married, DateTime(2025, 2, 2)),
      match('never', MatchStatus.idea, DateTime(2026, 8, 1)),
    ];
    const MonthStats monthly = MonthStats(
      ideas: 1,
      people: 0,
      dating: 0,
      weddings: 0,
    );

    final MonthStats displayed = MonthlyStats.withAllTimeTotals(
      monthly,
      matches,
      const <MatchStatusEvent>[],
    );
    expect(displayed.dating, 3);
    // Both historic figures drop the month from their heading and the
    // month-over-month chip along with it.
    expect(MonthlyStatMetric.dating.isAllTime, isTrue);
    expect(MonthlyStatMetric.weddings.isAllTime, isTrue);
    expect(MonthlyStatMetric.ideas.isAllTime, isFalse);
    expect(MonthlyStatMetric.people.isAllTime, isFalse);
  });

  test('the dating drill-down lists every couple, not this month\'s', () {
    final List<MatchIdea> matches = <MatchIdea>[
      match('long-ago', MatchStatus.dating, DateTime(2021, 3, 4)),
      match('recent', MatchStatus.dating, DateTime(2026, 8, 2)),
    ];

    final List<MatchIdea> detailed = MonthlyStats.matchesFor(
      MonthlyStatMetric.dating,
      august,
      matches,
    );
    expect(
      detailed.map((MatchIdea item) => item.id),
      containsAll(<String>['long-ago', 'recent']),
    );

    // A couple taken out by hand leaves the drill-down as well as the figure.
    final List<MatchIdea> trimmed = MonthlyStats.matchesFor(
      MonthlyStatMetric.dating,
      august,
      matches,
      excludedFromDating: <String>{'recent'},
    );
    expect(trimmed.map((MatchIdea item) => item.id), <String>['long-ago']);
  });
}
