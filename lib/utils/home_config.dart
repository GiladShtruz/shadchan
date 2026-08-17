/// The tuning knobs of the home screen, kept out of the widgets so the layout
/// can be adjusted without touching the design code.
abstract final class HomeConfig {
  /// How many items the recent-activity strip keeps. The board itself is
  /// intentionally unlimited and remains a horizontally scrolling surface.
  static const int recentActivityMaxItems = 25;

  /// How many cards each of the computed rows offers before the user has to
  /// open the full screen.
  static const int openIdeasInRow = 15;
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

  /// "הלוח שלי": a paper note — the pin at the top, avatars and text centred
  /// under it, and the actions button along the bottom edge.
  ///
  /// Both are *fixed*. The board is one row however many notes are on it, so
  /// its height must not depend on the longest note's text — a board that grows
  /// taller as it fills is the thing the redesign set out to remove.
  /// Both are *fixed* at the base text size and scale together with the system
  /// font — never with the content. Two notes are always the same box; a longer
  /// note is clamped, not taller.
  static const double cardWidth = 152;
  static const double cardHeight = 190;

  /// The cork surface's own padding above and below the notes. The top figure
  /// is what guarantees the drawing pin is never clipped.
  static const double boardPaddingTop = 16;
  static const double boardPaddingBottom = 14;

  /// "הפעולות הבאות שלך": every card is exactly this box, whatever its text
  /// says.
  ///
  /// The row scrolls horizontally rather than paging three at a time, so the
  /// card is sized to be *compact* — the point of the row is to run an eye over
  /// many actions quickly, and a card tall enough for the longest reason in the
  /// database makes every other card mostly empty. The reason line is clamped
  /// to fit this box; it never sets it.
  /// The height is measured from what a card actually holds — one mark, one
  /// clamped title line and two clamped reason lines — rather than rounded up
  /// to something comfortable. At 136 the box stood a third taller than its own
  /// contents, so every card in the row carried a band of empty white.
  static const double nextActionCardWidth = 150;
  static const double nextActionCardHeight = 110;

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
