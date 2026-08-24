import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// Where a proposal stands in the one process every proposal goes through, and
/// what the next thing to do about it is.
///
/// **This is what "יאללה לקדם" now knows.** The button used to be one prompt
/// with one wording, opening a sheet that asked the matchmaker who to message
/// — which is a question the app can answer itself. A proposal is opened, one
/// side is asked, the other side is asked, and then the two of them go out;
/// there is no branch in that until somebody says no. So the button reads the
/// stage, names the actual next step, and moves the proposal on when the step
/// is taken.
///
/// **The stage is derived, never stored.** It comes out of two dates on the
/// proposal ([MatchIdea.askedMaleAt], [MatchIdea.askedFemaleAt]) and its
/// [MatchStatus]. Storing it as a third field would have made three places able
/// to disagree about the same fact — a proposal marked "מתחילים לצאת" whose
/// status is still "רעיון" is a bug nobody could see and everybody would hit.
enum MatchStage {
  /// Nobody has been approached yet.
  newIdea,

  /// He has been asked; she has not.
  askedMale,

  /// She has been asked; he has not.
  askedFemale,

  /// Both sides know about it, and the answer is what is being waited for.
  askedBoth,

  /// They are out. The card stops offering the process and starts asking how
  /// it is going — see `DatingCheckIn`.
  dating;

  /// The stage as the card says it, in the matchmaker's own voice.
  String get label {
    switch (this) {
      case MatchStage.newIdea:
        return 'רעיון חדש';
      case MatchStage.askedMale:
        return 'שאלתי את הבחור';
      case MatchStage.askedFemale:
        return 'שאלתי את הבחורה';
      case MatchStage.askedBoth:
        return 'שאלתי את שניהם';
      case MatchStage.dating:
        return 'מתחילים לצאת';
    }
  }

  /// Whether the matchmaker may set this stage by hand from the little menu
  /// beside the button.
  ///
  /// All of them, deliberately. The app advances the stage on its own when the
  /// action is taken through it, but plenty of matchmaking happens on a phone
  /// call the app never sees, and a stage that can only move forwards through
  /// this one button is a stage that goes wrong and stays wrong.
  bool get isSelectable => true;

  static MatchStage of(MatchIdea match) {
    if (match.status == MatchStatus.dating) {
      return MatchStage.dating;
    }
    final bool him = match.askedMaleAt != null;
    final bool her = match.askedFemaleAt != null;
    if (him && her) {
      return MatchStage.askedBoth;
    }
    if (him) {
      return MatchStage.askedMale;
    }
    if (her) {
      return MatchStage.askedFemale;
    }
    return MatchStage.newIdea;
  }
}

/// The one thing the card's main button does next.
enum MatchNextStep {
  askMale,
  askFemale,
  startDating;

  /// Which side this step is about, or null for the step that is about both.
  Gender? get side {
    switch (this) {
      case MatchNextStep.askMale:
        return Gender.male;
      case MatchNextStep.askFemale:
        return Gender.female;
      case MatchNextStep.startDating:
        return null;
    }
  }
}

/// What the proposal's stage implies about the next move.
abstract final class MatchStages {
  /// The step the button offers, given where the proposal stands.
  ///
  /// **The boy is asked first by default.** That is the order most matchmakers
  /// work in, so it is what the button offers on a proposal nobody has touched
  /// — but it is only a default: [MatchStages.otherFirstStep] is what the card
  /// puts beside it, and the stage menu can set either side directly.
  ///
  /// Null for a proposal there is nothing to advance — closed, or a wedding.
  static MatchNextStep? nextStep(MatchIdea match) {
    if (match.status.isArchived) {
      return null;
    }
    switch (MatchStage.of(match)) {
      case MatchStage.newIdea:
        return MatchNextStep.askMale;
      case MatchStage.askedMale:
        return MatchNextStep.askFemale;
      case MatchStage.askedFemale:
        return MatchNextStep.askMale;
      case MatchStage.askedBoth:
        return MatchNextStep.startDating;
      case MatchStage.dating:
        return null;
    }
  }

  /// The other way round, offered quietly next to the main button while the
  /// proposal is brand new: "ניתן לפנות גם לבחורה קודם".
  ///
  /// Only on a new idea. Once one side has been asked there is no choice left
  /// to offer — the remaining side is the remaining side.
  static MatchNextStep? otherFirstStep(MatchIdea match) {
    return MatchStage.of(match) == MatchStage.newIdea &&
            !match.status.isArchived
        ? MatchNextStep.askFemale
        : null;
  }

  /// The words on the button, naming the person where there is a name.
  static String buttonLabel(
    MatchNextStep step, {
    Person? male,
    Person? female,
  }) {
    switch (step) {
      case MatchNextStep.askMale:
        return 'יאללה לקדם — לשאול את ${_firstName(male, 'הבחור')}';
      case MatchNextStep.askFemale:
        return 'יאללה לקדם — לשאול את ${_firstName(female, 'הבחורה')}';
      case MatchNextStep.startDating:
        return 'יאללה לקדם — מתחילים לצאת';
    }
  }

  /// The quiet line under the button: what pressing it actually does.
  static String buttonHint(MatchNextStep step) {
    switch (step) {
      case MatchNextStep.askMale:
      case MatchNextStep.askFemale:
        return 'פתיחת וואטסאפ עם הכרטיס של הצד השני';
      case MatchNextStep.startDating:
        return 'שני הצדדים ענו — לסמן שהם יוצאים';
    }
  }

  static String _firstName(Person? person, String fallback) {
    final String name = (person?.firstName ?? '').trim();
    return name.isEmpty ? fallback : name;
  }
}

/// How long a proposal has been left alone.
///
/// **A week with nothing happening is the one thing the list cannot show by
/// itself.** Ordering by date says which proposal is oldest, not which one is
/// stuck: a proposal opened in March and worked on yesterday is fine, and one
/// opened yesterday and forgotten since is not — and after a week those two
/// look identical on a card. So the promote area says it in words, on the
/// proposal it is true of, and **nothing about the ordering changes**: a nudge
/// that also reshuffles the list takes away the one thing a matchmaker relies
/// on, which is that the proposal they were looking at is still where it was.
abstract final class MatchStaleness {
  static const Duration after = Duration(days: 7);

  static bool isStale(MatchIdea match, {DateTime? now}) {
    if (match.status.isArchived) {
      return false;
    }
    return (now ?? DateTime.now()).difference(match.updatedAt) >= after;
  }

  /// "עבר שבוע בלי עדכון – שווה לקדם את הרעיון", or the same in months once it
  /// has been much longer than a week — a proposal untouched since May should
  /// not be told it has been a week.
  static String? nudge(MatchIdea match, {DateTime? now}) {
    if (!isStale(match, now: now)) {
      return null;
    }
    final int days = (now ?? DateTime.now()).difference(match.updatedAt).inDays;
    if (days >= 60) {
      return 'עברו ${days ~/ 30} חודשים בלי עדכון – שווה לקדם את הרעיון';
    }
    if (days >= 30) {
      return 'עבר חודש בלי עדכון – שווה לקדם את הרעיון';
    }
    if (days >= 14) {
      return 'עברו ${days ~/ 7} שבועות בלי עדכון – שווה לקדם את הרעיון';
    }
    return 'עבר שבוע בלי עדכון – שווה לקדם את הרעיון';
  }
}
