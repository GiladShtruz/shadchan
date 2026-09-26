import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/screens/stat_detail_screen.dart';

/// The sentence at the top of "זוגות שיצאו" follows the count, and says one
/// couple in the singular.
void main() {
  test('one couple is written in the singular', () {
    expect(
      datingEncouragement(1),
      'זוג אחד יצא לדייט בזכותך! '
      'כל הכבוד שהיית עבורם חלק משמעותי במסע אל החתונה.',
    );
  });

  test('several couples carry their number', () {
    expect(
      datingEncouragement(4),
      startsWith('4 זוגות יצאו לדייט בזכותך!'),
    );
  });

  test('no couples is not a congratulation', () {
    expect(datingEncouragement(0), isNot(contains('כל הכבוד')));
  });
}
