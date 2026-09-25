import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';

/// The four all-time figures, in the order they are drawn.
enum MetricKind { friends, ideas, couples, weddings }

abstract final class AppColors {
  static const Color primary = Color(0xFF7F9EAA);
  static const Color primaryLight = Color(0xFFD7E4EA);
  static const Color primaryDark = Color(0xFF5F7F8C);
  static const Color secondary = Color(0xFFC1845B);
  static const Color secondaryLight = Color(0xFFEFE4D4);

  /// Deeper members of the two brand hues, for text and icons sitting on a
  /// light wash of their own colour — the brand tone itself is too pale there
  /// to stay readable.
  static const Color primaryInk = Color(0xFF3F5A66);
  static const Color secondaryInk = Color(0xFF8F5F3D);

  static const Color surface = Color(0xFFFFFDF8);
  static const Color background = Color(0xFFF7F0E4);
  static const Color onPrimary = Color(0xFFFFFDF8);
  static const Color onSecondary = Color(0xFF211D17);
  static const Color onSurface = Color(0xFF211D17);
  static const Color onSurfaceVariant = Color(0xFF7C7468);
  static const Color outline = Color(0xFFE2D7C8);
  static const Color error = Color(0xFFD32F2F);
  static const Color divider = Color(0xFFE2D7C8);

  static const Color statusIdea = primary;
  static const Color statusChecking = Color(0xFFB99A55);
  static const Color statusUnavailable = Color(0xFF948577);
  static const Color statusRejected = Color(0xFFA96B49);
  static const Color statusDating = Color(0xFF6F7A55);
  static const Color statusDated = Color(0xFF948577);
  static const Color statusMarried = Color(0xFF6F7A55);

  /// The one green the app means "done, together" by, lifted for the dark
  /// theme. Named here so no widget picks its own shade of it.
  static const Color statusDatingDm = Color(0xFF9DB07A);

  static const Color softBlue = Color(0xFFD7E4EA);
  static const Color softPink = Color(0xFFE6D4C0);
  static const Color softGreen = Color(0xFFDDE3CF);
  static const Color softPurple = Color(0xFFDDD7E7);
  static const Color softSand = Color(0xFFE6D4C0);
  static const Color softYellow = Color(0xFFEFE0B8);
  static const Color softRose = Color(0xFFEFDDE4);

  /// What the two home entry cards are drawn in: their line drawing and the
  /// rule along their bottom edge.
  ///
  /// They were a *band* once — a filled strip of colour carrying the label in
  /// [onPrimary] — and before that a pair of tones sampled off painted
  /// artwork, which left the home screen with a blue and a copper that were
  /// only nearly the brand's. The cards are white with a rule under them now,
  /// so all that is left is the accent itself, and it is simply the palette:
  /// the light brand blue for friends, the brand brown for an idea.
  ///
  /// The hand-drawn icons (`add_friends_art.png`, `add_idea_art.png`) arrived
  /// in inks of their own, a shade off the palette; they are now recoloured
  /// at draw time into these two (see `ArtTint`), so the drawing, the rule
  /// under it and the rest of the page share one blue and one copper.
  static const Color addPeopleAccent = primaryDark;
  static const Color addIdeaAccent = secondary;

  /// **The four figures — on the home page and on "פעילות" — one palette
  /// colour each, and the same four in both places.**
  ///
  /// Friends are the deep brand blue, ideas the copper, the couples who went
  /// out the palette's own light blue, and a wedding the rose. Every one of
  /// them is a member of the palette above; none is sampled from artwork or
  /// picked for the occasion, so the figures agree with the rest of the app
  /// instead of inventing a fifth convention.
  static const Color metricFriends = primaryDark;
  static const Color metricIdeas = secondary;
  static const Color metricCouples = primary;
  static const Color metricWeddings = femaleAccent;

  /// The same four in the dark theme.
  static const Color metricFriendsDm = primaryDarkDm;
  static const Color metricIdeasDm = secondaryDarkDm;
  static const Color metricCouplesDm = Color(0xFF8FB0BC);
  static const Color metricWeddingsDm = femaleAccentDm;

  /// The metric colour for [dark] or light, in one call.
  static Color metric(MetricKind kind, {bool dark = false}) {
    switch (kind) {
      case MetricKind.friends:
        return dark ? metricFriendsDm : metricFriends;
      case MetricKind.ideas:
        return dark ? metricIdeasDm : metricIdeas;
      case MetricKind.couples:
        return dark ? metricCouplesDm : metricCouples;
      case MetricKind.weddings:
        return dark ? metricWeddingsDm : metricWeddings;
    }
  }

  /// **The two inks the home page is written in.**
  ///
  /// One colour for everything that titles, names or counts, and one for
  /// everything that explains, dates or qualifies — decided here rather than
  /// card by card, because "the heading colour" drifting by a few points per
  /// block is what makes a page of calm cards read as five different pages.
  /// [HomeTypography] folds them onto Material's roles; a block only names one
  /// of these directly when it is not going through that fold.
  ///
  /// [headingInk] is the palette's deep blue, [primaryInk] — visibly the
  /// brand's blue, and still dark enough to read as body text on the cream.
  /// It is the colour of every name, heading and opening line in the app,
  /// the wordmark included; no other blue is used for text. [mutedInk] is a true neutral grey rather than the
  /// warm taupe of [onSurfaceVariant]: beside navy, the warm one reads as a
  /// third colour instead of as quieter text.
  static const Color headingInk = primaryInk;
  static const Color mutedInk = Color(0xFF5E5C58);
  static const Color headingInkDm = primaryDarkDm;
  static const Color mutedInkDm = onSurfaceVariantDm;

  static Color heading({bool dark = false}) => dark ? headingInkDm : headingInk;

  static Color muted({bool dark = false}) => dark ? mutedInkDm : mutedInk;

  /// Gentle pastel pairs used for the initials circles next to a contact's
  /// name. Each entry is a soft surface plus the ink that stays readable on it.
  static const List<({Color surface, Color ink})> initialsPastels =
      <({Color surface, Color ink})>[
        (surface: softRose, ink: femaleAccent),
        (surface: softBlue, ink: primaryDark),
        (surface: softGreen, ink: statusDating),
        (surface: softPurple, ink: Color(0xFF7A6E93)),
        (surface: softSand, ink: statusRejected),
        (surface: softYellow, ink: Color(0xFF8A7333)),
      ];

  /// Picks a stable pastel for [seed] so the same contact always keeps the same
  /// shade, however the list happens to be sorted.
  static ({Color surface, Color ink}) initialsPastel(String seed) {
    int hash = 0;
    for (final int unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return initialsPastels[hash % initialsPastels.length];
  }

  // **Dark mode is the palette at night, not black.** The neutrals are a deep
  // stone blue taken from [primary]'s own hue — the page reads as the same
  // app with the lights down — and the copper, the rose and the light blue
  // carry the warmth on top of it. Nothing is `#000`, and nothing is the cold
  // near-black slate the theme used to be.
  static const Color primaryDarkDm = Color(0xFFAFC7D0);
  static const Color primaryLightDarkDm = Color(0xFF294C57);
  static const Color secondaryDarkDm = Color(0xFFD6A17A);
  static const Color secondaryLightDarkDm = Color(0xFF33383A);
  static const Color backgroundDm = Color(0xFF1D262B);
  static const Color surfaceDm = Color(0xFF263239);
  static const Color onSurfaceDm = Color(0xFFEDE6DA);
  static const Color onSurfaceVariantDm = Color(0xFFA8A49C);
  static const Color outlineDm = Color(0xFF41525B);
  static const Color dividerDm = Color(0xFF33434B);

  /// Per-gender accents. Men keep the app's stone blue; women get a muted
  /// rose-mauve picked to sit next to the copper/cream palette rather than a
  /// saturated pink.
  static const Color maleAccent = primaryDark;
  static const Color maleSurface = softBlue;
  static const Color femaleAccent = Color(0xFFA9748A);
  static const Color femaleSurface = Color(0xFFEFDDE4);
  static const Color femaleAccentDm = Color(0xFFCFA3B5);

  static Color genderAccent(Gender gender, {bool dark = false}) {
    if (gender != Gender.female) {
      return dark ? primaryDarkDm : maleAccent;
    }
    return dark ? femaleAccentDm : femaleAccent;
  }

  /// Soft background tint for a person's row/card. Dark mode uses a low-alpha
  /// wash of the accent so the tint reads without lighting up the surface.
  static Color genderSurface(Gender gender, {bool dark = false}) {
    if (dark) {
      return genderAccent(gender, dark: true).withValues(alpha: 0.16);
    }
    return gender == Gender.female ? femaleSurface : maleSurface;
  }

  /// Marks a person as a favorite in the people list.
  static const Color favorite = Color(0xFFC2185B);

  static const Color profileAvailable = Color(0xFF3E8E5A);
  static const Color profileBusy = Color(0xFFC0392B);
  static const Color profileOnBreak = Color(0xFFB07D18);

  /// Quieter versions of the availability colours, drawn from the app's own
  /// warm palette instead of the traffic-light primaries. Used where the tag
  /// repeats down a long list and should read as a hint, not an alarm.
  static Color profileStatusSoftColor(ProfileStatus status) {
    switch (status) {
      case ProfileStatus.available:
        return statusDating;
      case ProfileStatus.busy:
        return statusRejected;
      case ProfileStatus.onBreak:
        return statusChecking;
      case ProfileStatus.mazelTov:
        return secondary;
    }
  }

  /// **The dot beside an availability tag.** Three states, three plain
  /// colours: free is green, on a break is the palette's brown, taken is red.
  ///
  /// It exists because the *word* beside it no longer carries the state — the
  /// tag is written in the person's own gender colour, blue for a man and rose
  /// for a woman, so that a list can be read as "who" before it is read as
  /// "what". The dot is what puts the state back, in the one form that is read
  /// without reading.
  static Color profileStatusDotColor(ProfileStatus status) {
    switch (status) {
      case ProfileStatus.available:
        return profileAvailable;
      case ProfileStatus.busy:
        return profileBusy;
      case ProfileStatus.onBreak:
        return secondary;
      case ProfileStatus.mazelTov:
        return secondary;
    }
  }

  /// Colour for a person's availability tag: green / red / amber.
  static Color profileStatusColor(ProfileStatus status) {
    switch (status) {
      case ProfileStatus.available:
        return profileAvailable;
      case ProfileStatus.busy:
        return profileBusy;
      case ProfileStatus.onBreak:
        return profileOnBreak;
      case ProfileStatus.mazelTov:
        return secondary;
    }
  }

  /// **The one colour a proposal's status is drawn in, everywhere.**
  ///
  /// Colour says where a proposal stands and nothing else: open is the
  /// palette's blue, waiting its brown, a couple who are out keep the copper
  /// they have always worn, and anything that is over is the quiet grey. The
  /// finer stored distinctions ("רעיון" / "בבדיקה", the stage inside an open
  /// idea) never change the colour — a heart that turned a different shade
  /// every time somebody was asked read as five kinds of thing.
  static Color matchState(MatchStatus status, {bool dark = false}) {
    switch (status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return dark ? primaryDarkDm : primaryDark;
      case MatchStatus.unavailable:
        return dark ? secondaryDarkDm : secondary;
      case MatchStatus.dating:
        return dark ? secondaryDarkDm : secondary;
      case MatchStatus.married:
        return dark ? statusDatingDm : statusMarried;
      case MatchStatus.rejected:
      case MatchStatus.dated:
        return muted(dark: dark);
    }
  }

  /// [matchState] by the status's stored name, for the callers that hold one.
  static Color statusColor(String status) {
    for (final MatchStatus value in MatchStatus.values) {
      if (value.name == status) {
        return matchState(value);
      }
    }
    return matchState(MatchStatus.idea);
  }
}
