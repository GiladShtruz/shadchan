import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/home_board.dart';

int? tier({
  bool dueReminder = false,
  bool isIdea = false,
  bool ideaStale = false,
  bool isPair = false,
  bool isCardFriendWithoutIdea = false,
}) => HomeBoardSection.actionTier(
  dueReminder: dueReminder,
  isIdea: isIdea,
  ideaStale: ideaStale,
  isPair: isPair,
  isCardFriendWithoutIdea: isCardFriendWithoutIdea,
);

void main() {
  test('the order of "הפעולה הבאה שלך": due → open idea → stale idea → '
      'database suggestion → (secondary) a card friend with no idea yet', () {
    final List<int?> order = <int?>[
      tier(dueReminder: true, isIdea: true),
      tier(isIdea: true),
      tier(isIdea: true, ideaStale: true),
      tier(isPair: true),
      tier(isCardFriendWithoutIdea: true),
    ];
    expect(order, <int>[0, 1, 2, 3, 4]);
    // A due reminder outranks the idea being stale.
    expect(tier(dueReminder: true, isIdea: true, ideaStale: true), 0);
  });

  test('nothing without a clear action is on the list', () {
    // A friend with a card, a notice or a pin: not "the next action".
    expect(tier(), isNull);
  });
}
