import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The wide blocks of the home screen — the ones that are deliberately *not*
/// cards in a carousel: the opening band, the two entry actions, the couples
/// banner, the month's numbers and the tip strip. Each has its own shape,
/// height and weight, which is what keeps the page from reading as a stack of
/// identical squares.

/// The deep tone of the brand blue that can carry white text. The light
/// theme's `primary` is a pale blue-grey, too washed out to fill a button.
Color _leadTone(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.primary
      : AppColors.primaryDark;
}

/// A restrained closing palette: blue carries the celebratory banner, the
/// warm sand belongs to the tip, and each monthly metric keeps its established
/// accent. None of these introduces a new visual language to the home page.
const Color _datingPaper = Color(0xFFF1F6F8);
const Color _datingPaperWarm = Color(0xFFFFFBF4);
const Color _datingInk = Color(0xFF4F7D99);
const Color _datingInkDm = Color(0xFFA9C9DC);
const Color _celebrationGold = Color(0xFFD4A34B);
const Color _quietInk = Color(0xFF666666);
const Color _tipInk = Color(0xFF5C84A3);
const Color _tipInkDm = Color(0xFF9DBED6);
const Color _tipPaper = Color(0xFFFBF5EA);

/// The opening band under the app bar: one short thought about connections and
/// the single button that starts the work.
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
            borderRadius: BorderRadius.circular(narrow ? 22 : 28),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.18),
            ),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: dark
                  ? <Color>[
                      theme.colorScheme.primary.withValues(alpha: 0.18),
                      theme.colorScheme.surface,
                    ]
                  : <Color>[
                      AppColors.primaryLight.withValues(alpha: 0.75),
                      AppColors.surface,
                      AppColors.secondaryLight.withValues(alpha: 0.65),
                    ],
            ),
          ),
          child: CustomPaint(
            painter: _HeartLinePainter(
              color: (dark ? theme.colorScheme.primary : AppColors.femaleAccent)
                  .withValues(alpha: dark ? 0.22 : 0.28),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 18,
                narrow ? 14 : 18,
                narrow ? 12 : 16,
                narrow ? 14 : 18,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'אנחנו כאן כדי לעזור לך לחבר בין לבבות',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: narrow ? 14 : null,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        SizedBox(height: narrow ? 10 : 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onShowIdeas,
                            style: FilledButton.styleFrom(
                              backgroundColor: lead,
                              foregroundColor: theme.colorScheme.onPrimary,
                              padding: EdgeInsets.symmetric(
                                horizontal: narrow ? 10 : 18,
                                vertical: narrow ? 9 : 12,
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
                                Icon(
                                  Icons.auto_awesome,
                                  size: narrow ? 15 : 18,
                                ),
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
                  SizedBox(width: narrow ? 6 : 10),
                  _HeroCouple(compact: narrow),
                ],
              ),
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
    final double radius = compact ? 19 : 31;
    final double overlap = compact ? 12 : 18;

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

/// A single soft line, drawn like a hand-sketched heart trail behind the
/// opening band.
class _HeartLinePainter extends CustomPainter {
  const _HeartLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final double x = size.width * 0.06;
    final double y = size.height * 0.72;
    final double s = size.height * 0.16;

    final Path heart = Path()
      ..moveTo(x, y)
      ..cubicTo(x - s, y - s, x - s * 0.2, y - s * 1.8, x, y - s * 0.9)
      ..cubicTo(x + s * 0.2, y - s * 1.8, x + s, y - s, x, y);
    canvas.drawPath(heart, paint);

    final Path trail = Path()
      ..moveTo(x + s * 0.6, y - s * 0.2)
      ..cubicTo(
        x + s * 2.4,
        y + s * 0.9,
        x + s * 4.2,
        y - s * 1.2,
        x + s * 5.6,
        y - s * 0.1,
      );
    canvas.drawPath(trail, paint);
  }

  @override
  bool shouldRepaint(_HeartLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// "הוסף חברים" and "הוסף רעיון" — two cards that deliberately do not match:
/// one is a filled blue call to action, the other a frameless warm tile.
class HomeActionCards extends StatelessWidget {
  const HomeActionCards({
    super.key,
    required this.onAddPeople,
    required this.onAddIdea,
  });

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 350;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: narrow ? 1 : 11,
                child: _AddPeopleCard(onTap: onAddPeople, compact: narrow),
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                flex: narrow ? 1 : 9,
                child: _AddIdeaCard(onTap: onAddIdea, compact: narrow),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddPeopleCard extends StatelessWidget {
  const _AddPeopleCard({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fill = _leadTone(theme);
    final Color onFill = theme.colorScheme.onPrimary;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(22),
      elevation: 3,
      shadowColor: fill.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 11 : 14,
            compact ? 10 : 14,
            compact ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(compact ? 5 : 7),
                    decoration: BoxDecoration(
                      color: onFill.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_alt,
                      size: compact ? 17 : 20,
                      color: onFill,
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'הוספת חברים',
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 15 : 17,
                          height: 1.2,
                          color: onFill,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeArrowButton(
                  background: onFill.withValues(alpha: 0.22),
                  foreground: onFill,
                  icon: Icons.chevron_right,
                  size: compact ? 27 : 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddIdeaCard extends StatelessWidget {
  const _AddIdeaCard({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondaryInk;
    final Color background = dark
        ? AppColors.secondaryDarkDm.withValues(alpha: 0.16)
        : AppColors.secondaryLight.withValues(alpha: 0.85);

    return Material(
      // No border and no shadow — the warm wash is the whole frame.
      color: background,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 11 : 14,
            compact ? 10 : 14,
            compact ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(compact ? 5 : 7),
                    decoration: BoxDecoration(
                      color: dark
                          ? theme.colorScheme.surface
                          : AppColors.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      size: compact ? 17 : 20,
                      color: ink,
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'הוספת רעיון',
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 15 : 17,
                          height: 1.2,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeArrowButton(
                  background: dark
                      ? theme.colorScheme.surface
                      : AppColors.surface.withValues(alpha: 0.9),
                  foreground: ink,
                  icon: Icons.chevron_right,
                  size: compact ? 27 : 30,
                ),
              ),
            ],
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

/// "הנתונים שלך החודש": three small metric cards on one calm surface. Their
/// order is deliberately RTL: ideas on the right, people in the middle and
/// couples who started dating on the left.
class HomeStatsPanel extends StatelessWidget {
  const HomeStatsPanel({
    super.key,
    required this.stats,
    required this.onTap,
    this.previous,
  });

  final MonthStats stats;
  final MonthStats? previous;
  final VoidCallback onTap;

  /// The three the card has room for, in the order the row reads.
  static const List<MonthlyStatMetric> _shown = <MonthlyStatMetric>[
    MonthlyStatMetric.ideas,
    MonthlyStatMetric.people,
    MonthlyStatMetric.dating,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = _leadTone(theme);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: lead.withValues(alpha: dark ? 0.30 : 0.16),
            ),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: dark
                  ? <Color>[
                      theme.colorScheme.surfaceContainerHighest,
                      theme.colorScheme.surface,
                    ]
                  : <Color>[
                      Colors.white,
                      AppColors.primaryLight.withValues(alpha: 0.28),
                    ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: lead.withValues(alpha: dark ? 0.22 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.insights_rounded, size: 20, color: lead),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'הנתונים שלך החודש',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  HomeArrowButton(
                    background: lead.withValues(alpha: dark ? 0.20 : 0.10),
                    foreground: lead,
                    size: 30,
                    icon: Icons.chevron_right,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final MonthlyStatMetric metric in _shown) ...<Widget>[
                      if (metric != _shown.first) const SizedBox(width: 7),
                      Expanded(
                        child: _MonthNumber(
                          metric: metric,
                          value: metric.valueOf(stats),
                          previous: previous == null
                              ? null
                              : metric.valueOf(previous!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One metric tile. The title remains complete and a positive month-over-month
/// line scales down as one unit rather than being ellipsized.
class _MonthNumber extends StatelessWidget {
  const _MonthNumber({
    required this.metric,
    required this.value,
    required this.previous,
  });

  final MonthlyStatMetric metric;
  final int value;
  final int? previous;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color tone = metric.color;
    final int delta = previous == null ? 0 : value - previous!;
    final bool showRise = delta > 0;

    return Container(
      key: ValueKey<String>('home-stat-${metric.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: dark ? 0.16 : 0.075),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: tone.withValues(alpha: dark ? 0.28 : 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: dark ? 0.28 : 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(metric.icon, size: 18, color: tone),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              height: 1,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11.5,
              height: 1.22,
              fontWeight: FontWeight.w700,
              color: dark ? theme.colorScheme.onSurfaceVariant : _quietInk,
            ),
          ),
          if (showRise) ...<Widget>[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: dark ? 0.22 : 0.13),
                borderRadius: BorderRadius.circular(999),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '+$delta מחודש שעבר',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The tip that closes the page: warm cream paper, a blue lamp badge and a very
/// light botanical line. Its height follows the sentence; no tip is clipped.
class HomeTipStrip extends StatelessWidget {
  const HomeTipStrip({
    super.key,
    required this.tip,
    required this.onAnother,
    this.userGender,
  });

  final String tip;

  /// Moves to the next tip. Labelled and drawn as "forward", not as a reload.
  final VoidCallback onAnother;

  /// The matchmaker's own gender, so the heading reads שדכן or שדכנית.
  final Gender? userGender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? _tipInkDm : _tipInk;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ink.withValues(alpha: dark ? 0.30 : 0.16)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: dark
              ? <Color>[
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.surface,
                ]
              : <Color>[_tipPaper, AppColors.surface.withValues(alpha: 0.96)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: ink.withValues(alpha: dark ? 0.06 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            end: 16,
            bottom: -8,
            child: Icon(
              Icons.eco_outlined,
              size: 74,
              color: _celebrationGold.withValues(alpha: dark ? 0.08 : 0.13),
            ),
          ),
          PositionedDirectional(
            end: 68,
            bottom: 24,
            child: Icon(
              Icons.favorite_border_rounded,
              size: 34,
              color: ink.withValues(alpha: dark ? 0.07 : 0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(68, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'טיפ {לשדכן|לשדכנית}'.forGender(userGender),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tip,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: onAnother,
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('לטיפ נוסף'),
                          SizedBox(width: 3),
                          Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 12,
            start: 14,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.white.withValues(alpha: 0.88),
                shape: BoxShape.circle,
                border: Border.all(color: ink.withValues(alpha: 0.16)),
              ),
              child: Icon(Icons.lightbulb_rounded, size: 22, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
