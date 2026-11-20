import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_progress.dart';
import 'package:shadchan/utils/matchmaker_rank.dart';

void main() {
  test('nine ranks, by ideas opened, from zero', () {
    expect(MatchmakerRanks.ladder, hasLength(9));
    expect(MatchmakerRanks.current(0).male, 'שדכן מתחיל');
    expect(MatchmakerRanks.current(14).male, 'שדכן מתחיל');
    expect(MatchmakerRanks.current(15).male, 'שדכן חבר');
    expect(MatchmakerRanks.current(99).nameFor(Gender.female), 'שדכנית פעילה');
    expect(MatchmakerRanks.current(219).male, 'שדכן מקצוען');
    expect(MatchmakerRanks.current(999).male, 'שדכן־על');
    expect(MatchmakerRanks.current(5000).male, 'מאסטר שדכן');
    expect(MatchmakerRanks.current(5000).emoji, '💎');
    expect(MatchmakerRanks.next(5000), isNull);
  });

  test('"+" half way to the next rank, never on the first or the last', () {
    expect(MatchmakerRanks.plus(10), isFalse); // מתחיל: never.
    expect(MatchmakerRanks.plus(32), isFalse); // 15→50: half is 32.5.
    expect(MatchmakerRanks.plus(33), isTrue);
    expect(MatchmakerRanks.nameAt(33, Gender.male), 'שדכן חבר+');
    expect(MatchmakerRanks.nameAt(75, Gender.female), 'שדכנית פעילה+');
    expect(MatchmakerRanks.nameAt(74, Gender.male), 'שדכן פעיל');
    expect(MatchmakerRanks.nameAt(250, Gender.male), 'שדכן מקצוען+');
    expect(MatchmakerRanks.plus(4000), isFalse); // מאסטר: no next rank.
    expect(MatchmakerRanks.titleAt(219, Gender.male), '🏅 שדכן מקצוען');
  });

  test('progress is ideas out of the next rank threshold', () {
    expect(MatchmakerRanks.progress(118), closeTo(118 / 150, 1e-9));
    expect(MatchmakerRanks.progress(0), 0);
    expect(MatchmakerRanks.progress(1000), 1);
  });

  test('the home line: rank and figures, then what is next', () {
    final HomeProgress p = HomeProgress.rank(ideas: 219, gender: Gender.male);
    expect(p.line, '🏅 שדכן מקצוען · 219/300 רעיונות');
    expect(p.subline, 'עוד 81 רעיונות לשדכן בכיר 🏆');
    expect(p.progress, closeTo(219 / 300, 1e-9));
    expect(p.rankIdeas, 219);
    expect(
      HomeProgress.rank(ideas: 149, gender: Gender.female).subline,
      'עוד רעיון אחד לשדכנית מצטיינת ⭐',
    );
    expect(HomeProgress.rank(ideas: 1200).fractionLabel, isNull);
  });
}
