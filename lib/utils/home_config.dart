/// The tuning knobs of the home screen, kept out of the widgets so the layout
/// can be adjusted without touching the design code.
abstract final class HomeConfig {
  /// Below this many people in the database, "הוסף חברים" is shown as one big
  /// invitation card — building the database is the only thing that matters
  /// yet. From this count up, both actions collapse into one compact row.
  static const int compactActionsFromPeopleCount = 8;

  /// How many items the board and the recent-activity strip keep.
  static const int boardMaxItems = 40;
  static const int recentActivityMaxItems = 25;

  /// How many cards each of the computed rows offers before the user has to
  /// open the full screen.
  static const int openIdeasInRow = 15;
  static const int worthThinkingCount = 12;
  static const int datingCouplesInRow = 15;

  /// A person with no proposal opened for this long counts as someone the
  /// matchmaker has not thought about in a while.
  static const int notThoughtAboutAfterDays = 45;

  /// "Recently" for the added / updated hints on the suggestions row.
  static const int recentlyChangedWithinDays = 14;

  /// Every home carousel uses the same card box, so the rows read as one
  /// system and as many cards as possible fit side by side.
  static const double cardWidth = 150;
  static const double cardHeight = 150;

  /// Side padding of a carousel. Narrow enough that the next card always peeks
  /// in from the edge, which is what tells the user the row scrolls.
  static const double carouselPadding = 14;
  static const double cardGap = 10;
}
