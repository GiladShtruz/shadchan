import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_highlight.dart';
import 'package:shadchan/utils/community_milestones.dart';

CommunityTotals _totals({
  int friends = 0,
  int ideas = 0,
  int couples = 0,
  int engagements = 0,
  int active = 0,
}) {
  return CommunityTotals(
    points: friends + ideas + couples + engagements,
    activeMatchmakers: active,
    friends: friends,
    ideas: ideas,
    couples: couples,
    engagements: engagements,
  );
}

void main() {
  group('The weekly community challenge', () {
    test('picks the same metric for everybody in the same week', () {
      // The whole feature depends on this: two devices reading the same week
      // key must show the same challenge, with no coordination at all.
      const String week = 'W2026-08-16';
      expect(
        CommunityChallenge.metricFor(week),
        CommunityChallenge.metricFor(week),
      );
    });

    test('changes from week to week', () {
      final Set<ChallengeMetric> seen = <ChallengeMetric>{
        for (final String week in <String>[
          'W2026-08-02',
          'W2026-08-09',
          'W2026-08-16',
          'W2026-08-23',
          'W2026-08-30',
          'W2026-09-06',
        ])
          CommunityChallenge.metricFor(week),
      };
      expect(seen.length, greaterThan(1));
    });

    test('aims above last week and rounds to something sayable', () {
      // 128 raised by a tenth is 141, which nobody would say out loud.
      expect(CommunityChallenge.targetFor(ChallengeMetric.ideas, 128), 150);
      expect(CommunityChallenge.targetFor(ChallengeMetric.couples, 12), 15);
      // Always at least one above the record, even when a tenth rounds to
      // nothing.
      expect(
        CommunityChallenge.targetFor(ChallengeMetric.couples, 4),
        greaterThan(4),
      );
    });

    test('falls back to the opening target with no record to beat', () {
      expect(
        CommunityChallenge.targetFor(ChallengeMetric.ideas, null),
        ChallengeMetric.ideas.openingTarget,
      );
      expect(
        CommunityChallenge.targetFor(ChallengeMetric.friends, 0),
        ChallengeMetric.friends.openingTarget,
      );
    });

    test('says what last week reached, and that it was beaten', () {
      const CommunityWeekSnapshot last = CommunityWeekSnapshot(
        weekKey: 'W2026-08-09',
        friends: 40,
        ideas: 80,
        couples: 6,
      );
      final CommunityChallenge behind = CommunityChallenge(
        metric: ChallengeMetric.ideas,
        target: 90,
        current: 20,
        record: last.ideas,
      );
      expect(behind.subline, contains('בשבוע שעבר הגענו ל־80'));
      expect(behind.beatsRecord, isFalse);
      expect(behind.progress, closeTo(20 / 90, 0.001));

      final CommunityChallenge ahead = CommunityChallenge(
        metric: ChallengeMetric.ideas,
        target: 90,
        current: 95,
        record: last.ideas,
      );
      expect(ahead.beatsRecord, isTrue);
      expect(ahead.reachedTarget, isTrue);
      // A bar cannot be more than full.
      expect(ahead.progress, 1);
      expect(ahead.subline, contains('שברנו את השיא'));
    });

    test('claims no record when this device never saw last week', () {
      final CommunityChallenge challenge = CommunityChallenge.build(
        weekKey: 'W2026-08-16',
        week: _totals(friends: 12, ideas: 9, couples: 2),
      );
      expect(challenge.record, isNull);
      expect(challenge.subline, isNot(contains('בשבוע שעבר')));
      expect(challenge.headline, contains('${challenge.target}'));
    });
  });

  group('The home banner lines', () {
    test('lead with the engagement, then today, then the week', () {
      final List<String> lines = CommunityHighlight.pulseLines(
        day: _totals(ideas: 18, friends: 4, active: 7),
        week: _totals(ideas: 40, friends: 30, couples: 6, engagements: 1),
      );
      expect(lines.first, 'מזל טוב! זוג נוסף התארס 🎉');
      expect(lines, contains('18 רעיונות נפתחו היום'));
      expect(lines, contains('6 זוגות התחילו לצאת השבוע'));
      // The week's ideas are not repeated when today already has some.
      expect(lines, isNot(contains('40 רעיונות נפתחו השבוע')));
    });

    test('say nothing at all about a community that did nothing', () {
      expect(
        CommunityHighlight.pulseLines(day: _totals(), week: _totals()),
        isEmpty,
      );
    });
  });

  group('Community milestones', () {
    test('are never announced from an unresolved read', () {
      expect(
        CommunityMilestones.firstUnseen(
          allTime: CommunityTotals.empty,
          seen: <String>{},
        ),
        isNull,
      );
    });

    test('put the couples ahead of any count of records', () {
      final CommunityMilestone? milestone = CommunityMilestones.firstUnseen(
        allTime: _totals(friends: 9000, ideas: 3000, couples: 120),
        seen: <String>{},
      );
      expect(milestone?.id, 'community.couples.100');
    });

    test('move on to the next thing once one has been shown', () {
      final CommunityMilestone? milestone = CommunityMilestones.firstUnseen(
        allTime: _totals(friends: 9000, ideas: 3000, couples: 120),
        seen: <String>{'community.couples.100'},
      );
      expect(milestone?.id, 'community.ideas.2500');
      expect(milestone?.title, contains('2,500'));
    });

    test('list everything reached, for the silent first pass', () {
      expect(
        CommunityMilestones.reachedIds(
          _totals(friends: 9000, ideas: 3000, couples: 120, engagements: 30),
        ),
        <String>[
          'community.couples.100',
          'community.engagements.25',
          'community.ideas.2500',
          'community.friends.5000',
        ],
      );
    });
  });

  group('The remembered community week', () {
    test('round-trips through its string form', () {
      const CommunityWeekSnapshot snapshot = CommunityWeekSnapshot(
        weekKey: 'W2026-08-16',
        friends: 30,
        ideas: 80,
        couples: 6,
      );
      final CommunityWeekSnapshot? back = CommunityWeekSnapshot.decode(
        snapshot.encode(),
      );
      expect(back?.weekKey, 'W2026-08-16');
      expect(back?.friends, 30);
      expect(back?.ideas, 80);
      expect(back?.couples, 6);
    });

    test('reads anything that is not one of ours as nothing', () {
      expect(CommunityWeekSnapshot.decode(null), isNull);
      expect(CommunityWeekSnapshot.decode('W2026-08-16|30|80'), isNull);
      expect(CommunityWeekSnapshot.decode('W2026-08-16|30|x|6'), isNull);
      expect(CommunityWeekSnapshot.decode(42), isNull);
    });
  });
}
