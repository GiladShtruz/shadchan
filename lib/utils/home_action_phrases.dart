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

/// The action list's rows: who it is about first ("הודיה × אבי"), and under
/// it one short grey line of what to do ("לשאול את אבי מה דעתו"). Short
/// enough to fit one line on a narrow phone — never cut with "…".
abstract final class HomeActionLines {
  static String _first(Person? person, String fallback) =>
      HomeActionPhrases._first(person, fallback);

  /// "הודיה × אבי" — the woman first, as a couple is said aloud.
  static String couple({Person? male, Person? female}) =>
      '${_first(female, 'הבחורה')} × ${_first(male, 'הבחור')}';

  /// What to do next with an open idea, by where it stands.
  static String ideaNext(MatchStage stage, {Person? male, Person? female}) {
    final String him = _first(male, 'הבחור');
    final String her = _first(female, 'הבחורה');
    switch (stage) {
      case MatchStage.newIdea:
        return 'לשאול את $him מה דעתו';
      case MatchStage.askedMale:
        return 'מחכים לתשובה מ$him';
      case MatchStage.askedFemale:
        return 'מחכים לתשובה מ$her';
      case MatchStage.askedBoth:
        return 'מחכים לתשובה משניהם';
      case MatchStage.dating:
        return 'לשאול את $him אם להמשיך';
    }
  }

  /// "רעיון מהמאגר: נועה × איתמר".
  static String pair({required Person male, required Person female}) =>
      'רעיון מהמאגר: ${couple(male: male, female: female)}';

  /// "נראה מתאים? פתח רעיון".
  static String pairNext(Gender? matchmaker) =>
      'נראה מתאים? {פתח|פתחי} רעיון'.forGender(matchmaker);

  /// A friend reminder with no words of the matchmaker's own.
  static String personNext(Person person) =>
      'לבדוק מה {חדש אצלו|חדש אצלה}'.forGender(HomeActionPhrases._g(person));

  /// A friend whose personal card arrived, with no idea yet.
  static String cardFriendNext(Person person) =>
      '{הוסיף|הוסיפה} כרטיס אישי · לחשוב {לו|לה} על רעיון'.forGender(
        HomeActionPhrases._g(person),
      );
}
