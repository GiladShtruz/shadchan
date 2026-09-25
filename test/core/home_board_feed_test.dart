import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/home_board_feed.dart';
import 'package:shadchan/utils/invisible_marks.dart';

void main() {
  group('HomeBoardFeed.mix', () {
    Map<BoardFeedKind, List<String>> queues() => <BoardFeedKind, List<String>>{
      BoardFeedKind.freshReminder: <String>['r1', 'r2', 'r3'],
      BoardFeedKind.openIdea: <String>['i1', 'i2', 'i3'],
      BoardFeedKind.pinned: <String>['p1'],
      BoardFeedKind.oldReminder: <String>['o1'],
    };

    test('keeps every item, and each kind in its own order', () {
      for (int seed = 0; seed < 50; seed++) {
        final List<BoardFeedItem<String>> out = HomeBoardFeed.mix(
          queues(),
          seed: seed,
        );
        expect(out, hasLength(8));
        for (final BoardFeedKind kind in BoardFeedKind.values) {
          expect(
            out.where((e) => e.kind == kind).map((e) => e.value).toList(),
            queues()[kind] ?? <String>[],
          );
        }
      }
    });

    test('a fresh reminder leads, and no kind repeats while others remain', () {
      for (int seed = 0; seed < 50; seed++) {
        final List<BoardFeedItem<String>> out = HomeBoardFeed.mix(
          queues(),
          seed: seed,
        );
        expect(out.first.value, 'r1');
        for (int i = 1; i < out.length; i++) {
          if (out[i].kind == out[i - 1].kind) {
            // Allowed only once every other kind has run out.
            final Set<BoardFeedKind> left = out
                .sublist(i)
                .map((e) => e.kind)
                .toSet();
            expect(left, <BoardFeedKind>{out[i].kind});
          }
        }
      }
    });

    test('the seed varies how kinds meet', () {
      final Set<String> orders = <String>{
        for (int seed = 0; seed < 40; seed++)
          HomeBoardFeed.mix(queues(), seed: seed).map((e) => e.value).join(),
      };
      expect(orders.length, greaterThan(1));
    });

    test('fillers come after the matchmaker\'s own work', () {
      final List<BoardFeedItem<String>> out = HomeBoardFeed.mix(
        <BoardFeedKind, List<String>>{
          BoardFeedKind.openIdea: <String>['i1', 'i2'],
          BoardFeedKind.suggestedIdea: <String>['s1'],
          BoardFeedKind.thinkAbout: <String>['t1'],
        },
        seed: 3,
      );
      expect(out.first.value, 'i1');
      expect(out.map((e) => e.value), containsAll(<String>['s1', 't1']));
    });
  });

  test('splitFillers alternates and respects the room', () {
    final (List<int>, List<String>) split = HomeBoardFeed.splitFillers(
      <int>[1, 2, 3],
      <String>['a', 'b'],
      4,
    );
    expect(split.$1, <int>[1, 2]);
    expect(split.$2, <String>['a', 'b']);
    expect(HomeBoardFeed.fillerRoom(12), 0);
    expect(HomeBoardFeed.fillerRoom(3), 7);
  });

  group('InvisibleMarks', () {
    test('strips direction marks but keeps emoji joiners', () {
      expect(InvisibleMarks.strip('\u200Fשלום\u200E.'), 'שלום.');
      expect(InvisibleMarks.strip('👨\u200D👩'), '👨\u200D👩');
    });

    test('the formatter keeps the caret on the same character', () {
      const InvisibleMarksFormatter formatter = InvisibleMarksFormatter();
      final TextEditingValue out = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'א\u200Fב\u200Fג',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(out.text, 'אבג');
      expect(out.selection.baseOffset, 2);
    });
  });
}
