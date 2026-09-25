import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';

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
  /// Since the hand-drawn icons (`add_friends_art.png`, `add_idea_art.png`)
  /// arrived already coloured, the rule takes the icon's own ink, sampled off
  /// the drawing — a rule a shade away from the picture above it reads as a
  /// mistake. Both are deeper members of the brand's blue and brown.
  static const Color addPeopleAccent = Color(0xFF115489);
  static const Color addIdeaAccent = Color(0xFFB25130);

  /// **The four figures at the head of הלוח שלי, one palette colour each.**
  ///
  /// They were all four brown once, on the reasoning that a colour per metric
  /// invites the reader to work out what each one means. What settled it the
  /// other way is that the app already says these four things in colour
  /// everywhere else — a friend is the brand blue, an idea is the copper, a
  /// couple wears the rose the women's side is drawn in, and a wedding is the
  /// palest blue on the page. The rules under the tiles now simply agree with
  /// the rest of the app instead of inventing a fifth convention.
  static const Color metricFriends = primaryDark;
  static const Color metricIdeas = secondary;
  static const Color metricCouples = femaleAccent;
  static const Color metricWeddings = primaryLight;

  /// The same four in the dark theme, where the two light blues would vanish.
  static const Color metricFriendsDm = primaryDarkDm;
  static const Color metricIdeasDm = secondaryDarkDm;
  static const Color metricCouplesDm = femaleAccentDm;
  static const Color metricWeddingsDm = Color(0xFF7FA3B2);

  /// **The two inks the home page is written in.**
  ///
  /// One colour for everything that titles, names or counts, and one for
  /// everything that explains, dates or qualifies — decided here rather than
  /// card by card, because "the heading colour" drifting by a few points per
  /// block is what makes a page of calm cards read as five different pages.
  /// [HomeTypography] folds them onto Material's roles; a block only names one
  /// of these directly when it is not going through that fold.
  ///
  /// [headingInk] is [onSurface] taken round to the brand's blue — the same
  /// near-black weight, so nothing loses contrast, in the hue the rest of the
  /// page is built from. [mutedInk] is a true neutral grey rather than the
  /// warm taupe of [onSurfaceVariant]: beside navy, the warm one reads as a
  /// third colour instead of as quieter text.
  static const Color headingInk = Color(0xFF0B2233);
  static const Color mutedInk = Color(0xFF5E5C58);
  static const Color headingInkDm = Color(0xFFDCE6EC);
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

  // Dark mode uses a clean, cool near-neutral slate rather than the old warm
  // brown, which read as muddy. The blue-grey primary and copper secondary keep
  // the brand accents; only the neutrals (background/surface/lines) are cooled.
  static const Color primaryDarkDm = Color(0xFFAFC7D0);
  static const Color primaryLightDarkDm = Color(0xFF294C57);
  static const Color secondaryDarkDm = Color(0xFFD6A17A);
  static const Color secondaryLightDarkDm = Color(0xFF2A2F36);
  static const Color backgroundDm = Color(0xFF121418);
  static const Color surfaceDm = Color(0xFF1B1E24);
  static const Color onSurfaceDm = Color(0xFFE7E9ED);
  static const Color onSurfaceVariantDm = Color(0xFF9BA1AB);
  static const Color outlineDm = Color(0xFF3A3F48);
  static const Color dividerDm = Color(0xFF272B32);

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
