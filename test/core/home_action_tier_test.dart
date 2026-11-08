import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/home_board.dart';

int? tier({
  bool dueReminder = false,
  bool isIdea = false,
  bool ideaStale = false,
  bool isNotice = false,
  bool isCardFriend = false,
  bool cardHandled = false,
  bool isPair = false,
}) => HomeBoardSection.actionTier(
  dueReminder: dueReminder,
  isIdea: isIdea,
  ideaStale: ideaStale,
  isNotice: isNotice,
  isCardFriend: isCardFriend,
  cardHandled: cardHandled,
  isPair: isPair,
);

void main() {
  test('the order on the home list: due → open idea → card friend → '
      'stale idea → database suggestion', () {
    final List<int?> order = <int?>[
      tier(dueReminder: true, isIdea: true),
      tier(isIdea: true),
      tier(isCardFriend: true),
      tier(isIdea: true, ideaStale: true),
      tier(isPair: true),
    ];
    expect(order, <int>[0, 1, 2, 3, 4]);
    // An unread notice needs handling now, like a reminder.
    expect(tier(isNotice: true), 0);
    // A due reminder outranks the idea being stale.
    expect(tier(dueReminder: true, isIdea: true, ideaStale: true), 0);
  });

  test('a card already handled is nothing to do now', () {
    expect(tier(isCardFriend: true, cardHandled: true), isNull);
  });
}
