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

/// The three closing blocks of the page — the couples banner, the month's
/// numbers and the tip — are drawn from their own small palette rather than
/// from the theme: a barely-there green paper, one green ink, one blue ink and
/// one grey, with a hairline between the numbers. Dark mode swaps each for a
/// lighter twin, since these tones are mixed for cream paper.
const Color _datingPaper = Color(0xFFF3F7ED);
const Color _datingInk = Color(0xFF699A6A);
const Color _datingInkDm = Color(0xFF9BC49B);
const Color _quietInk = Color(0xFF666666);
const Color _hairline = Color(0xFFECECEC);
const Color _tipInk = Color(0xFF5C84A3);
const Color _tipInkDm = Color(0xFF9DBED6);

/// The white paper the numbers and the tip sit on. It is the one place on the
/// page that is plain white rather than the app's cream.
Color _cardPaper(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surface
      : Colors.white;
}

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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
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
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'כל חיבור מתחיל ברעיון טוב',
                      maxLines: 2,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'אנחנו כאן כדי לעזור לך לחבר בין לבבות',
                      maxLines: 2,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: onShowIdeas,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('הצגת רעיונות חדשים'),
                      style: FilledButton.styleFrom(
                        backgroundColor: lead,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: const StadiumBorder(),
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _HeroCouple(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two bundled illustrations that stand in for a couple, with a small heart
/// where they meet. Decorative only — no record is behind them.
class _HeroCouple extends StatelessWidget {
  const _HeroCouple();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const double radius = 31;
    const double overlap = 18;

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
    required this.stacked,
    required this.onAddPeople,
    required this.onAddIdea,
  });

  /// While the database is still small, growing it is the only thing that
  /// matters, so "הוסף חברים" takes a wide card of its own above the other.
  final bool stacked;

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        children: <Widget>[
          _AddPeopleCard(onTap: onAddPeople, wide: true),
          const SizedBox(height: 10),
          _AddIdeaCard(onTap: onAddIdea, wide: true),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // In RTL the first child sits on the right: "הוסף חברים" leads the
          // pair. Unequal weights on purpose, so the two never read as two
          // identical squares.
          Expanded(flex: 11, child: _AddPeopleCard(onTap: onAddPeople)),
          const SizedBox(width: 12),
          Expanded(flex: 9, child: _AddIdeaCard(onTap: onAddIdea)),
        ],
      ),
    );
  }
}

class _AddPeopleCard extends StatelessWidget {
  const _AddPeopleCard({required this.onTap, this.wide = false});

  final VoidCallback onTap;
  final bool wide;

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
          padding: EdgeInsets.fromLTRB(14, wide ? 16 : 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: onFill.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_alt,
                      size: wide ? 24 : 20,
                      color: onFill,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'הוספת חברים',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (wide
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.titleSmall)
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: onFill,
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'לא משאירים אף חבר/ה רווק/ה מאחור',
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onFill.withValues(alpha: 0.88),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeArrowButton(
                  background: onFill.withValues(alpha: 0.22),
                  foreground: onFill,
                  icon: Icons.chevron_right,
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
  const _AddIdeaCard({required this.onTap, this.wide = false});

  final VoidCallback onTap;
  final bool wide;

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
          padding: EdgeInsets.fromLTRB(14, wide ? 16 : 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: dark
                          ? theme.colorScheme.surface
                          : AppColors.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      size: wide ? 24 : 20,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'הוספת רעיון',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (wide
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.titleSmall)
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'שמירת רעיונות במקום אחד',
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeArrowButton(
                  background: dark
                      ? theme.colorScheme.surface
                      : AppColors.surface.withValues(alpha: 0.9),
                  foreground: ink,
                  icon: Icons.chevron_right,
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

/// "זוגות שיוצאים" — one wide, quietly festive banner rather than another row
/// of cards. Several couples are paged through in place.
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
      // No frame: the green paper alone is what lifts the banner off the page.
      decoration: BoxDecoration(
        color: dark ? theme.colorScheme.surface : _datingPaper,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: homeScaled(context, 116),
            child: PageView.builder(
              controller: _controller,
              itemCount: count,
              onPageChanged: (int index) => setState(() => _page = index),
              itemBuilder: (BuildContext context, int index) {
                return _DatingPage(
                  couple: widget.couples[index],
                  onOpen: () => widget.onOpen(widget.couples[index].matchId),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
                          width: i == current ? 14 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: i == current ? 0.85 : 0.30,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'שומרים על קשר :) כל זוג צריך חבר אחד שיאמין בו',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 13,
                    height: 1.3,
                    color: dark
                        ? theme.colorScheme.onSurfaceVariant
                        : _quietInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
                  // The label carries no heart of its own: the only one on the
                  // banner is the small one between the two faces.
                  Text(
                    'זוגות שיוצאים',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    couple.names,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
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

/// "הנתונים שלך החודש": the month's three numbers on white paper, each one a
/// pastel circle over a big figure, with hairlines between them. It stays a way
/// in — the fourth number and the records behind all of them live on the stats
/// screen.
class HomeStatsPanel extends StatelessWidget {
  const HomeStatsPanel({super.key, required this.stats, required this.onTap});

  final MonthStats stats;
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
    final Color line = dark ? theme.dividerColor : _hairline;

    return Material(
      color: _cardPaper(theme),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: lead.withValues(alpha: dark ? 0.22 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.insights_outlined, size: 18, color: lead),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'הנתונים שלך החודש',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: lead,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  for (final MonthlyStatMetric metric in _shown) ...<Widget>[
                    if (metric != _shown.first)
                      Container(width: 1, height: 36, color: line),
                    Expanded(
                      child: _MonthNumber(
                        metric: metric,
                        value: metric.valueOf(stats),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  HomeArrowButton(
                    background: line,
                    foreground: theme.colorScheme.onSurface.withValues(
                      alpha: 0.72,
                    ),
                    size: 30,
                    // Material mirrors the chevrons in RTL, so `chevron_right`
                    // is the one that renders as an arrow pointing left.
                    icon: Icons.chevron_right,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the month's numbers: the figure, the metric's own pastel circle
/// beside it, and the caption under both.
class _MonthNumber extends StatelessWidget {
  const _MonthNumber({required this.metric, required this.value});

  final MonthlyStatMetric metric;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color tone = metric.color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: dark ? 0.26 : 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(metric.icon, size: 17, color: tone),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          metric.shortTitle,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 12.5,
            height: 1.25,
            color: dark ? theme.colorScheme.onSurfaceVariant : _quietInk,
          ),
        ),
      ],
    );
  }
}

/// The tip that closes the page: white paper with one blue stripe down its
/// leading edge and a lamp resting on it. The tip itself is left in plain body
/// ink — it is the one sentence on the page meant to be *read*, not scanned —
/// and moving on is a quiet link rather than a button.
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
        color: _cardPaper(theme),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: <Widget>[
          // The stripe runs the full height of whatever the text needs, so a
          // long tip simply makes it longer.
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            child: Container(
              width: 16,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: const BorderRadiusDirectional.horizontal(
                  start: Radius.circular(16),
                ),
              ),
            ),
          ),
          Padding(
            // The end padding leaves the lamp and its stripe a lane of their
            // own, so no line of the tip ever runs under them.
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 70, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'טיפ {לשדכן|לשדכנית}'.forGender(userGender),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tip,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                // In RTL the end edge is the left one, which is where the way
                // on sits — out of the way of the sentence itself.
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('טיפ נוסף'),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 12,
            end: 14,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark
                    ? theme.colorScheme.surfaceContainerHighest
                    : ink.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lightbulb_outline, size: 22, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
