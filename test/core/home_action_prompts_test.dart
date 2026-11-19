import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_action_prompts.dart';
import 'package:shadchan/utils/match_stage.dart';

void main() {
  test('each prompt only when it has something to say', () {
    final List<HomeActionPrompt> all = HomeActionPrompts.build(
      hasPhoto: false,
      hasAbout: false,
      friendsWithoutCard: 12,
      cardFriendsToAsk: 3,
      connectedMatchmakers: 0,
      hasFriends: true,
      gender: Gender.female,
    );
    expect(all.map((HomeActionPrompt p) => p.title), <String>[
      '3 חברים שלך מנהלים כרטיס אישי · בקשי גישה',
      'הוסיפי תמונת פרופיל',
      '12 חברים שלך עדיין בלי כרטיס אישי · הזמיני אותם',
      'התחברי לשדכנים נוספים ובקשי גישה למאגרים שלהם',
      'כתבי משפט קצר עליך',
    ]);
    expect(
      HomeActionPrompts.build(
        hasPhoto: true,
        hasAbout: true,
        friendsWithoutCard: 0,
        cardFriendsToAsk: 0,
        connectedMatchmakers: 8,
        hasFriends: true,
      ),
      isEmpty,
    );
  });

  test('prompts are mixed in from the third place, every third', () {
    expect(HomeActionPrompts.positions(10, 3), <int>[2, 5, 8]);
    // With fewer rows they follow what there is.
    expect(HomeActionPrompts.positions(1, 2), <int>[1, 2]);
    expect(HomeActionPrompts.positions(0, 2), <int>[0, 1]);
  });

  test('a short, one-line staleness phrase', () {
    expect(MatchStaleness.quietFor(7), 'שבוע');
    expect(MatchStaleness.quietFor(15), 'שבועיים');
    expect(MatchStaleness.quietFor(21), '3 שבועות');
    expect(MatchStaleness.quietFor(31), 'חודש');
    expect(MatchStaleness.quietFor(62), 'חודשיים');
    expect(MatchStaleness.quietFor(95), '3 חודשים');
  });
}
