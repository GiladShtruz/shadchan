import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/match_stage.dart';

/// The sentence each row of "הפעולה הבאה שלך" says — what to do, to whom,
/// in a few words, and always the whole sentence (the row wraps, it never
/// cuts a sentence with "…").
///
/// **A verb and a name, not a label.** "השלב הבא: לשאול את יוסי" read as a
/// status; "לשאול את יוסי מה הוא חושב על נועה" is the thing to do. Pure, so
/// every wording is tested.
abstract final class HomeActionPhrases {
  static String _first(Person? person, String fallback) {
    final String first = (person?.firstName ?? '').trim();
    if (first.isNotEmpty) return first;
    final String full = (person?.fullName ?? '').trim();
    return full.isNotEmpty ? full : fallback;
  }

  static Gender _g(Person? person) =>
      person?.gender == Gender.female ? Gender.female : Gender.male;

  /// An open idea, by the step it waits on.
  static String ideaStep(MatchNextStep step, {Person? male, Person? female}) {
    final String him = _first(male, 'הבחור');
    final String her = _first(female, 'הבחורה');
    switch (step) {
      case MatchNextStep.askMale:
        return 'לשאול את $him מה הוא חושב על $her';
      case MatchNextStep.askFemale:
        return 'לשאול את $her מה היא חושבת על $him';
      case MatchNextStep.startDating:
        return 'לבדוק עם $him ו$her אם מתאים להם להיפגש';
    }
  }

  /// A couple who are going out: the check-in.
  static String datingCheckIn({Person? male, Person? female}) {
    final String him = _first(male, 'הבחור');
    final String her = _first(female, 'הבחורה');
    return 'לשאול את $him אם מתאים לו להמשיך עם $her';
  }

  /// A reminder on an idea that came due, with nothing written on it.
  static String ideaReminder({
    required MatchStatus status,
    MatchNextStep? step,
    Person? male,
    Person? female,
  }) {
    if (status == MatchStatus.dating) {
      return datingCheckIn(male: male, female: female);
    }
    if (step != null) {
      return ideaStep(step, male: male, female: female);
    }
    return 'לבדוק מה קורה עם ${_first(male, 'הבחור')} '
        'ו${_first(female, 'הבחורה')}';
  }

  /// A reminder on a friend that came due, with nothing written on it.
  static String personReminder(Person person) =>
      'לבדוק שוב עם ${_first(person, 'החבר')} מה {חדש אצלו|חדש אצלה}'.forGender(
        _g(person),
      );

  /// A pair the database suggests — the woman first, as it is said aloud.
  static String pair({required Person male, required Person female}) =>
      'רעיון מהמאגר: ${_first(female, 'הבחורה')} ו${_first(male, 'הבחור')} '
      '– מה דעתך?';

  /// A friend whose personal card the matchmaker sees, with no idea yet.
  static String cardFriend(Person person) =>
      '${_first(person, 'החבר')} {הוסיף|הוסיפה} כרטיס אישי – '
              'לחשוב {לו|לה} על רעיון'
          .forGender(_g(person));
}
