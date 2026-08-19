import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_highlight.dart';

/// The one human sentence on the activity screen.
///
/// Two rules matter more than the wording: it never announces a zero, and it
/// never names anybody. A line saying "0 שדכנים היו פעילים השבוע" is worse than
/// no line, and a line naming the matchmaker behind an engagement would attach
/// a name to a record the app deliberately writes anonymously.
void main() {
  CommunityTotals totals({
    int points = 0,
    int activeMatchmakers = 0,
    int friends = 0,
    int ideas = 0,
    int couples = 0,
    int engagements = 0,
  }) {
    return CommunityTotals(
      points: points,
      activeMatchmakers: activeMatchmakers,
      friends: friends,
      ideas: ideas,
      couples: couples,
      engagements: engagements,
    );
  }

  test('a silent week says nothing at all', () {
    expect(CommunityHighlight.forWeek(totals(), seed: 0), isNull);
    expect(CommunityHighlight.forWeek(CommunityTotals.empty, seed: 7), isNull);
  });

  test('only figures that actually moved can be said', () {
    // Six friends and nothing else: whichever seed comes up, the sentence has
    // to be the one true line.
    final CommunityTotals week = totals(points: 6, friends: 6);
    for (int seed = 0; seed < 5; seed++) {
      expect(
        CommunityHighlight.forWeek(week, seed: seed),
        '6 חברים חדשים נוספו למאגרים של הקהילה השבוע.',
      );
    }
  });

  test('a lone active matchmaker is not told they are a crowd', () {
    // "1 שדכנים כבר היו פעילים השבוע" is the reader, alone, being described as
    // a community. The line needs more than one person before it is true.
    expect(
      CommunityHighlight.forWeek(
        totals(points: 1, activeMatchmakers: 1, ideas: 1),
        seed: 0,
      ),
      isNot(contains('שדכנים')),
    );
  });

  test('the rotation covers every true line and repeats', () {
    final CommunityTotals week = totals(
      points: 120,
      activeMatchmakers: 12,
      friends: 30,
      ideas: 8,
      couples: 2,
      engagements: 1,
    );

    final Set<String?> seen = <String?>{
      for (int seed = 0; seed < 20; seed++)
        CommunityHighlight.forWeek(week, seed: seed),
    };
    expect(seen.length, 5);
  });

  test('nobody is named, whichever line comes up', () {
    final CommunityTotals week = totals(
      points: 60,
      activeMatchmakers: 4,
      couples: 1,
      engagements: 1,
    );

    for (int seed = 0; seed < 6; seed++) {
      final String? line = CommunityHighlight.forWeek(week, seed: seed);
      expect(line, isNotNull);
      expect(line, isNot(contains('שדכן ')));
    }
  });

  test('the seed holds still for a day and moves the next one', () {
    final DateTime morning = DateTime(2026, 8, 19, 7);
    final DateTime evening = DateTime(2026, 8, 19, 23);
    final DateTime tomorrow = DateTime(2026, 8, 20, 7);

    expect(
      CommunityHighlight.seedFor(morning),
      CommunityHighlight.seedFor(evening),
    );
    expect(
      CommunityHighlight.seedFor(tomorrow),
      isNot(CommunityHighlight.seedFor(morning)),
    );
  });
}
