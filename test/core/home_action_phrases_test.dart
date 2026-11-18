import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_action_phrases.dart';
import 'package:shadchan/utils/match_stage.dart';

Person _p(String first, Gender gender) {
  final DateTime now = DateTime(2026, 11, 18);
  return Person(
    id: first,
    firstName: first,
    lastName: 'כהן',
    gender: gender,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final Person yossi = _p('יוסי', Gender.male);
  final Person noa = _p('נועה', Gender.female);

  test('an open idea says whom to ask, and what about', () {
    expect(
      HomeActionPhrases.ideaStep(
        MatchNextStep.askMale,
        male: yossi,
        female: noa,
      ),
      'לשאול את יוסי מה הוא חושב על נועה',
    );
    expect(
      HomeActionPhrases.ideaStep(
        MatchNextStep.askFemale,
        male: yossi,
        female: noa,
      ),
      'לשאול את נועה מה היא חושבת על יוסי',
    );
  });

  test('a couple going out: the check-in', () {
    expect(
      HomeActionPhrases.ideaReminder(
        status: MatchStatus.dating,
        male: yossi,
        female: noa,
      ),
      'לשאול את יוסי אם מתאים לו להמשיך עם נועה',
    );
  });

  test('the database\'s pair, the woman first', () {
    expect(
      HomeActionPhrases.pair(
        male: _p('איתמר', Gender.male),
        female: _p('יעל', Gender.female),
      ),
      'רעיון מהמאגר: יעל ואיתמר – מה דעתך?',
    );
  });

  test('a friend with a card, in their own gender', () {
    expect(
      HomeActionPhrases.cardFriend(noa),
      'נועה הוסיפה כרטיס אישי – לחשוב לה על רעיון',
    );
    expect(
      HomeActionPhrases.personReminder(yossi),
      'לבדוק שוב עם יוסי מה חדש אצלו',
    );
  });

  test('no sentence ever carries an ellipsis', () {
    for (final String line in <String>[
      HomeActionPhrases.ideaStep(
        MatchNextStep.startDating,
        male: yossi,
        female: noa,
      ),
      HomeActionPhrases.pair(male: yossi, female: noa),
      HomeActionPhrases.cardFriend(yossi),
    ]) {
      expect(line, isNot(contains('…')));
      expect(line, isNot(contains('...')));
    }
  });
}
