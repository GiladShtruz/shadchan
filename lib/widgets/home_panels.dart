import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';
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
/// It sits near the top of the page now, above the two add actions, which is
/// exactly why it stopped being a banner. It used to carry a three-stop
/// gradient, a hand-drawn heart trail and a large pair of portraits; at the top
/// of the screen that read as decoration to scroll past rather than as an
/// offer. What is left is the page's ordinary bordered surface with a soft tint
/// — the same shape the activity card wears — one line of type, one button and
/// one small mark. Nothing here is drawn that does not lead somewhere.
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
        final bool narrow = constraints.maxWidth < 410 || textScale > 1.2;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: lead.withValues(alpha: 0.22)),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: <Color>[
                lead.withValues(alpha: dark ? 0.14 : 0.07),
                theme.colorScheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              narrow ? 12 : 16,
              narrow ? 13 : 15,
              narrow ? 12 : 16,
              narrow ? 13 : 15,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Named for what it is: pairs the database worked out on
                      // its own, not ideas the matchmaker opened.
                      Text(
                        'רעיונות שהמאגר מציע לך',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: narrow ? 15 : 17,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      SizedBox(height: narrow ? 9 : 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onShowIdeas,
                          style: FilledButton.styleFrom(
                            backgroundColor: lead,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: EdgeInsets.symmetric(
                              horizontal: narrow ? 10 : 18,
                              vertical: narrow ? 9 : 11,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: theme.textTheme.labelLarge?.copyWith(
                              fontSize: narrow ? 11.5 : null,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(Icons.auto_awesome, size: narrow ? 15 : 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'הצגת רעיונות חדשים',
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: narrow ? 8 : 12),
                _HeroCouple(compact: narrow),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The two bundled illustrations that stand in for a couple, with a small heart
/// where they meet. Decorative only — no record is behind them.
class _HeroCouple extends StatelessWidget {
  const _HeroCouple({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Smaller than it was: the block is a card near the top of the page now,
    // not the banner it opened as, and the mark is there to identify it rather
    // than to fill it.
    final double radius = compact ? 17 : 24;
    final double overlap = compact ? 11 : 14;

    Widget portrait(String? asset, Color ring) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ring,
          border: Border.all(color: theme.colorScheme.surface, width: 2.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: asset == null
            ? Icon(
                Icons.person_outline,
                color: theme.colorScheme.primary,
                size: radius,
              )
            : Image.asset(asset, fit: BoxFit.cover),
      );
    }

    return SizedBox(
      width: radius * 4 - overlap,
      height: radius * 2 + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          PositionedDirectional(
            start: 0,
            child: portrait(
              PersonAvatarAssets.pathFor(Gender.female, 0),
              AppColors.femaleSurface,
            ),
          ),
          PositionedDirectional(
            start: radius * 2 - overlap,
            child: portrait(
              PersonAvatarAssets.pathFor(Gender.male, 0),
              AppColors.maleSurface,
            ),
          ),
          PositionedDirectional(
            start: radius * 2 - overlap - 8,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite,
                size: 13,
                color: AppColors.femaleAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "הוספת חברים" and "הוספת רעיון" — the two most important things on the page,
/// because they are the two that make everything else on it possible.
///
/// Each is one illustrated card: the picture is the top of it, a coloured band
/// across the bottom carries the name of the action, and the whole surface is
/// the button. There is no chevron and no inner badge — a card that is entirely
/// a tap target does not need an arrow to say so. Adding friends is the louder
/// of the two: it takes more of the row.
///
/// **The label is text, not part of the picture.** The artwork these came from
/// had the Hebrew drawn into it, which would have been one less widget and four
/// separate losses: it does not grow with the system font size, a screen reader
/// cannot read it, it is soft on a large display, and it could never be
/// reworded. So each illustration is cropped to its picture alone and the band
/// under it is drawn here, in the colour sampled from the band the artwork had.
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
  /// actually moves anything forward, so it takes visibly more of the row.
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
        final double bandHeight = (narrow ? 54.0 : 60.0) * textScale;
        final double artHeight = (constraints.maxWidth * 0.42).clamp(104, 172);

        return SizedBox(
          height: artHeight + bandHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Even at rest adding friends leads; while the database is small
              // it leads by more.
              Expanded(
                flex: emphasiseAddPeople ? 13 : 11,
                child: _AddTile(
                  onTap: onAddPeople,
                  compact: narrow,
                  art: 'assets/home_add_people.jpg',
                  band: AppColors.addPeopleBand,
                  ornament: Icons.favorite,
                  label: 'הוספת חברים',
                  bandHeight: bandHeight,
                  primary: true,
                ),
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                flex: emphasiseAddPeople ? 9 : 10,
                child: _AddTile(
                  onTap: onAddIdea,
                  compact: narrow,
                  art: 'assets/home_add_idea.jpg',
                  band: AppColors.addIdeaBand,
                  ornament: Icons.star_rounded,
                  label: 'הוספת רעיון',
                  bandHeight: bandHeight,
                  primary: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One of the two entry tiles: its picture, its band, and one tap target over
/// the whole of it.
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
  });

  final VoidCallback onTap;
  final bool compact;
  final String art;
  final Color band;
  final IconData ornament;
  final String label;
  final double bandHeight;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      // The band's own colour, so the corners the picture does not reach are
      // never the page showing through.
      color: band,
      borderRadius: BorderRadius.circular(22),
      elevation: primary ? 3 : 0,
      // A neutral shadow, not one tinted with the band. Tinting worked while
      // the tile was a flat blue rectangle; under an illustration the same
      // shadow reads as a coloured halo drawn around the card rather than as
      // the card sitting above the page.
      shadowColor: AppColors.onSurface.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(
                child: Image.asset(
                  art,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // The label under it says everything this picture says.
                  excludeFromSemantics: true,
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: (primary ? 17 : 16) * (compact ? 0.9 : 1),
                            height: 1.2,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
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
    required this.duration,
    this.personA,
    this.personB,
  });

  final String matchId;
  final String names;

  /// How long they have been dating, e.g. "3 חודשים".
  final String duration;

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
                        'ממשיכים לשמור על קשר עד החתונה! :)',
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
                            fontSize: 13,
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
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'יוצאים כבר ${couple.duration}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 14,
                      color: accent,
                    ),
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
