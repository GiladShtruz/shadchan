import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_progress.dart';
import 'package:shadchan/utils/matchmaker_rank.dart';

void main() {
  test('eleven ranks, by ideas opened', () {
    expect(MatchmakerRanks.ladder, hasLength(11));
    expect(MatchmakerRanks.current(4), isNull);
    expect(MatchmakerRanks.current(5)!.male, 'מתחיל לחבר');
    expect(MatchmakerRanks.current(74)!.nameFor(Gender.female), 'שדכנית פעילה');
    expect(MatchmakerRanks.current(100)!.male, 'שדכן מוביל');
    expect(MatchmakerRanks.current(5000)!.male, 'מאסטר שדכן');
    expect(MatchmakerRanks.next(5000), isNull);
  });

  test('progress is measured against the next rank threshold', () {
    // Between 50 (שדכן פעיל) and 75 (שדכן מתקדם).
    expect(MatchmakerRanks.progress(60), closeTo(10 / 25, 1e-9));
    expect(MatchmakerRanks.progress(0), 0);
    expect(MatchmakerRanks.progress(1000), 1);
  });

  test('the home line names the next rank', () {
    final HomeProgress p = HomeProgress.rank(ideas: 43, gender: Gender.male);
    expect(p.line, 'עוד 7 רעיונות כדי להפוך ל־שדכן פעיל');
    expect(p.fractionLabel, '43 מתוך 50 רעיונות');
    expect(p.progress, closeTo(43 / 50, 1e-9));
    expect(HomeProgress.rank(ideas: 1200).fractionLabel, isNull);
    expect(
      HomeProgress.rank(ideas: 49, gender: Gender.female).line,
      'עוד רעיון אחד כדי להפוך ל־שדכנית פעילה',
    );
  });
}
