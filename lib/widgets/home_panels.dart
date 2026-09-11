import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The full-width blocks of the home screen: the database's own suggestions,
/// the two entry actions and the couples banner.
///
/// The ranked actions, the open ideas, the activity summary and the tip live in
/// `home_blocks.dart`; the board and the shared primitives in
/// `home_section.dart`.

/// The deep tone of the brand blue that can carry white text. The light
/// theme's `primary` is a pale blue-grey, too washed out to fill a button.
Color _leadTone(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.primary
      : AppColors.primaryDark;
}

/// The couples banner's own palette — the one block on the page that wears
/// colour. Blue paper, a warm gold glint, and nothing that introduces a new
/// visual language to the rest of the screen.
const Color _datingPaper = Color(0xFFF1F6F8);
const Color _datingPaperWarm = Color(0xFFFFFBF4);
const Color _datingInk = Color(0xFF4F7D99);
const Color _datingInkDm = Color(0xFFA9C9DC);
const Color _celebrationGold = Color(0xFFD4A34B);

/// "רעיונות שהמאגר מציע לך" — the pairs the database worked out on its own.
///
/// **One wide row that opens a screen, and nothing else.** It carried a title,
/// a full-width filled button and a pair of portraits, which made three things
/// to look at for one destination — and put a primary-coloured button near the
/// top of a page whose two loudest controls are the add cards directly under
/// it. What is left is the shape the rest of the page uses for "there is more
/// of this elsewhere": a mark, a line, a line under it, and a chevron. The
/// whole row is the tap target, so nothing inside it has to be one.
///
/// The mark at the head of it is the sealed envelope that used to be the
/// drawing on "הוספת חברים" — see [_HeroMark]. It says at a glance what kind
/// of thing is behind the row, and it costs no height the line of type does
/// not already take. The pair of portraits it replaced stood at the *other*
/// end, which left one row carrying two separate pictures of the same idea.
class HomeHeroBand extends StatelessWidget {
  const HomeHeroBand({super.key, required this.onShowIdeas});

  final VoidCallback onShowIdeas;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = _leadTone(theme);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        // The mark is the first thing to go: it is decoration, and the line of
        // type is the row.
        final bool showMark = constraints.maxWidth >= 300 && textScale <= 1.4;

        return Material(
          color: dark
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onShowIdeas,
            child: Ink(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                // No outline — the same rule as the block above it: the wash
                // separates it from the page on its own, and a line round a
                // tinted fill is a second edge for one shape.
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: <Color>[
                    lead.withValues(alpha: dark ? 0.14 : 0.06),
                    dark
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.surface,
                  ],
                ),
              ),
              child: Row(
                children: <Widget>[
                  // **The sealed envelope**, which used to be the drawing on
                  // "הוספת חברים". It is the one mark in the set that means
                  // *something arrived for you* rather than *do something* —
                  // which is exactly what this row is, and is why the pair of
                  // portraits that stood at the other end of it has gone: two
                  // marks for one destination, and the couple was the vaguer
                  // of them. Recoloured at draw time so the strokes wear the
                  // row's own lead in either theme — see [HomeLineArt].
                  if (showMark) ...<Widget>[
                    _HeroMark(lead: lead, dark: dark),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Named for what it is: pairs the database worked out
                        // on its own, not ideas the matchmaker opened.
                        //
                        // **Exactly the size of "עוצרים רגע לחשוב על חברים"
                        // above it.** These two blocks sit one on top of the
                        // other and are the two invitations at the top of the
                        // page; each was scaled to whatever width its own card
                        // had left over, so the pair read as a banner with a
                        // footnote under it. One size, fixed — see
                        // [HomeBannerTitle].
                        //
                        // The line that used to sit under it, "שווה הצצה,
                        // אולי מחכה שם חיבור", is gone: the heading already
                        // says what the row is.
                        const HomeBannerTitle(text: 'רעיונות שהמאגר מציע לך'),
                      ],
                    ),
                  ),
                  // `chevron_right` and not `chevron_left`: Material's
                  // directional icons mirror themselves, so in this RTL app
                  // this is the one that points the way the page is going.
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 26,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The envelope that heads "רעיונות שהמאגר מציע לך".
///
/// A drawing rather than a Material glyph, because every other block at the
/// top of these pages is headed by one of the app's own line illustrations and
/// an outlined mail icon among them reads as a control that wandered in. It
/// sits in a disc of the row's own tint so the white ground the file ships
/// with never shows — see [HomeLineArt] for how the two colours are put on.
class _HeroMark extends StatelessWidget {
  const _HeroMark({required this.lead, required this.dark});

  final Color lead;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color disc = Color.alphaBlend(
      lead.withValues(alpha: dark ? 0.20 : 0.10),
      dark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surface,
    );

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
      padding: const EdgeInsets.all(9),
      child: HomeLineArt(
        asset: 'assets/home_add_people2.png',
        ink: lead,
        paper: disc,
      ),
    );
  }
}

/// "הוספת חברים" and "הוספת רעיון" — the two most important things on the page,
/// because they are the two that make everything else on it possible.
///
/// Each is one illustrated card: the drawing is the top of it, a coloured band
/// across the bottom carries the name of the action, and the whole surface is
/// the button. There is no chevron and no inner badge — a card that is entirely
/// a tap target does not need an arrow to say so.
///
/// **The two are exactly the same size.** They used to be split 13:9 while the
/// database was small, on the reasoning that adding friends is what moves
/// anything forward — but two cards drawn as a pair and then set at two
/// different widths read as one card and its afterthought. They are halves of
/// the row now, and what makes adding friends lead is what it is *drawn* in:
/// the deeper of the two tones, and the shadow. See [emphasiseAddPeople].
///
/// **The label is text, not part of the picture.** The artwork these came from
/// had the Hebrew drawn into it, which would have been one less widget and four
/// separate losses: it does not grow with the system font size, a screen reader
/// cannot read it, it is soft on a large display, and it could never be
/// reworded. So each card is a line drawing on its own paper and the band under
/// it is drawn here.
class HomeActionCards extends StatelessWidget {
  const HomeActionCards({
    super.key,
    required this.onAddPeople,
    required this.onAddIdea,
    this.emphasiseAddPeople = false,
  });

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;

  /// While the database is still small, adding friends is the thing that
  /// actually moves anything forward — so the card is drawn louder: a filled
  /// ground behind the drawing rather than a pale one, and a deeper shadow. It
  /// never takes more of the row; the two are always the same size.
  final bool emphasiseAddPeople;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 350;
        // The band is measured rather than guessed at, and the picture takes
        // whatever is left. Sizing it the other way round — a fixed tile height
        // with the band inside it — is what makes a card overflow on a phone
        // with large system text, and this is a card nobody can navigate past.
        final double textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1, 1.8);
        final double bandHeight = (narrow ? 46.0 : 50.0) * textScale;
        // Squatter than the drawing would like, on purpose. These two are the
        // top of a page that has to show what is under them too, and a tile
        // tall enough to give a line drawing room is a tile that pushes
        // everything else off the first screen.
        final double artHeight = (constraints.maxWidth * 0.33).clamp(88, 132);

        return SizedBox(
          height: artHeight + bandHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Equal halves. Adding friends leads by colour and by shadow,
              // never by width — see [emphasiseAddPeople].
              Expanded(
                child: _AddTile(
                  onTap: onAddPeople,
                  compact: narrow,
                  // The notepad, which came off "הוספת רעיון". Adding a
                  // friend is the moment somebody writes a person down —
                  // the name, the age, the two lines that will one day make
                  // a match possible — so the page of ruled lines with a
                  // pencil beside it is the more literal of the two
                  // drawings for the more literal of the two actions.
                  art: 'assets/home_add_idea2.png',
                  band: AppColors.addPeopleBand,
                  ornament: Icons.favorite,
                  label: 'הוספת חברים',
                  bandHeight: bandHeight,
                  primary: true,
                  loud: emphasiseAddPeople,
                ),
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                child: _AddTile(
                  onTap: onAddIdea,
                  compact: narrow,
                  // The heart beside a pencil, which used to head "טיפ
                  // לשדכן". A notepad is a place to write anything down; a
                  // heart being drawn *is* the idea, which is what this card
                  // opens. The tip block took a bulb in its place.
                  art: 'assets/shadchan-tip.png',
                  band: AppColors.addIdeaBand,
                  ornament: Icons.star_rounded,
                  label: 'הוספת רעיון',
                  bandHeight: bandHeight,
                  primary: false,
                  loud: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One of the two entry tiles: its drawing, its band, and one tap target over
/// the whole of it.
///
/// The drawing is a black-on-white line illustration recoloured at draw time —
/// see [HomeLineArt] — so the paper under it is the card's own, and in the dark
/// theme the strokes come out light on a dark ground rather than as a lightbox.
class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.onTap,
    required this.compact,
    required this.art,
    required this.band,
    required this.ornament,
    required this.label,
    required this.bandHeight,
    required this.primary,
    required this.loud,
  });

  final VoidCallback onTap;
  final bool compact;
  final String art;
  final Color band;
  final IconData ornament;
  final String label;
  final double bandHeight;
  final bool primary;

  /// Drawn to be picked first: a tinted ground behind the illustration instead
  /// of the plain paper, and a deeper shadow under the card.
  final bool loud;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // The ground the drawing sits on, and what its strokes are drawn in. In the
    // dark theme the two swap over: pale ink on the card's own dark paper.
    final Color paper = dark
        ? Color.alphaBlend(
            band.withValues(alpha: loud ? 0.22 : 0.12),
            theme.colorScheme.surface,
          )
        : Color.alphaBlend(
            band.withValues(alpha: loud ? 0.16 : 0.07),
            AppColors.surface,
          );
    final Color ink = dark
        ? Color.alphaBlend(band.withValues(alpha: 0.55), Colors.white)
        : band;

    return Material(
      // The band's own colour, so the corners the drawing does not reach are
      // never the page showing through.
      color: band,
      borderRadius: BorderRadius.circular(22),
      elevation: loud ? 3 : (primary ? 2 : 0),
      // A neutral shadow, not one tinted with the band. Tinting worked while
      // the tile was a flat blue rectangle; under an illustration the same
      // shadow reads as a coloured halo drawn around the card rather than as
      // the card sitting above the page.
      shadowColor: AppColors.onSurface.withValues(alpha: 0.4),
      // **No elevation overlay.** Material 3 lightens a raised surface towards
      // `surfaceTint`, which in the dark theme is a pale blue — so a raised
      // card's band would drift off the brand colour and take the contrast of
      // the white label on it with it. The band is a brand colour, not a
      // surface: it means the same thing at any elevation.
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(
                child: ColoredBox(
                  color: paper,
                  child: Padding(
                    // The drawings are line art with very little margin of
                    // their own, so the breathing room is given here rather
                    // than baked into three separate files.
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 14,
                      compact ? 8 : 10,
                      compact ? 10 : 14,
                      compact ? 6 : 8,
                    ),
                    child: SizedBox.expand(
                      child: HomeLineArt(asset: art, ink: ink, paper: paper),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: bandHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          // No size of its own: the page decides that once,
                          // for every block on it — see [HomeTypography]. The
                          // `FittedBox` above still shrinks the label on a
                          // narrow card, which is what `compact` used to do by
                          // hand.
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _BandRule(icon: ornament),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Above the picture rather than under it: the ripple of an `InkWell`
          // is painted by the `Material` behind it, so an image in between
          // would leave the tap looking dead everywhere except the band.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, child: const SizedBox.expand()),
            ),
          ),
        ],
      ),
    );
  }
}

/// The little rule under a tile's label — two strokes with a mark between them.
///
/// It is the one piece of the artwork's band that is redrawn rather than
/// cropped away, because without it the band is a plain colour bar and the two
/// cards stop looking like the pair they were drawn as.
class _BandRule extends StatelessWidget {
  const _BandRule({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final Color ink = AppColors.onPrimary.withValues(alpha: 0.6);

    Widget stroke() => Container(width: 16, height: 1, color: ink);
    Widget dot() => Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        dot(),
        stroke(),
        Icon(icon, size: 10, color: ink),
        stroke(),
        dot(),
      ],
    );
  }
}

/// One couple on the celebration banner.
class HomeDatingCouple {
  const HomeDatingCouple({
    required this.matchId,
    required this.names,
    required this.sinceLabel,
    this.personA,
    this.personB,
  });

  final String matchId;
  final String names;

  /// The whole sentence, not a fragment: "יוצאים מהיום", "יוצאים כבר יומיים",
  /// "יוצאים כבר שבוע". It used to be a duration with "יוצאים כבר" glued in
  /// front of it here, which produced "יוצאים כבר מהיום" for every couple in
  /// their first days — and, because the figure came from the proposal's
  /// `updatedAt`, for every couple whose card had just been touched. See
  /// `DatingCheckIn.datingSinceLabel`.
  final String sinceLabel;

  final Person? personA;
  final Person? personB;
}

/// "זוגות שיוצאים" — the strongest of the closing home banners. It is festive
/// through the brand blue, a warm gold glint and layered paper rather than pink
/// decoration, so it stays joyful without becoming loud or gendered.
class HomeDatingBanner extends StatefulWidget {
  const HomeDatingBanner({
    super.key,
    required this.couples,
    required this.onOpen,
  });

  final List<HomeDatingCouple> couples;
  final void Function(String matchId) onOpen;

  @override
  State<HomeDatingBanner> createState() => _HomeDatingBannerState();
}

class _HomeDatingBannerState extends State<HomeDatingBanner> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark ? _datingInkDm : _datingInk;
    final int count = widget.couples.length;
    final int current = _page.clamp(0, count - 1);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: accent.withValues(alpha: dark ? 0.48 : 0.38),
          width: 1.4,
        ),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: dark
              ? <Color>[
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.surface,
                ]
              : const <Color>[_datingPaperWarm, _datingPaper],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: dark ? 0.12 : 0.16),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            top: -32,
            start: -24,
            child: _CelebrationOrb(
              size: 104,
              color: _celebrationGold.withValues(alpha: dark ? 0.08 : 0.10),
            ),
          ),
          PositionedDirectional(
            bottom: -42,
            end: -30,
            child: _CelebrationOrb(
              size: 126,
              color: accent.withValues(alpha: dark ? 0.08 : 0.09),
            ),
          ),
          Column(
            children: <Widget>[
              SizedBox(
                height: homeScaled(context, 128),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: count,
                  onPageChanged: (int index) => setState(() => _page = index),
                  itemBuilder: (BuildContext context, int index) {
                    return _DatingPage(
                      couple: widget.couples[index],
                      onOpen: () =>
                          widget.onOpen(widget.couples[index].matchId),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 12),
                child: Column(
                  children: <Widget>[
                    if (count > 1) ...<Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (int i = 0; i < count; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == current ? 16 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: accent.withValues(
                                  alpha: i == current ? 0.90 : 0.26,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: dark ? 0.15 : 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'ממשיכים לשמור איתם על קשר עד החתונה! :)',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: dark
                              ? theme.colorScheme.onSurface
                              : _datingInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CelebrationOrb extends StatelessWidget {
  const _CelebrationOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DatingPage extends StatelessWidget {
  const _DatingPage({required this.couple, required this.onOpen});

  final HomeDatingCouple couple;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark ? _datingInkDm : _datingInk;
    final Color paper = dark ? theme.colorScheme.surface : _datingPaper;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Row(
          children: <Widget>[
            _CoupleFaces(
              personA: couple.personA,
              personB: couple.personB,
              paper: paper,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 15,
                          color: _celebrationGold,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'זוגות שיוצאים',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    couple.names,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    couple.sinceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: accent),
                  ),
                ],
              ),
            ),
            HomeArrowButton(
              background: accent.withValues(alpha: dark ? 0.22 : 0.14),
              foreground: dark
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.72),
              size: 34,
              // Material mirrors the chevrons in RTL, so `chevron_right` is
              // what draws an arrow pointing the way the page reads — left.
              icon: Icons.chevron_right,
            ),
          ],
        ),
      ),
    );
  }
}

/// The couple's two faces with one small heart resting where they meet.
class _CoupleFaces extends StatelessWidget {
  const _CoupleFaces({
    required this.personA,
    required this.personB,
    required this.paper,
  });

  final Person? personA;
  final Person? personB;

  /// The banner's own paper, so the ring between the faces and the halo behind
  /// the heart disappear into it.
  final Color paper;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        HomeCardCoupleAvatars(
          personA: personA,
          personB: personB,
          radius: 25,
          ringColor: paper,
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: paper, shape: BoxShape.circle),
              child: const Icon(
                Icons.favorite,
                size: 15,
                color: AppColors.femaleAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "כל הכבוד! 3 זוגות שלך יוצאים — שומרים איתם על קשר עד החתונה!"
///
/// **A strip, not a banner.** The couples who are out used to be a colourful
/// card on the home screen, three faces wide and a third of a phone tall,
/// carrying nothing anybody acts on — it was pure encouragement, and pure
/// encouragement does not earn that much of a landing page. It is one line at
/// the head of "הרעיונות שלי" now, where the couples themselves are a tap away
/// on the "יוצאים" shelf, and tapping the line is what opens that shelf.
///
/// It exists only while there is somebody to celebrate, which is what keeps it
/// from becoming furniture.
class DatingCouplesStrip extends StatelessWidget {
  const DatingCouplesStrip({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? _datingInkDm : _datingInk;
    final String couples = count == 1
        ? 'זוג אחד שלך יוצא'
        : '$count זוגות שלך יוצאים';

    return Material(
      color: dark
          ? Color.alphaBlend(
              ink.withValues(alpha: 0.14),
              theme.colorScheme.surface,
            )
          : _datingPaper,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 8, 9),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.celebration_rounded,
                size: 17,
                color: _celebrationGold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'כל הכבוד! $couples — שומרים איתם על קשר עד החתונה!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: dark ? theme.colorScheme.onSurface : _datingInk,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}
