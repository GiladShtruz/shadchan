import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/screens/stat_detail_screen.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/monthly_stats.dart';

/// The sentence at the top of "זוגות שיצאו" and "חתונות": beside the figure,
/// so it never repeats it; and with nothing to count, warm rather than a zero.
void main() {
  test('one couple is written in the singular, without the number', () {
    expect(
      coupleEncouragement(MonthlyStatMetric.dating, 1),
      'זוג יצא לדייט בזכותך! '
      'כל הכבוד שהיית עבורם חלק משמעותי במסע אל החתונה.',
    );
  });

  test('the number is never repeated in the sentence', () {
    expect(
      coupleEncouragement(MonthlyStatMetric.dating, 4),
      isNot(contains('4')),
    );
    expect(
      coupleEncouragement(MonthlyStatMetric.weddings, 3),
      isNot(contains('3')),
    );
  });

  test('weddings have their own congratulation', () {
    expect(
      coupleEncouragement(MonthlyStatMetric.weddings, 2),
      contains('מזל טוב'),
    );
  });

  test('zero speaks of the community when its figure is known', () {
    expect(
      coupleZeroLine(
        MonthlyStatMetric.dating,
        community: 37,
        gender: Gender.female,
      ),
      'את חלק מקהילה שהוציאה 37 זוגות לדייט. ממשיכים לנסות, בשביל החברים.',
    );
    expect(
      coupleZeroLine(MonthlyStatMetric.weddings, community: 5),
      contains('5 חתונות'),
    );
  });

  test('zero without a community figure is still encouraging', () {
    for (final MonthlyStatMetric metric in <MonthlyStatMetric>[
      MonthlyStatMetric.dating,
      MonthlyStatMetric.weddings,
    ]) {
      final String line = coupleZeroLine(metric);
      expect(line, contains('ממשיכים לנסות'));
      expect(line, isNot(contains('0')));
    }
  });
}
