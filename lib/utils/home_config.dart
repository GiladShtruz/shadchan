/// The tuning knobs of the home screen, kept out of the widgets so the layout
/// can be adjusted without touching the design code.
abstract final class HomeConfig {
  /// How many items the recent-activity strip keeps. The board itself is
  /// intentionally unlimited and remains a horizontally scrolling surface.
  static const int recentActivityMaxItems = 25;

  /// How many cards each of the computed rows offers before the user has to
  /// open the full screen.
  ///
  /// "רעיונות פתוחים" is deliberately not on this list: it carries every open
  /// proposal, because it is the home screen's answer to "what is open right
  /// now" and a truncated answer to that is a wrong one.
  static const int worthThinkingCount = 12;
  static const int datingCouplesInRow = 15;
  static const int recentActionsInRow = 12;

  /// "רעיונות שהמאגר מציע לך" only appears above this many friends.
  ///
  /// Below it the pair scan finds a handful at best and then nothing, so the
  /// block would be a promise the database cannot keep — and the screen has
  /// better things to say to a small database, all of which are about growing
  /// it. Above it there is always something to offer.
  static const int databaseIdeasMinFriends = 50;

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

  /// "הפעולות האחרונות שלך": the maximum phone-width strip card. Height is
  /// content-driven.
  static const double activityCardWidth = 186;

  /// "רעיונות פתוחים": maximum width; narrow screens calculate a smaller
  /// width that leaves two whole cards plus a deliberate next-card peek.
  static const double ideaCardWidth = 190;

  /// "חברים ששווה לחשוב עליהם": maximum bubble width. Height follows text.
  static const double suggestionBubbleWidth = 128;

  /// The breathing room the wave row keeps above and below the circles.
  static const double suggestionRowPadding = 8;

  /// Side padding of a carousel. Narrow enough that the next card always peeks
  /// in from the edge, which is what tells the user the row scrolls.
  static const double carouselPadding = 14;
  static const double cardGap = 10;
}
