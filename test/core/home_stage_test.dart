import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/home_stage.dart';

/// The rules that decide what the home screen shows.
///
/// These are asserted rather than left to the widget tree because the whole
/// design rests on them: a block drawn at the wrong stage is an empty box in
/// front of a new user, and a reproachful number is worse than no number.
void main() {
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
}
