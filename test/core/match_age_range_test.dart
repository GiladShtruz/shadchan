import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// The default age window a friend's matches filter opens on, from either side.
void main() {
  // The window spans the youngest to the oldest man whose own window includes
  // her. It is an envelope, not a list: at the tier boundaries (30 and 40) the
  // men's rule has a one-year seam — a woman of 24 fits men of 23–29 and 31 but
  // not 30 — and a slider range cannot have a hole in it.
  test(
    'a woman\'s window runs from the youngest to the oldest man who fits',
    () {
      bool fits(int female, int male) {
        final ({int minAge, int maxAge})? women =
            MatchSuggestionUtils.femaleAgeRangeForMale(male);
        return women != null &&
            female >= women.minAge &&
            female <= women.maxAge;
      }

      for (final int female in <int>[20, 24, 29, 35, 42]) {
        final ({int minAge, int maxAge})? men =
            MatchSuggestionUtils.maleAgeRangeForFemale(female);
        expect(men, isNotNull, reason: '$female');
        // Both ends are real matches...
        expect(fits(female, men!.minAge), isTrue, reason: 'woman $female, min');
        expect(fits(female, men.maxAge), isTrue, reason: 'woman $female, max');
        // ...and nobody just outside them is.
        expect(fits(female, men.minAge - 1), isFalse, reason: '$female, below');
        expect(fits(female, men.maxAge + 1), isFalse, reason: '$female, above');
      }
    },
  );

  test('no age, no default window', () {
    expect(MatchSuggestionUtils.maleAgeRangeForFemale(null), isNull);
  });
}
