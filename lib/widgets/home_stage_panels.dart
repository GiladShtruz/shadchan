import 'package:flutter/material.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/widgets/home_section.dart';

Color _lead(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.primary
    : AppColors.primaryDark;

/// The opening card a brand-new matchmaker lands on.
///
/// Shown *inside* the real home screen rather than as a wizard in front of it:
/// nothing here blocks the rest of the app, and adding friends is an invitation
/// rather than a toll gate. It disappears on its own once the database starts.
class HomeWelcomeCard extends StatelessWidget {
  const HomeWelcomeCard({super.key, required this.onAddPeople});

  final VoidCallback onAddPeople;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: dark
              ? <Color>[
                  theme.colorScheme.primary.withValues(alpha: 0.20),
                  theme.colorScheme.surface,
                ]
              : <Color>[
                  AppColors.primaryLight.withValues(alpha: 0.8),
                  AppColors.surface,
                ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'זה היומן האישי שלך לשידוכים',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'כאן נשמרים החברים {שאתה חושב|שאת חושבת} עליהם, הרעיונות שנפתחו '
                    'ומה קרה איתם. מתחילים בהוספת כמה חברים — כל אחד שנוסף '
                    'פותח כיוון.'
                .forGender(context.userGender),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAddPeople,
              style: FilledButton.styleFrom(
                backgroundColor: _lead(theme),
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.person_add_alt, size: 19),
              label: const Text('הוספת החברים הראשונים'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The staged target: ten, then twenty-five, then fifty, then a hundred.
class HomeMilestoneCard extends StatelessWidget {
  const HomeMilestoneCard({super.key, required this.milestone});

  final HomeMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = _lead(theme);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.flag_outlined, size: 18, color: lead),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  milestone.target == null
                      ? 'המאגר שלך'
                      : '${milestone.friends} מתוך ${milestone.target} חברים',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: milestone.progress,
              minHeight: 7,
              backgroundColor: theme.colorScheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation<Color>(lead),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            milestone.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The nudge towards a first proposal.
///
/// Only ever shown to someone who has friends but has never opened an idea —
/// which is the one moment the app can say something genuinely useful about it.
/// It disappears the moment the first proposal exists and never returns, so it
/// cannot become another permanent box asking to be dealt with.
class HomeFirstIdeaCard extends StatelessWidget {
  const HomeFirstIdeaCard({
    super.key,
    required this.friends,
    required this.onOpenIdea,
  });

  final int friends;
  final VoidCallback onOpenIdea;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = _lead(theme);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.favorite_border, size: 18, color: lead),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'עוד לא פתחת רעיון',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'יש כבר $friends חברים במאגר. אולי שניים מהם מתאימים זה לזה — '
            'רעיון ראשון הוא רק מחשבה שנשמרת.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onOpenIdea,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('פתיחת רעיון ראשון'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bulk-import offer. Prominent but plainly secondary to adding from the
/// address book, and gone from this screen once the database is large enough
/// that it is no longer the fastest way to grow.
class HomeImportInvite extends StatelessWidget {
  const HomeImportInvite({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = _lead(theme);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: lead.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: lead.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.auto_awesome, color: lead, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'יש לך מאגר אישי בקבוצת ווטסאפ או באקסל? ייבא אותו באמצעות '
                  'כלי ה-AI',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              HomeArrowButton(
                background: lead.withValues(alpha: 0.12),
                foreground: lead,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "עוצרים רגע לחשוב על החברים" — the invitation into the continuous
/// think-about-someone view, and the warmest thing on the home screen.
///
/// **A card with a picture in it, not a banner with an icon on it.** It was one
/// tinted strip with a small glyph and the word "מתחילים" — legible, and
/// completely interchangeable with the six other tinted strips the page has had
/// at one time or another. This is the one block on the home screen that is an
/// invitation rather than a control, so it is allowed to look like one: painted
/// paper, a title, and a real button.
///
/// **Its own illustration: somebody thinking, over a cup of coffee.** It used
/// to reuse the notepad from "הוספת רעיון", and then a pair of profile
/// cards — but a pair of cards is what a *match* looks like, and this block is
/// not about a pair, it is about the minute before one. A figure sitting with a
/// coffee and a thought rising off it is what the block actually asks for, and
/// it is drawn in the same warm paper-and-copper palette as the photographs
/// beside it so the page still looks drawn rather than assembled.
///
/// **Kept short, and one line high in the title.** Title, button, picture —
/// nothing else, the title scaled to stay on a single line rather than wrapping
/// into a two-line heading that pushed the card taller than anything around it.
/// The sentence under the title and the heart in the corner are both gone for
/// the same reason: on a page whose whole job is to get out of the way, this
/// block is an invitation, not a poster.
///
/// It drops the picture entirely below 300px of card or above 1.3x text, where
/// keeping it would leave the title three words wide.
class HomeThinkBanner extends StatelessWidget {
  const HomeThinkBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark
        ? AppColors.secondaryDarkDm
        : AppColors.secondaryInk;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool showPicture =
            constraints.maxWidth >= 300 && textScale <= 1.3;
        // Held down deliberately: the button under the title has to keep
        // "על מי חושבים עכשיו?" on one line, and every pixel the picture takes
        // comes out of the column that has to hold it. It is also what sets the
        // height of the whole block now that there is no sentence under the
        // title, so it stays close to the height of the two lines beside it.
        final double pictureWidth = (constraints.maxWidth * 0.22).clamp(
          64.0,
          84.0,
        );

        return Material(
          color: dark ? theme.colorScheme.surface : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                // No outline. The wash is already a different colour from the
                // page, which is all a block needs to be told apart from it —
                // and a tinted fill inside a tinted line reads as a component
                // with a frame drawn round it rather than as a piece of the
                // page.
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topEnd,
                  end: AlignmentDirectional.bottomStart,
                  colors: <Color>[
                    accent.withValues(alpha: dark ? 0.15 : 0.08),
                    dark ? theme.colorScheme.surface : AppColors.surface,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // A statement, not a question. The block is an
                          // open door, and a question mark on the home screen
                          // asks for an answer the matchmaker did not come
                          // here to give.
                          //
                          // Held to exactly the size of "רעיונות שהמאגר מציע
                          // לך" under it rather than scaled down to one line
                          // — see [HomeBannerTitle]. Two blocks that sit one
                          // above the other cannot be headed at two sizes,
                          // and which of them came out larger depended on how
                          // much room the picture beside it happened to
                          // leave.
                          HomeBannerTitle(
                            text: 'עוצרים רגע לחשוב על החברים',
                            color: dark ? theme.colorScheme.onSurface : accent,
                          ),
                          const SizedBox(height: 8),
                          // Centred in its own column rather than pinned to
                          // the reading edge: the invitation is the middle of
                          // the block, and a pill hard against the right edge
                          // under a two-line heading reads as a footnote to
                          // it.
                          Align(
                            alignment: Alignment.center,
                            child: FilledButton(
                              onPressed: onTap,
                              // Scaled down rather than wrapped. The
                              // label is a question, and a question
                              // broken across two lines inside a pill
                              // reads as two half-sentences; at 1.5x
                              // system text on a 320px phone there is no
                              // room for it at full size and no room to
                              // wrap it either. No glyph beside it either:
                              // the picture on the card already says what
                              // this is, and the symbol only made the pill
                              // wider.
                              style: FilledButton.styleFrom(
                                backgroundColor: dark
                                    ? AppColors.secondaryDarkDm
                                    : AppColors.secondary,
                                foregroundColor: dark
                                    ? AppColors.onSecondary
                                    : AppColors.surface,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: theme.textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('על מי חושבים עכשיו?', maxLines: 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showPicture) ...<Widget>[
                      const SizedBox(width: 10),
                      _ThinkingArt(size: pictureWidth, accent: accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Somebody sitting with a coffee, thinking — the picture for
/// "עוצרים רגע לחשוב על החברים".
///
/// **Drawn, not photographed.** Every other picture on this page is a painted
/// asset, and there is no painted asset for *stopping to think*. Drawing it
/// here costs nothing to ship, follows the text size and the theme on its own,
/// and keeps the block to the palette of the photographs next to it — warm
/// paper, a copper line, the stone blue of the app — so it reads as one more
/// piece of the same vintage set rather than as an icon that wandered in.
///
/// **A person and a cup, not a pair of profile cards.** Two cards with a heart
/// between them is what a *match* looks like, and this block is about the
/// minute before one: one person, chin on hand, over a coffee that is still
/// steaming. Everything is one stroke weight and flat fills — the tell of a
/// generated illustration is fussy shading and too many little flourishes, so
/// there are five shapes here and no gradients.
class _ThinkingArt extends StatelessWidget {
  const _ThinkingArt({required this.size, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ThinkingPainter(
          paper: dark
              ? Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.07),
                  theme.colorScheme.surface,
                )
              : AppColors.surface,
          line: accent.withValues(alpha: dark ? 0.55 : 0.45),
          figure: dark
              ? AppColors.primaryDarkDm.withValues(alpha: 0.85)
              : AppColors.primaryDark,
          brew: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
        ),
        // The picture is decoration for a block whose title already says what
        // it is; a screen reader announcing "a person with a cup of coffee"
        // here would only be reading the wallpaper out loud.
        isComplex: false,
      ),
    );
  }
}

class _ThinkingPainter extends CustomPainter {
  const _ThinkingPainter({
    required this.paper,
    required this.line,
    required this.figure,
    required this.brew,
  });

  /// The face of the cup.
  final Color paper;

  /// The drawn outline — one weight for the whole picture, the way the painted
  /// assets beside it are outlined.
  final Color line;

  /// The person.
  final Color figure;

  /// The coffee, and the thought rising off it.
  final Color brew;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 100;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line;

    _thought(canvas, u: u, stroke: stroke);
    _person(canvas, u: u, stroke: stroke);
    _table(canvas, u: u);
    _cup(canvas, u: u, stroke: stroke);
  }

  /// Two small rings drifting up off the head. The one piece of the picture
  /// that says *thinking* rather than *sitting*.
  void _thought(Canvas canvas, {required double u, required Paint stroke}) {
    canvas.drawCircle(Offset(14 * u, 20 * u), 4.5 * u, stroke);
    canvas.drawCircle(Offset(6 * u, 9 * u), 2.4 * u, stroke);
  }

  /// A head and a pair of shoulders, outlined.
  ///
  /// **Two shapes and no arm.** The obvious drawing of somebody thinking is
  /// chin-on-hand — and at 80 pixels, in one flat colour, a hand touching a
  /// chin is a lump: every attempt at it read as a blob with a bump. The
  /// thought rising off the head says *thinking* on its own, and two clean
  /// shapes beside a cup of coffee is a picture rather than a puzzle.
  ///
  /// Outlined in the same copper as the cup, so the whole illustration is one
  /// weight of line around flat fills — the look of the painted assets beside
  /// it, and the opposite of a soft-shaded generated image.
  void _person(Canvas canvas, {required double u, required Paint stroke}) {
    final Paint body = Paint()..color = figure;

    // Shoulders, cut off by the table rather than floating above it. The
    // corners are rounded well short of a half-circle: a dome reads as a hill,
    // and what makes a bust a person is a short flat top with a shoulder
    // falling away on each side.
    final RRect torso = RRect.fromLTRBAndCorners(
      8 * u,
      42 * u,
      58 * u,
      92 * u,
      topLeft: Radius.circular(16 * u),
      topRight: Radius.circular(16 * u),
    );
    canvas.drawRRect(torso, body);
    canvas.drawRRect(torso, stroke);

    // The head sits *on* the shoulders rather than above them — a gap between
    // the two is the difference between a person and a balloon. The outline is
    // what keeps the two shapes apart where they meet.
    canvas.drawCircle(Offset(33 * u, 26 * u), 13 * u, body);
    canvas.drawCircle(Offset(33 * u, 26 * u), 13 * u, stroke);
  }

  /// The tabletop: one bar across the bottom, drawn after the figure so the
  /// person sits behind it.
  void _table(Canvas canvas, {required double u}) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2 * u, 84 * u, 96 * u, 6 * u),
        Radius.circular(3 * u),
      ),
      Paint()..color = brew.withValues(alpha: 0.7),
    );
  }

  /// The cup on the table, with two curls of steam.
  void _cup(Canvas canvas, {required double u, required Paint stroke}) {
    // A tapered body — wider at the rim than at the base, which is the whole
    // difference between a cup and a box.
    final Path cup = Path()
      ..moveTo(60 * u, 58 * u)
      ..lineTo(86 * u, 58 * u)
      ..lineTo(82.5 * u, 80 * u)
      ..quadraticBezierTo(82 * u, 84 * u, 78.5 * u, 84 * u)
      ..lineTo(67.5 * u, 84 * u)
      ..quadraticBezierTo(64 * u, 84 * u, 63.5 * u, 80 * u)
      ..close();
    canvas.drawPath(cup, Paint()..color = paper);
    canvas.drawPath(cup, stroke);

    // The coffee itself, a band just under the rim.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(63 * u, 60 * u, 20 * u, 5.5 * u),
        Radius.circular(2.5 * u),
      ),
      Paint()..color = brew,
    );

    // The handle, on the outer side so it never crowds the figure.
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(87 * u, 68 * u),
        width: 15 * u,
        height: 17 * u,
      ),
      -1.3,
      2.6,
      false,
      stroke,
    );

    // Steam: two short waves, the second shorter, so it reads as rising rather
    // than as a pair of brackets.
    final Paint wisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * u
      ..strokeCap = StrokeCap.round
      ..color = brew.withValues(alpha: 0.65);
    canvas.drawPath(
      Path()
        ..moveTo(71 * u, 52 * u)
        ..quadraticBezierTo(67 * u, 45 * u, 71 * u, 38 * u),
      wisp,
    );
    canvas.drawPath(
      Path()
        ..moveTo(80 * u, 52 * u)
        ..quadraticBezierTo(76 * u, 46 * u, 80 * u, 41 * u),
      wisp,
    );
  }

  @override
  bool shouldRepaint(_ThinkingPainter old) {
    return old.paper != paper ||
        old.line != line ||
        old.figure != figure ||
        old.brew != brew;
  }
}
