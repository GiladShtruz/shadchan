import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/art_tint.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The full-width blocks of the home screen: the database's own suggestions,
/// the two entry actions and the couples banner.
///
/// The ranked actions, the open ideas, the activity summary and the tip live in
/// `home_blocks.dart`; the board and the shared primitives in
/// `home_section.dart`.

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
    // The envelope and one line beside it, drawn exactly like the home
    // page's two add cards — see [HomeArtTile].
    return HomeArtTile(
      art: 'assets/idea_envelope_art.png',
      label: 'רעיונות שהמאגר מציע לך',
      onTap: onShowIdeas,
    );
  }
}

/// One invitation drawn the way "הוספת חברים" / "הוספת רעיון" are: a small
/// copper drawing and its label beside it as one centred unit, on the page's
/// paper, with the copper rule along the foot.
///
/// Used for "עוצרים רגע לחשוב על החברים" (the cup of coffee) and "רעיונות
/// שהמאגר מציע לך" (the envelope), so the head of המאגר שלי and of הרעיונות
/// שלי speak the same language as the head of בית.
class HomeArtTile extends StatelessWidget {
  const HomeArtTile({
    super.key,
    required this.art,
    required this.label,
    required this.onTap,
  });

  /// A single-colour drawing on transparency; tinted to the palette's copper.
  final String art;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondary;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final bool narrow = width < 350;
        final double textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1, 1.8);
        final double labelHeight = 22 * textScale;
        // The same size the add cards give their drawing at half this width,
        // so the three tiles across the app carry one size of icon.
        final double artHeight = (width * 0.5 * 0.085).clamp(30, 40);
        final double padding = narrow ? 10 : 12;

        return SizedBox(
          height: HomeActionCards.heightFor(context, width * 0.5),
          child: _AddTile(
            onTap: onTap,
            art: art,
            // The drawing and the rule along the foot stay copper; the words
            // are the palette's dark blue, like every heading on the page.
            tint: ColorFilter.mode(ink, BlendMode.srcIn),
            accent: ink,
            labelColor: AppColors.heading(dark: dark),
            label: label,
            artHeight: artHeight,
            labelHeight: labelHeight,
            padding: padding,
            divided: true,
          ),
        );
      },
    );
  }
}

/// "הוספת חברים" and "הוספת רעיון" — the two most important things on the page,
/// because they are the two that make everything else on it possible.
///
/// **One pair from one system.** Both are the same card at the same radius
/// and shadow, with the icon beside the label as one centred unit. The
/// drawing and the rule along the foot are one palette colour each — the deep
/// brand blue for friends, the copper for an idea ([AppColors.addPeopleAccent]
/// / [AppColors.addIdeaAccent]) — and nothing else on them is coloured.
///
/// **"הוספת חברים" leads, a little.** It is slightly wider, sits on a faint
/// wash of its own blue and carries a heavier shadow: the database is what
/// every other thing on the page is made from, so growing it should be the
/// easier of the two to reach for — without the pair stopping being a pair.
///
/// **The drawings keep their line.** They are hand-drawn with a stroke that
/// thickens and thins along its length; [artTint] moves them into the palette
/// by luminance, so the texture survives and only the ink changes.
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

  /// Gives "הוספת חברים" the slightly larger share and the faint wash.
  final bool emphasiseAddPeople;

  /// How tall the pair is at [width] — the same sum [build] makes, so the
  /// home screen can pin the row under its search bar at exactly this height.
  static double heightFor(BuildContext context, double width) {
    final bool narrow = width < 350;
    final double textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.8);
    final double labelHeight = 22 * textScale;
    final double artHeight = (width * 0.085).clamp(30, 40);
    final double padding = narrow ? 10 : 12;
    return padding * 2 +
        (artHeight > labelHeight ? artHeight : labelHeight) +
        AccentBar.thickness;
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color peopleInk = dark
        ? AppColors.primaryDarkDm
        : AppColors.addPeopleAccent;
    final Color ideaInk = dark
        ? AppColors.secondaryDarkDm
        : AppColors.addIdeaAccent;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 350;
        // The label is measured rather than guessed at, so a phone with large
        // system text grows the card instead of overflowing it.
        final double textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1, 1.8);
        final double labelHeight = 22 * textScale;
        // Icon and label sit side by side now, so the card is only as tall as
        // the taller of the two — about half of what it was.
        final double artHeight = (constraints.maxWidth * 0.085).clamp(30, 40);
        final double padding = narrow ? 10 : 12;

        return SizedBox(
          height:
              padding * 2 +
              (artHeight > labelHeight ? artHeight : labelHeight) +
              AccentBar.thickness,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: emphasiseAddPeople ? 11 : 1,
                child: _AddTile(
                  onTap: onAddPeople,
                  art: 'assets/add_friends_art.png',
                  tint: artTint(peopleInk, ArtTint.addFriends),
                  accent: peopleInk,
                  label: 'הוספת חברים',
                  artHeight: artHeight,
                  labelHeight: labelHeight,
                  padding: padding,
                  emphasised: emphasiseAddPeople,
                  prominent: true,
                ),
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                flex: emphasiseAddPeople ? 9 : 1,
                child: _AddTile(
                  onTap: onAddIdea,
                  art: 'assets/add_idea_art.png',
                  tint: artTint(ideaInk, ArtTint.addIdea),
                  accent: ideaInk,
                  label: 'הוספת רעיון',
                  artHeight: artHeight,
                  labelHeight: labelHeight,
                  padding: padding,
                  prominent: true,
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
    required this.tint,
    required this.accent,
    required this.label,
    required this.artHeight,
    required this.labelHeight,
    required this.padding,
    this.emphasised = false,
    this.divided = false,
    this.labelColor,
    this.prominent = false,
  });

  final VoidCallback onTap;
  final String art;

  /// The two entry cards on בית: a wash and a frame of their own colour, the
  /// label in that colour and the drawing on a soft disc, with a shadow tinted
  /// to match — so they read as the page's two main buttons. The type is the
  /// same size as before; only the colour and depth change.
  final bool prominent;

  /// The label's ink — the heading blue unless the tile names its own.
  final Color? labelColor;

  /// A short, faint rule between the drawing and the label.
  final bool divided;

  /// Recolours the drawing into [accent].
  final ColorFilter tint;

  /// The rule along the foot, and the drawing's ink.
  final Color accent;

  final String label;
  final double artHeight;
  final double labelHeight;
  final double padding;

  /// The lead tile: a faint wash of its own colour and a deeper shadow.
  final bool emphasised;

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
    final bool prominent = widget.prominent;
    final Color paper = prominent
        ? Color.alphaBlend(
            widget.accent.withValues(alpha: dark ? 0.20 : 0.11),
            theme.colorScheme.surface,
          )
        : widget.emphasised
        ? Color.alphaBlend(
            widget.accent.withValues(alpha: dark ? 0.16 : 0.07),
            theme.colorScheme.surface,
          )
        : theme.colorScheme.surface;
    final BorderRadius radius = BorderRadius.circular(18);
    final double rest = widget.emphasised ? 0.12 : 0.07;
    final Color labelInk = prominent
        ? (dark ? AppColors.heading(dark: true) : widget.accent)
        : (widget.labelColor ?? AppColors.heading(dark: dark));

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
            border: prominent
                ? Border.all(
                    color: widget.accent.withValues(alpha: dark ? 0.6 : 0.45),
                    width: 1.4,
                  )
                : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                // A neutral shadow, very soft: depth, not a 3D button. The
                // two entry cards on בית take it in their own colour.
                color: prominent && !dark
                    ? widget.accent.withValues(alpha: _pressed ? 0.10 : 0.24)
                    : Colors.black.withValues(
                        alpha: dark ? 0.30 : (_pressed ? 0.05 : rest),
                      ),
                blurRadius: _pressed
                    ? 4
                    : (prominent ? 16 : (widget.emphasised ? 16 : 12)),
                offset: Offset(0, _pressed ? 1 : (prominent ? 5 : 4)),
              ),
            ],
          ),
          child: ClipRRect(
            // Rounds the rule at the foot along with the card.
            borderRadius: radius,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.padding,
                      vertical: widget.padding,
                    ),
                    // Icon and label side by side, as one centred unit.
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          height: widget.artHeight,
                          width: widget.artHeight,
                          padding: prominent
                              ? EdgeInsets.all(widget.artHeight * 0.14)
                              : EdgeInsets.zero,
                          decoration: prominent
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.surface.withValues(
                                    alpha: dark ? 0.35 : 0.9,
                                  ),
                                )
                              : null,
                          child: ColorFiltered(
                            colorFilter: widget.tint,
                            child: Image.asset(
                              widget.art,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                        if (widget.divided) ...<Widget>[
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: widget.artHeight * 0.7,
                            color:
                                (widget.labelColor ??
                                        AppColors.heading(dark: dark))
                                    .withValues(alpha: 0.22),
                          ),
                          const SizedBox(width: 10),
                        ] else
                          const SizedBox(width: 8),
                        Flexible(
                          child: SizedBox(
                            height: widget.labelHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: prominent
                                      ? FontWeight.w900
                                      : FontWeight.w800,
                                  height: 1.2,
                                  color: labelInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
/// the top of הלוח שלי now, beside the rest of the work in hand, and tapping it
/// opens the "יוצאים" shelf on הרעיונות שלי.
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
    // The rose-to-honey wash a dating couple's own card wears on "הרעיונות
    // שלי", and nothing around it: no frame, no glow, no sparkle — the wash and
    // the rose ink of the words are the whole decoration.
    final Color rose = dark ? AppColors.femaleAccentDm : AppColors.femaleAccent;
    final Color surface = theme.colorScheme.surface;
    final String couples = count == 1
        ? 'זוג אחד שלך יוצא'
        : '$count זוגות שלך יוצאים';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: <Color>[
                Color.alphaBlend(
                  AppColors.softRose.withValues(alpha: dark ? 0.26 : 0.95),
                  surface,
                ),
                Color.alphaBlend(
                  AppColors.softYellow.withValues(alpha: dark ? 0.14 : 0.70),
                  surface,
                ),
              ],
            ),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rose.withValues(alpha: dark ? 0.28 : 0.18),
                ),
                child: Icon(Icons.favorite_rounded, size: 18, color: rose),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'כל הכבוד! $couples — שומרים איתם על קשר עד החתונה!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: dark ? rose : AppColors.femaleInk,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: rose),
            ],
          ),
        ),
      ),
    );
  }
}
