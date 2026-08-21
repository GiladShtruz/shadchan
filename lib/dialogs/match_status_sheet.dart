/// Why a proposal is waiting.
///
/// One list, shared by every place a proposal can be paused, because a reason
/// written in one place is read in another — two lists would drift and the same
/// pause would be worded two ways depending on where it was set.
///
/// They are all about one side being unavailable, which is what a pause
/// actually is. "מחכים לתשובה" was dropped: that is not a pause, it is the
/// ordinary state of an open proposal.
///
/// **This file used to hold `MatchStatusSheet` as well** — a bottom sheet
/// listing all seven stored statuses to pick from. It is gone with the proposal
/// screen it belonged to. A flat list of statuses asked the matchmaker to
/// translate what happened ("she said no") into a database value, and offered
/// moves that make no sense from where the proposal stood; the card's "פעולות"
/// panel offers only the moves actually available from the current status, in
/// the words of the act rather than the state. See
/// [MatchQuickAction.statusActionsFor].
library;

abstract final class MatchWaitingReasons {
  static const List<String> options = <String>[
    'הוא בהפסקה',
    'היא בהפסקה',
    'הוא תפוס',
    'היא תפוסה',
  ];

  /// Offered alongside the rest rather than above them: pausing a proposal
  /// never has to be justified.
  static const String noReason = 'בלי סיבה מיוחדת';
}
