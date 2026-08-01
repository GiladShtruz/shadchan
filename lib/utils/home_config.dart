/// The tuning knobs of the home screen, kept out of the widgets so the layout
/// can be adjusted without touching the design code.
abstract final class HomeConfig {
  /// Below this many people in the database, "הוסף חברים" is shown as one wide
  /// invitation card above "הוסף רעיון" — building the database is the only
  /// thing that matters yet. From this count up, the two actions sit side by
  /// side as a pair of differently weighted cards.
  static const int compactActionsFromPeopleCount = 8;

  /// How many items the board and the recent-activity strip keep.
  static const int boardMaxItems = 40;
  static const int recentActivityMaxItems = 25;

  /// How many cards each of the computed rows offers before the user has to
  /// open the full screen.
  static const int openIdeasInRow = 15;
  static const int worthThinkingCount = 12;
  static const int datingCouplesInRow = 15;
  static const int recentActionsInRow = 12;

  /// A person with no proposal opened for this long counts as someone the
  /// matchmaker has not thought about in a while.
  static const int notThoughtAboutAfterDays = 45;

  /// "Recently" for the added / updated hints on the suggestions row.
  static const int recentlyChangedWithinDays = 14;

  /// A card nobody has touched for this long is worth a second look.
  static const int cardNotUpdatedAfterDays = 120;

  /// Open proposals that have not moved for this long are "waiting for an
  /// update".
  static const int openIdeaStaleAfterDays = 21;

  /// How recently a proposal must have closed for "הרעיון האחרון נסגר" to still
  /// be the interesting thing about a person.
  static const int ideaClosedWithinDays = 45;

  /// "יש במאגר X אנשים שעשויים להתאים לו" is only worth saying from this many
  /// never-proposed candidates up — below it, it is noise rather than news.
  static const int matchesFoundMinCandidates = 3;

  /// Pairing every person against every other is O(n²), so the candidate count
  /// behind that line is skipped entirely on databases larger than this. The
  /// row simply falls back to its other reasons.
  static const int matchScanMaxPeople = 500;

  /// "הלוח שלי": a paper note — avatars centred, the name under them, and the
  /// actions button along the bottom. Taller than the other cards because it
  /// carries a note, a reminder and its own button.
  static const double cardWidth = 152;
  static const double cardHeight = 186;

  /// The frame the notes run inside, so the row reads as one pinned board.
  static const double boardFramePadding = 10;

  /// "הפעולות האחרונות שלך": a low, wide strip card. Tall enough for both of
  /// its lines to wrap onto a second row, so a long name or a long action is
  /// never cut — and every card in the strip keeps that same box whether it
  /// wrapped or not.
  static const double activityCardWidth = 186;
  static const double activityCardHeight = 88;

  /// "רעיונות פתוחים": a low, centred card — avatars, names, status.
  static const double ideaCardWidth = 142;
  static const double ideaCardHeight = 112;

  /// "חברים ששווה לחשוב עליהם": a free-standing circle with a name and one
  /// line of reasoning under it, on a soft wave rather than in a box.
  static const double suggestionBubbleWidth = 128;
  static const double suggestionBubbleHeight = 168;

  /// The breathing room the wave row keeps above and below the circles.
  static const double suggestionRowPadding = 8;

  /// Side padding of a carousel. Narrow enough that the next card always peeks
  /// in from the edge, which is what tells the user the row scrolls.
  static const double carouselPadding = 14;
  static const double cardGap = 10;
}
