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
/// **Its own illustration, no longer the notepad.** It used to reuse the
/// picture from "הוספת רעיון", and on a page where that card sits a few
/// centimetres below it the two read as the same thing twice. What this block
/// asks for is not writing something down — it is holding people in mind — so
/// it gets people: two little profile cards leaning on each other with a heart
/// between them, drawn in the same warm paper-and-copper palette as the
/// photographs beside it so the page still looks drawn rather than assembled.
///
/// **Kept short.** Title, button, picture — nothing else. The sentence under
/// the title was true and cost the block a third of its height on a page whose
/// whole job is to get out of the way, so it is gone.
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
                border: Border.all(color: accent.withValues(alpha: 0.20)),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topEnd,
                  end: AlignmentDirectional.bottomStart,
                  colors: <Color>[
                    accent.withValues(alpha: dark ? 0.15 : 0.08),
                    dark ? theme.colorScheme.surface : AppColors.surface,
                  ],
                ),
              ),
              child: Stack(
                children: <Widget>[
                  // One outlined heart in the far corner. The card's only
                  // decoration, and the reason it reads as paper somebody wrote
                  // on rather than as a panel.
                  PositionedDirectional(
                    top: 8,
                    end: 10,
                    child: Icon(
                      Icons.favorite_border_rounded,
                      size: 15,
                      color: accent.withValues(alpha: 0.35),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                // A statement, not a question. The block is an
                                // open door, and a question mark on the home
                                // screen asks for an answer the matchmaker did
                                // not come here to give.
                                'עוצרים רגע לחשוב על החברים',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                  color: dark
                                      ? theme.colorScheme.onSurface
                                      : accent,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: FilledButton.icon(
                                  onPressed: onTap,
                                  icon: const Icon(
                                    Icons.people_alt_outlined,
                                    size: 17,
                                  ),
                                  // Scaled down rather than wrapped. The
                                  // label is a question, and a question
                                  // broken across two lines inside a pill
                                  // reads as two half-sentences; at 1.5x
                                  // system text on a 320px phone there is no
                                  // room for it at full size and no room to
                                  // wrap it either.
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'על מי חושבים עכשיו?',
                                      maxLines: 1,
                                    ),
                                  ),
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
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showPicture) ...<Widget>[
                          const SizedBox(width: 10),
                          _ThinkPeopleArt(size: pictureWidth, accent: accent),
                        ],
                      ],
                    ),
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

/// Two little profile cards with a heart between them — the picture for
/// "עוצרים רגע לחשוב על החברים".
///
/// **Drawn, not photographed.** Every other picture on this page is a painted
/// asset, and there is no painted asset for *thinking about people*; the two
/// that exist are a notepad and a group of friends, and both already belong to
/// a card of their own further down the page. Drawing it here costs nothing to
/// ship, follows the text size and the theme on its own, and keeps the block to
/// the palette of the photographs next to it — warm paper, a copper line, the
/// stone blue of the app — so it reads as one more piece of the same vintage
/// set rather than as an icon that wandered in.
class _ThinkPeopleArt extends StatelessWidget {
  const _ThinkPeopleArt({required this.size, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ThinkPeoplePainter(
          paper: dark
              ? Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.07),
                  theme.colorScheme.surface,
                )
              : AppColors.surface,
          wash: dark
              ? AppColors.primaryDarkDm.withValues(alpha: 0.22)
              : AppColors.softBlue,
          line: accent.withValues(alpha: dark ? 0.55 : 0.45),
          ink: dark
              ? AppColors.secondaryDarkDm.withValues(alpha: 0.85)
              : AppColors.secondary,
          heart: dark ? AppColors.femaleAccentDm : AppColors.femaleAccent,
        ),
        // The picture is decoration for a block whose title already says what
        // it is; a screen reader announcing "two profile cards" here would only
        // be reading the wallpaper out loud.
        isComplex: false,
      ),
    );
  }
}

class _ThinkPeoplePainter extends CustomPainter {
  const _ThinkPeoplePainter({
    required this.paper,
    required this.wash,
    required this.line,
    required this.ink,
    required this.heart,
  });

  /// The face of a card.
  final Color paper;

  /// The tint on the card behind, so the two do not merge into one shape.
  final Color wash;

  /// The drawn outline — one weight for the whole picture, the way the painted
  /// assets beside it are outlined.
  final Color line;

  /// The name bars and the shoulders.
  final Color ink;

  final Color heart;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 100;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * u
      ..strokeJoin = StrokeJoin.round
      ..color = line;

    // The card behind, leaning one way.
    _card(
      canvas,
      u: u,
      center: Offset(38 * u, 46 * u),
      turns: -0.055,
      fill: wash,
      stroke: stroke,
      ink: ink.withValues(alpha: 0.35),
    );
    // The card in front, leaning the other, overlapping it by a third — two
    // people standing close enough to be one thought.
    _card(
      canvas,
      u: u,
      center: Offset(62 * u, 54 * u),
      turns: 0.05,
      fill: paper,
      stroke: stroke,
      ink: ink.withValues(alpha: 0.7),
    );
    _heart(canvas, u: u, center: Offset(50 * u, 22 * u));
  }

  /// One profile card: a rounded rectangle, a head, shoulders, and two bars
  /// where a name would be.
  void _card(
    Canvas canvas, {
    required double u,
    required Offset center,
    required double turns,
    required Color fill,
    required Paint stroke,
    required Color ink,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turns * 3.14159 * 2);

    final Rect rect = Rect.fromCenter(
      center: Offset.zero,
      width: 46 * u,
      height: 58 * u,
    );
    final RRect card = RRect.fromRectAndRadius(rect, Radius.circular(9 * u));
    canvas.drawRRect(card, Paint()..color = fill);
    canvas.drawRRect(card, stroke);

    // Head and shoulders, the way a passport photo sits on a card.
    final Paint figure = Paint()..color = ink;
    canvas.drawCircle(Offset(0, -14 * u), 8 * u, figure);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(0, 8 * u), width: 30 * u, height: 30 * u),
      3.14159,
      3.14159,
      true,
      figure,
    );

    // Two bars for the name, the lower one short, as a real name reads.
    final Paint bar = Paint()..color = ink.withValues(alpha: 0.45);
    for (final ({double width, double y}) row in <({double width, double y})>[
      (width: 26 * u, y: 17 * u),
      (width: 16 * u, y: 24 * u),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, row.y),
            width: row.width,
            height: 4 * u,
          ),
          Radius.circular(2 * u),
        ),
        bar,
      );
    }
    canvas.restore();
  }

  /// The small heart over the seam between the two cards — the only reason
  /// they are next to each other.
  void _heart(Canvas canvas, {required double u, required Offset center}) {
    final Path path = Path()
      ..moveTo(center.dx, center.dy + 9 * u)
      ..cubicTo(
        center.dx - 13 * u,
        center.dy,
        center.dx - 8 * u,
        center.dy - 11 * u,
        center.dx,
        center.dy - 4 * u,
      )
      ..cubicTo(
        center.dx + 8 * u,
        center.dy - 11 * u,
        center.dx + 13 * u,
        center.dy,
        center.dx,
        center.dy + 9 * u,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = heart);
  }

  @override
  bool shouldRepaint(_ThinkPeoplePainter old) {
    return old.paper != paper ||
        old.wash != wash ||
        old.line != line ||
        old.ink != ink ||
        old.heart != heart;
  }
}
