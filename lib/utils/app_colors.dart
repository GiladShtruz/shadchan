import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';

/// The four all-time figures, in the order they are drawn.
enum MetricKind { friends, ideas, couples, weddings }

abstract final class AppColors {
  // **The palette (2026-11-20, "וינטג' רענן") — the only seven colours the app
  // is drawn in.** Everything else in this file is one of them, a light wash
  // of one of them on white/cream, or one deepened toward the dark blue for
  // text. Recommended weight on a screen: 70% cream/white, 15% blue and
  // teal, 10% copper, 5% rose. Do not add a hue that is not here.
  //
  //  - [darkBlue]  #324754  text, headings, icons
  //  - [blue]      #5F91A3  the main blue: highlights, central elements
  //  - [teal]      #8FB7C4  light grounds, tags, rules between things
  //  - [rose]      #A3647E  a bordeaux-mauve (2026-11-21, was the lighter
  //                         #C97891): women, complementary highlights — the
  //                         notification badge's family, never a light pink
  //  - [copper]    #C98657  the main actions (FAB, send, CTA)
  //  - [cream]     #FAF7F1  the page and wide areas
  //  - [white]     #FFFFFF  cards, windows, clean content
  static const Color darkBlue = Color(0xFF324754);
  static const Color blue = Color(0xFF5F91A3);
  static const Color teal = Color(0xFF8FB7C4);
  static const Color rose = Color(0xFFA3647E);
  static const Color copper = Color(0xFFC98657);
  static const Color cream = Color(0xFFFAF7F1);
  static const Color white = Color(0xFFFFFFFF);

  static const Color primary = blue;

  /// A light wash of [teal] — chips, selected rows, soft grounds.
  static const Color primaryLight = Color(0xFFDDE9ED);

  /// The blue a thing is *marked* in (a man's accent, an open idea). The
  /// palette has one main blue; this is it.
  static const Color primaryDark = blue;
  static const Color secondary = copper;

  /// A light wash of [copper] on cream.
  static const Color secondaryLight = Color(0xFFF3E7DB);

  /// Deeper members of the two hues, for text and icons on their own light
  /// wash: the dark blue itself, and the copper drawn toward it.
  static const Color primaryInk = darkBlue;
  static const Color secondaryInk = Color(0xFF9C7356);

  /// What is drawn *on* a colour or on cream — a button's label, a ring
  /// around a face, the inside of a framed box.
  static const Color surface = white;

  /// The page.
  static const Color background = cream;

  /// **The page is cream; what sits on it is white** — the palette's own
  /// rule ("קרם – רקע כללי", "לבן – כרטיסים, חלונות"). Every scaffold and
  /// bar is [cream]; a bounded thing on it — a card, a tile, a sheet, a
  /// figure square — is white.
  static const Color page = cream;

  /// The ground of a card. Kept under its old name (it was a cream once)
  /// because widgets across the app name it; it is the palette's white.
  static const Color card = white;
  static const Color cardCream = card;
  static const Color onPrimary = white;
  static const Color onSecondary = white;
  static const Color onSurface = darkBlue;
  static const Color onSurfaceVariant = mutedInk;
  static const Color outline = Color(0xFFE2E2DE);
  static const Color error = rose;
  static const Color divider = Color(0xFFE8E7E3);

  static const Color statusIdea = blue;
  static const Color statusChecking = copper;
  static const Color statusUnavailable = mutedInk;
  static const Color statusRejected = copper;
  static const Color statusDating = rose;
  static const Color statusDated = mutedInk;
  static const Color statusMarried = darkBlue;

  /// "Done, together", lifted for the dark theme.
  static const Color statusDatingDm = femaleAccentDm;

  /// Light washes of the palette, for grounds behind a mark.
  static const Color softBlue = primaryLight;
  static const Color softPink = Color(0xFFF2E4EA);
  static const Color softGreen = Color(0xFFE6EFF2);
  static const Color softPurple = Color(0xFFF2E4EA);
  static const Color softSand = Color(0xFFF6ECE4);
  static const Color softYellow = Color(0xFFF6ECE4);
  static const Color softRose = Color(0xFFF2E4EA);

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
  static const Color metricCouples = teal;
  static const Color metricWeddings = femaleAccent;

  /// The same four in the dark theme.
  static const Color metricFriendsDm = primaryDarkDm;
  static const Color metricIdeasDm = secondaryDarkDm;
  static const Color metricCouplesDm = softHighlightDm;
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
  static const Color mutedInk = Color(0xFF6A7880);

  /// Headings at night are the cream, never a blue on the blue.
  static const Color headingInkDm = onSurfaceDm;
  static const Color mutedInkDm = onSurfaceVariantDm;

  static Color heading({bool dark = false}) => dark ? headingInkDm : headingInk;

  static Color muted({bool dark = false}) => dark ? mutedInkDm : mutedInk;

  /// Gentle pastel pairs used for the initials circles next to a contact's
  /// name. Each entry is a soft surface plus the ink that stays readable on it.
  static const List<({Color surface, Color ink})> initialsPastels =
      <({Color surface, Color ink})>[
        (surface: softRose, ink: femaleAccent),
        (surface: softBlue, ink: primaryDark),
        (surface: softPink, ink: femaleInk),
        (surface: softGreen, ink: darkBlue),
        (surface: secondaryLight, ink: secondaryInk),
        (surface: softSand, ink: secondaryInk),
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

  // **Dark mode has a palette of its own (2026-11-21), not the light one
  // with the lights down.** The light palette laid on a dark ground reads
  // grey and washed out, so the night set is tuned for it: a deep blue page,
  // cards a step lighter, a third step for what is active, two warm creams of
  // text, and the accents lifted to stay alive on the dark. The same brand,
  // not the same colours.
  //
  //  - [backgroundDm]    #1B2C35  the page
  //  - [surfaceDm]       #304954  ordinary cards, the search field, sheets
  //  - [surfaceActiveDm] #3F606D  a raised/active card, a selected row
  //  - [onSurfaceDm]     #F5F1E8  headings and important text
  //  - [onSurfaceVariantDm] #B8C8CD  secondary text
  //  - [primaryDarkDm]   #79B4C5  the blue — men, open ideas, highlights
  //  - [femaleAccentDm]  #B86A87  the bordeaux-mauve — women, the badge
  //  - [secondaryDarkDm] #D49262  the terracotta — CTA, "+", progress
  //  - [softHighlightDm] #E8B78F  the peach — gentle highlights
  //
  // Never the light [teal] or [copper] on the dark ground: their night
  // versions are [primaryDarkDm] and [secondaryDarkDm].
  static const Color backgroundDm = Color(0xFF1B2C35);
  static const Color surfaceDm = Color(0xFF304954);
  static const Color surfaceActiveDm = Color(0xFF3F606D);
  static const Color onSurfaceDm = Color(0xFFF5F1E8);
  static const Color onSurfaceVariantDm = Color(0xFFB8C8CD);
  static const Color primaryDarkDm = Color(0xFF79B4C5);
  static const Color secondaryDarkDm = Color(0xFFD49262);
  static const Color softHighlightDm = Color(0xFFE8B78F);

  /// Washes on the dark ground: the active surface for the blue, and the
  /// terracotta laid over a card at a fifth.
  static const Color primaryLightDarkDm = surfaceActiveDm;
  static const Color secondaryLightDarkDm = Color(0xFF515857);

  /// Rules and borders: a step lighter than a card, so a field or a card's
  /// edge is seen without a line that shouts.
  static const Color outlineDm = Color(0xFF4F6F7C);
  static const Color dividerDm = Color(0xFF3F5A66);

  /// Per-gender accents. Men keep the app's stone blue; women get the
  /// bordeaux-mauve [rose] — the same family as the notification badge — and
  /// never a light pink.
  static const Color maleAccent = primaryDark;
  static const Color maleSurface = softBlue;
  static const Color femaleAccent = rose;
  static const Color femaleSurface = softRose;
  static const Color femaleAccentDm = Color(0xFFB86A87);

  /// The bordeaux as text on a dark card: [femaleAccentDm] drawn toward the
  /// cream far enough to be read (≈4:1 on [surfaceDm]) — the night twin of
  /// [femaleInk].
  static const Color femaleInkDm = Color(0xFFCD99A9);

  /// The rose as ink: [femaleAccent] deepened far enough to be read as text
  /// on its own light wash, the way [primaryInk] is to the blue.
  static const Color femaleInk = Color(0xFF7E4A61);

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
  static const Color favorite = rose;

  static const Color profileAvailable = blue;
  static const Color profileBusy = rose;
  static const Color profileOnBreak = copper;

  /// Quieter versions of the availability colours, drawn from the app's own
  /// warm palette instead of the traffic-light primaries. Used where the tag
  /// repeats down a long list and should read as a hint, not an alarm.
  static Color profileStatusSoftColor(ProfileStatus status) {
    switch (status) {
      case ProfileStatus.available:
        return blue;
      case ProfileStatus.busy:
        return rose;
      case ProfileStatus.onBreak:
        return copper;
      case ProfileStatus.mazelTov:
        return secondary;
    }
  }

  /// **The dot beside an availability tag.** Three states, three plain
  /// colours, all from the palette: free is the blue, on a break the copper,
  /// taken the rose.
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

  /// Colour for a person's availability tag: blue / rose / copper.
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
  /// palette's blue, waiting its brown, a couple who are out the rose of the
  /// pink "יוצאים" card (they wore the copper once, which made them
  /// indistinguishable from a waiting idea), and anything that is over is the
  /// quiet grey. The
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
        return dark ? femaleAccentDm : femaleAccent;
      case MatchStatus.married:
        return dark ? statusDatingDm : statusMarried;
      case MatchStatus.rejected:
      case MatchStatus.dated:
        return muted(dark: dark);
    }
  }

  /// The frame a *live* idea wears, wherever it is drawn — its card on
  /// "הרעיונות שלי" and its row or square in "התאמות" alike, so a status is
  /// one colour everywhere: open is the blue, waiting the orange-copper (a
  /// stored "בהמתנה", or either side on a break or taken — [paused]), and a
  /// couple who are out the rose. Null for an idea that is over: it wears no
  /// frame at all.
  static Color? ideaFrame(
    MatchStatus status, {
    bool paused = false,
    bool dark = false,
  }) {
    switch (status) {
      case MatchStatus.dating:
        return dark ? femaleAccentDm : femaleAccent;
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.unavailable:
        if (status == MatchStatus.unavailable || paused) {
          return dark ? secondaryDarkDm : secondary;
        }
        return dark ? primaryDarkDm : primaryDark;
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return null;
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
