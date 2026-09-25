import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
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
/// colour. Blue paper, a warm glint, and nothing that introduces a new visual
/// language to the rest of the screen.
///
/// **Named here, chosen in [AppColors].** These were five hand-picked tones,
/// each a shade off a brand colour it sat next to; the whole point of the page
/// having a palette is that the blue in one block is the blue in the next.
const Color _datingPaper = AppColors.primaryLight;
const Color _datingPaperWarm = AppColors.surface;

/// `primaryInk` and not `primaryDark`, because everything written in it sits
/// on [_datingPaper] — a light wash of its own colour, where the brand tone
/// itself does not hold a readable contrast. That is the case `primaryInk`
/// exists for.
const Color _datingInk = AppColors.primaryInk;
const Color _datingInkDm = AppColors.primaryDarkDm;
const Color _celebrationGold = AppColors.secondary;

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

        // The same white card the home page's blocks wear, with the copper
        // rule under it: an idea is what this row opens, and copper is what an
        // idea is drawn in everywhere else in the app.
        return HomePaperCard(
          stripe: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          onTap: onShowIdeas,
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
                color: AppColors.muted(dark: dark),
              ),
            ],
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
/// **One pair from one system.** Both are the same white card at the same
/// size, radius and shadow, with the icon over the label as one centred unit
/// and a small chevron at the outer edge. The only two things that differ are
/// the drawing and the colour of the rule along the foot — and that colour is
/// the drawing's own ink ([AppColors.addPeopleAccent] /
/// [AppColors.addIdeaAccent]), so the rule and the picture are one colour.
///
/// **The drawings are shown as they are.** They are hand-drawn with a line
/// that thickens and thins along its length, already in their colour, and cut
/// off their ground into transparent PNGs. They are never recoloured and never
/// replaced by a library glyph: the unevenness is what gives the pair its
/// warmth, and a uniform outline would be exactly the generic kit look these
/// were drawn to avoid.
///
/// **The label is text, not part of the picture**, so it grows with the
/// system font and a screen reader can read it.
class HomeActionCards extends StatelessWidget {
  const HomeActionCards({
    super.key,
    required this.onAddPeople,
    required this.onAddIdea,
    this.emphasiseAddPeople = false,
  });

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;

  /// Kept for the callers that still pass it. The pair is deliberately
  /// identical now — the difference is the drawing and the rule, never the
  /// weight — so this changes nothing.
  final bool emphasiseAddPeople;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 350;
        // The label is measured rather than guessed at, so a phone with large
        // system text grows the card instead of overflowing it.
        final double textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1, 1.8);
        final double labelHeight = 24 * textScale;
        final double artHeight = (constraints.maxWidth * 0.14).clamp(44, 64);
        final double padding = narrow ? 14 : 18;
        const double gap = 8;

        return SizedBox(
          height:
              padding * 2 + artHeight + gap + labelHeight + AccentBar.thickness,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _AddTile(
                  onTap: onAddPeople,
                  art: 'assets/add_friends_art.png',
                  accent: AppColors.addPeopleAccent,
                  label: 'הוספת חברים',
                  artHeight: artHeight,
                  labelHeight: labelHeight,
                  padding: padding,
                  gap: gap,
                ),
              ),
              SizedBox(width: narrow ? 10 : 14),
              Expanded(
                child: _AddTile(
                  onTap: onAddIdea,
                  art: 'assets/add_idea_art.png',
                  accent: AppColors.addIdeaAccent,
                  label: 'הוספת רעיון',
                  artHeight: artHeight,
                  labelHeight: labelHeight,
                  padding: padding,
                  gap: gap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One of the two entry tiles.
///
/// A press is answered by the card settling — the shadow shrinks and the card
/// sinks a pixel — and by nothing else: no ripple and no change of colour,
/// which on a card this quiet would read as a state rather than as a touch.
class _AddTile extends StatefulWidget {
  const _AddTile({
    required this.onTap,
    required this.art,
    required this.accent,
    required this.label,
    required this.artHeight,
    required this.labelHeight,
    required this.padding,
    required this.gap,
  });

  final VoidCallback onTap;
  final String art;

  /// The rule along the foot — the drawing's own ink.
  final Color accent;

  final String label;
  final double artHeight;
  final double labelHeight;
  final double padding;
  final double gap;

  @override
  State<_AddTile> createState() => _AddTileState();
}

class _AddTileState extends State<_AddTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color paper = theme.colorScheme.surface;
    final BorderRadius radius = BorderRadius.circular(20);

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _pressed ? 1.5 : 0, 0),
          decoration: BoxDecoration(
            color: paper,
            borderRadius: radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                // A neutral shadow, very soft: depth, not a 3D button.
                color: Colors.black.withValues(
                  alpha: dark ? 0.30 : (_pressed ? 0.05 : 0.08),
                ),
                blurRadius: _pressed ? 4 : 14,
                offset: Offset(0, _pressed ? 1 : 5),
              ),
            ],
          ),
          child: ClipRRect(
            // Rounds the rule at the foot along with the card.
            borderRadius: radius,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(widget.padding),
                          // Icon and label are one unit, centred together
                          // with a small, fixed gap — not spread over the
                          // card's height.
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              SizedBox(
                                height: widget.artHeight,
                                child: Image.asset(
                                  widget.art,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                              SizedBox(height: widget.gap),
                              SizedBox(
                                height: widget.labelHeight,
                                child: Padding(
                                  // Clear of the chevron on both sides, so the
                                  // label is centred on the card.
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      widget.label,
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            height: 1.2,
                                            color: AppColors.heading(
                                              dark: dark,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Level with the label, at the edge the page reads
                      // towards — left, in RTL. Dark, but lighter than the
                      // label so it never competes with it. `chevron_right`
                      // because Material mirrors its chevrons in RTL: this is
                      // the one that draws pointing left.
                      PositionedDirectional(
                        end: 8,
                        bottom: widget.padding,
                        height: widget.labelHeight,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.muted(dark: dark),
                        ),
                      ),
                    ],
                  ),
                ),
                AccentUnderline(color: widget.accent),
              ],
            ),
          ),
        ),
      ),
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
