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

  /// The status as the card says it, named for what is being *waited for*
  /// rather than for what was done.
  ///
  /// **"שאלתי את הבחור" was a report; "מחכים לתשובת הבחור" is the state.** The
  /// difference matters on a list: a matchmaker running down forty proposals
  /// is looking for the ones that are stuck, and what tells them that is whose
  /// answer has not come — not which call was made last week.
  String get label {
    switch (this) {
      case MatchStage.newIdea:
        return 'רעיון חדש';
      case MatchStage.askedMale:
        return 'מחכים לתשובת הבחור';
      case MatchStage.askedFemale:
        return 'מחכים לתשובת הבחורה';
      case MatchStage.askedBoth:
        return 'בבדיקה';
      case MatchStage.dating:
        return 'מתחילים לצאת';
    }
  }

  /// Whether the matchmaker may set this status by hand from the menu beside
  /// the button.
  ///
  /// Four of the five, and the menu is deliberately both ways: the app advances
  /// the status on its own when the action is taken through it, but plenty of
  /// matchmaking happens on a phone call the app never sees, and a status that
  /// can only move forwards is one that goes wrong and stays wrong. That is
  /// also what puts right a "מתחילים לצאת" tapped by mistake.
  ///
  /// "רעיון חדש" is the one that is not offered: it is where every proposal
  /// starts and it is not a state anybody moves a proposal *to*.
  bool get isSelectable => this != MatchStage.newIdea;

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
  ///
  /// **Only the two asking steps are a button at all.** Once both sides have
  /// been asked there is nothing left for the app to do on the matchmaker's
  /// behalf — the answer is what is being waited for — so the panel says
  /// [bothAskedLabel] instead and leaves the three status moves underneath to
  /// carry whatever comes back. See `_CardActionBar`.
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
        return bothAskedLabel;
    }
  }

  /// The same step, in as few words as a board note can hold.
  ///
  /// **The step itself is not decided here.** This is [nextStep]'s answer said
  /// shorter — the ideas page's own button is [buttonLabel] and stays exactly
  /// as it is. A note on הלוח שלי is a third of a phone wide and already
  /// carrying two faces and two names, so "יאללה לקדם — לשאול את יוסי" would be
  /// cut off before it reached the name, which is the only part of it that says
  /// anything. Naming the row is what the shorter form spends its words on
  /// instead.
  static String shortLabel(MatchNextStep step, {Person? male, Person? female}) {
    switch (step) {
      case MatchNextStep.askMale:
        return 'השלב הבא: לשאול את ${_firstName(male, 'הבחור')}';
      case MatchNextStep.askFemale:
        return 'השלב הבא: לשאול את ${_firstName(female, 'הבחורה')}';
      case MatchNextStep.startDating:
        // Both have been asked; there is nothing for the matchmaker to do next
        // except hear back. See [bothAskedLabel].
        return 'השלב הבא: מחכים לתשובה';
    }
  }

  /// What the panel says once both sides know about it.
  ///
  /// A statement, not a prompt. "יאללה לקדם — מתחילים לצאת" asked the
  /// matchmaker to press a button on somebody else's decision; what is
  /// actually true at this point is that both of them have been asked, and
  /// "מתחילים לצאת" is one of the three status tiles below like every other
  /// answer that could come back.
  static const String bothAskedLabel = 'שאלתי את שניהם';

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
