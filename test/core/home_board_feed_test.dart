import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/home_board_feed.dart';
import 'package:shadchan/utils/invisible_marks.dart';

void main() {
  group('HomeBoardFeed.arrange', () {
    final DateTime now = DateTime(2026, 10, 5, 12);

    BoardFeedEntry<String> e(
      String id,
      BoardCategory category,
      BoardPriority priority,
      Duration ago, {
      Set<BoardCategory> alsoIn = const <BoardCategory>{},
    }) => BoardFeedEntry<String>(
      value: id,
      category: category,
      priority: priority,
      activityAt: now.subtract(ago),
      alsoIn: alsoIn,
    );

    List<String> ids(Iterable<BoardFeedEntry<String>> out) =>
        out.map((BoardFeedEntry<String> x) => x.value).toList();

    test('newer activity first, whatever the category', () {
      final List<BoardFeedEntry<String>> out =
          HomeBoardFeed.arrange(<BoardFeedEntry<String>>[
            e(
              'old-alert',
              BoardCategory.alerts,
              BoardPriority.alert,
              const Duration(days: 10),
            ),
            e(
              'fresh-idea',
              BoardCategory.openIdeas,
              BoardPriority.openIdea,
              const Duration(hours: 2),
            ),
          ], now: now);
      expect(ids(out), <String>['fresh-idea', 'old-alert']);
    });

    test('close in time, the more pressing goes first', () {
      final List<BoardFeedEntry<String>> out =
          HomeBoardFeed.arrange(<BoardFeedEntry<String>>[
            e(
              'suggestion',
              BoardCategory.suggestions,
              BoardPriority.suggestion,
              const Duration(hours: 1),
            ),
            e(
              'idea',
              BoardCategory.openIdeas,
              BoardPriority.openIdea,
              const Duration(hours: 2),
            ),
            e(
              'card',
              BoardCategory.cards,
              BoardPriority.cardChange,
              const Duration(hours: 3),
            ),
            e(
              'reminder',
              BoardCategory.alerts,
              BoardPriority.alert,
              const Duration(hours: 4),
            ),
            e(
              'ask',
              BoardCategory.cards,
              BoardPriority.action,
              const Duration(hours: 5),
            ),
          ], now: now);
      expect(ids(out), <String>[
        'ask',
        'reminder',
        'card',
        'idea',
        'suggestion',
      ]);
    });

    test('a flood of one kind does not bury the rest', () {
      final List<BoardFeedEntry<String>> out =
          HomeBoardFeed.arrange(<BoardFeedEntry<String>>[
            for (int i = 0; i < 8; i++)
              e(
                'card$i',
                BoardCategory.cards,
                BoardPriority.cardChange,
                Duration(minutes: i),
              ),
            e(
              'idea',
              BoardCategory.openIdeas,
              BoardPriority.openIdea,
              const Duration(days: 4),
            ),
            e(
              'reminder',
              BoardCategory.alerts,
              BoardPriority.alert,
              const Duration(days: 12),
            ),
          ], now: now);
      expect(out, hasLength(10));
      expect(ids(out).indexOf('idea'), 2);
      expect(ids(out).indexOf('reminder'), 5);
      // Never more than two of one shelf in a row while another is left.
      for (int i = 2; i < 6; i++) {
        expect(
          out[i].category == out[i - 1].category &&
              out[i - 1].category == out[i - 2].category,
          isFalse,
        );
      }
    });

    test('suggestions break a run only when nothing else can', () {
      final List<BoardFeedEntry<String>> out =
          HomeBoardFeed.arrange(<BoardFeedEntry<String>>[
            for (int i = 0; i < 4; i++)
              e(
                'alert$i',
                BoardCategory.alerts,
                BoardPriority.alert,
                Duration(minutes: i),
              ),
            e(
              'pair',
              BoardCategory.suggestions,
              BoardPriority.suggestion,
              const Duration(days: 40),
            ),
            e(
              'idea',
              BoardCategory.openIdeas,
              BoardPriority.openIdea,
              const Duration(days: 20),
            ),
          ], now: now);
      expect(ids(out), <String>[
        'alert0',
        'alert1',
        'idea',
        'alert2',
        'alert3',
        'pair',
      ]);
    });

    test('a chip shows its own shelf; "הכל" only the shelves switched on', () {
      final List<BoardFeedEntry<String>> arranged = HomeBoardFeed.arrange(
        <BoardFeedEntry<String>>[
          e(
            'due-idea',
            BoardCategory.alerts,
            BoardPriority.alert,
            const Duration(hours: 1),
            alsoIn: const <BoardCategory>{BoardCategory.openIdeas},
          ),
          e(
            'idea',
            BoardCategory.openIdeas,
            BoardPriority.openIdea,
            const Duration(hours: 2),
          ),
          e(
            'pair',
            BoardCategory.suggestions,
            BoardPriority.suggestion,
            const Duration(hours: 3),
          ),
        ],
        now: now,
      );
      expect(
        ids(
          HomeBoardFeed.forChip(
            arranged,
            BoardCategory.openIdeas,
            inAll: const <BoardCategory>{},
          ),
        ),
        <String>['due-idea', 'idea'],
      );
      expect(
        ids(
          HomeBoardFeed.forChip(
            arranged,
            BoardCategory.all,
            inAll: const <BoardCategory>{BoardCategory.openIdeas},
          ),
        ),
        <String>['due-idea', 'idea'],
      );
      // Switched off in "הכל", a shelf is still all there on its own chip.
      expect(
        ids(
          HomeBoardFeed.forChip(
            arranged,
            BoardCategory.suggestions,
            inAll: const <BoardCategory>{BoardCategory.openIdeas},
          ),
        ),
        <String>['pair'],
      );
    });
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
