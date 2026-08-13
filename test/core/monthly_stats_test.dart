import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/monthly_stats.dart';

void main() {
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

    final MonthStats displayed = MonthlyStats.withAllTimeWeddings(
      monthly,
      matches,
    );
    expect(displayed.weddings, 2);
    expect(MonthlyStatMetric.weddings.title, 'חתונות בכל הזמנים');

    final List<MatchIdea> detailed = MonthlyStats.matchesFor(
      MonthlyStatMetric.weddings,
      MonthPeriod(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 9, 1),
        label: '',
        shortLabel: '',
      ),
      matches,
    );
    expect(
      detailed.map((MatchIdea item) => item.id),
      containsAll(<String>['old', 'new']),
    );
  });
}
