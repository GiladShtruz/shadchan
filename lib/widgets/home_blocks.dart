import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_next_actions.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The blocks introduced by the home-screen rework: the ranked next actions,
/// the open ideas drawn without boxes, the activity summary and the community
/// tip carousel.
///
/// They share one rule with the rest of the page — a block with nothing to say
/// is not drawn — and one visual rule: outside the board, the tip and the
/// "עוצרים רגע" banner, nothing here introduces a new card shape.

Color _leadTone(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.primary
    : AppColors.primaryDark;

// --- הפעולות הבאות שלך ------------------------------------------------------

/// The ranked recommendations, as one horizontally scrolling row.
///
/// **A scroll rather than a "פעולות נוספות" button.** The button showed three
/// at a time and swapped the whole trio, which meant reaching the tenth action
/// took three taps and no sense of where it sat in the list. A row that is
/// dragged runs an eye past a dozen actions in one gesture, which is what this
/// list is for — it is a place to scan, not a queue to work through in order.
///
/// Every card is exactly the same box, and a compact one. The reason line is
/// clamped rather than allowed to set the height: a row whose cards are three
/// different heights reads as three different kinds of thing, and a card sized
/// for the longest sentence in the database leaves every other card half empty.
class HomeNextActionsRow extends StatelessWidget {
  const HomeNextActionsRow({
    super.key,
    required this.actions,
    required this.onOpen,
  });

  final List<HomeNextAction> actions;
  final void Function(HomeNextAction action) onOpen;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const HomeSectionHeader(title: 'הפעולות הבאות שלך'),
        SizedBox(
          height: homeScaled(context, HomeConfig.nextActionCardHeight),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            // The end padding is deliberately smaller than a card, so the next
            // one always peeks in from the edge. That slice is the only thing
            // telling the user the row moves, and it replaces the button.
            padding: EdgeInsetsDirectional.fromSTEB(
              homeHorizontalInset(context),
              0,
              28,
              0,
            ),
            itemCount: actions.length,
            separatorBuilder: (_, _) => SizedBox(width: homeCardGap(context)),
            itemBuilder: (BuildContext context, int index) => _NextActionCard(
              action: actions[index],
              onTap: () => onOpen(actions[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.action, required this.onTap});

  final HomeNextAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool urgent = action.kind == HomeActionKind.reminderDue;
    final Color accent = urgent ? AppColors.secondary : _leadTone(theme);

    final bool dark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: homeIsNarrow(context) ? 134 : HomeConfig.nextActionCardWidth,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: urgent
                    ? accent.withValues(alpha: 0.45)
                    : accent.withValues(alpha: 0.20),
              ),
              // The same wash "רעיונות שהמאגר מציע" and the activity panel
              // wear — a card that belongs to this page rather than a plain
              // white rectangle, and quiet enough that twelve of them in a row
              // still read as one calm strip. Urgent cards take it a shade
              // deeper; that, and the border, are the whole difference.
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  accent.withValues(
                    alpha: urgent
                        ? (dark ? 0.20 : 0.13)
                        : (dark ? 0.13 : 0.065),
                  ),
                  theme.colorScheme.surface,
                ],
              ),
            ),
            child: Column(
              children: <Widget>[
                // A hairline of the card's own tone along the top edge. It is
                // what keeps the row from reading as a queue of identical
                // boxes without any of them raising its voice.
                Container(height: 3, color: accent.withValues(alpha: 0.55)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        if (action.isPrompt)
                          _PromptBadge(icon: action.kind.icon, accent: accent)
                        else if (action.isPerson)
                          HomeCardAvatar(person: action.person, radius: 16)
                        else
                          HomeCardCoupleAvatars(
                            personA: action.personA,
                            personB: action.personB,
                            radius: 12,
                          ),
                        const SizedBox(height: 5),
                        Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Two lines and no more: the card's height is fixed,
                        // so a long sentence is cut rather than allowed to
                        // push the box.
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(action.kind.icon, size: 11, color: accent),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  action.reason,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    height: 1.3,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stands where a face would go on the two habit prompts, which are about the
/// matchmaker rather than about anybody in the database.
class _PromptBadge extends StatelessWidget {
  const _PromptBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}

// --- רעיונות פתוחים ---------------------------------------------------------

/// An open proposal on the wave, in the same frameless language the suggestion
/// circles used: the two faces, the names and the status, with no white box of
/// its own. It is still plainly tappable — the ink ripple covers the whole
/// group and the status pill carries the affordance colour.
class HomeOpenIdeaBubble extends StatelessWidget {
  const HomeOpenIdeaBubble({
    super.key,
    required this.personA,
    required this.personB,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.onTap,
    this.alerting = false,
  });

  final Person? personA;
  final Person? personB;
  final String title;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;

  /// A reminder on this proposal has come due.
  final bool alerting;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: homeIsNarrow(context) ? 132 : 146,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: dark
                          ? theme.colorScheme.surface
                          : AppColors.surface.withValues(alpha: 0.9),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: HomeCardCoupleAvatars(
                      personA: personA,
                      personB: personB,
                      radius: 21,
                      ringColor: dark
                          ? theme.colorScheme.surface
                          : AppColors.surface,
                    ),
                  ),
                  if (alerting)
                    const PositionedDirectional(
                      top: -4,
                      start: -4,
                      child: HomeAlertBadge(),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              HomeCardFooter(label: status, color: statusColor, tinted: true),
            ],
          ),
        ),
      ),
    );
  }
}

// --- הפעילות שלך ------------------------------------------------------------

/// All three windows at once: this week, this Hebrew month, and everything ever.
///
/// **Not tabs.** The card used to carry three chips that swapped one number
/// between them, which meant the only way to know whether a quiet week sat
/// inside a good year was to tap twice and hold both figures in your head. Seen
/// together they say something none of them says alone, and the comparison is
/// the encouraging part: "3 this week" reads very differently next to "412 ever".
///
/// A little warmer than the rest of the page — a soft tinted ground and one
/// short line of encouragement — and no further. The breakdown by kind of
/// action, the chart and the months all live one tap away, on a screen someone
/// opened *to look at numbers*.
class HomeActivityPanel extends StatelessWidget {
  const HomeActivityPanel({
    super.key,
    required this.week,
    required this.month,
    required this.allTime,
    required this.onOpen,
  });

  final int week;
  final int month;
  final int allTime;
  final VoidCallback onOpen;

  /// One short line, and never a comparative or a reproach. A quiet week is
  /// answered with an invitation rather than a tally, because there is no
  /// amount of matchmaking that counts as "not enough".
  String get _encouragement =>
      week > 0 ? 'עוד פעולה וניפגש בחופה' : 'כל פעולה מקדמת עוד רעיון';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = _leadTone(theme);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Ink(
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
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'הפעולות שעשית בשביל החברים שלך',
                      // Three, not two: the heading is a whole sentence now,
                      // and at 1.5× system text on a 320px phone it needs the
                      // third line rather than an ellipsis through it.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _ActivityFigure(
                        label: 'השבוע',
                        value: week,
                        accent: lead,
                      ),
                    ),
                    _FigureDivider(color: lead.withValues(alpha: 0.18)),
                    Expanded(
                      child: _ActivityFigure(
                        label: 'החודש',
                        value: month,
                        accent: lead,
                      ),
                    ),
                    _FigureDivider(color: lead.withValues(alpha: 0.18)),
                    Expanded(
                      child: _ActivityFigure(
                        label: 'כל הזמנים',
                        value: allTime,
                        accent: lead,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: lead.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _encouragement,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: lead,
                      ),
                    ),
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

/// One of the three figures: the number over its window's name.
class _ActivityFigure extends StatelessWidget {
  const _ActivityFigure({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // A four-figure all-time count at 1.5× system text is wider than a
        // third of a 320px phone, so the number scales down inside its column
        // rather than wrapping or clipping.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value',
            maxLines: 1,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _FigureDivider extends StatelessWidget {
  const _FigureDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: color,
    );
  }
}

// --- טיפ לשדכן --------------------------------------------------------------

/// One tip, and who wrote it.
class HomeTip {
  const HomeTip({required this.text, this.author});

  final String text;

  /// The matchmaker who contributed it — first name and surname. Null for the
  /// tips that ship with the app, which have no author to credit.
  final String? author;
}

/// The closing block: a tip, swiped through in an endless ring.
///
/// Endless in the literal sense — the page view starts deep inside its range
/// and wraps by modulo, so there is no first tip to be stuck before and no last
/// tip to run out of. It advances itself every seven seconds; a manual swipe
/// restarts that clock rather than fighting it, so the card never moves under a
/// finger that is using it.
class HomeTipCarousel extends StatefulWidget {
  const HomeTipCarousel({
    super.key,
    required this.tips,
    this.userGender,
    this.onAddTip,
  });

  final List<HomeTip> tips;

  /// The matchmaker's own gender, so the heading reads שדכן or שדכנית.
  final Gender? userGender;

  /// Route into contributing one. It is offered at the foot of the block as
  /// well as in the settings: reading somebody else's tip is the moment a
  /// matchmaker is most likely to think of their own.
  final VoidCallback? onAddTip;

  @override
  State<HomeTipCarousel> createState() => _HomeTipCarouselState();
}

class _HomeTipCarouselState extends State<HomeTipCarousel> {
  /// Long enough that nobody swipes to the end of it in one sitting.
  static const int _origin = 10000;
  static const Duration _dwell = Duration(seconds: 7);

  late final PageController _controller = PageController(initialPage: _origin);
  Timer? _timer;
  int _page = _origin;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant HomeTipCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tips.length != oldWidget.tips.length) {
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.tips.length < 2) {
      return;
    }
    _timer = Timer.periodic(_dwell, (_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      _controller.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? _tipInkDm : _tipInk;
    final List<HomeTip> tips = widget.tips;
    if (tips.isEmpty) {
      return const SizedBox.shrink();
    }

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
          // Exactly one decorative mark, low in the corner and very faint. The
          // scattered leaf and heart the previous version carried competed with
          // the sentence, which is the only thing here worth reading.
          PositionedDirectional(
            end: -10,
            bottom: -14,
            child: Icon(
              Icons.eco_rounded,
              size: 78,
              color: ink.withValues(alpha: dark ? 0.06 : 0.07),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'טיפ {לשדכן|לשדכנית}'.forGender(widget.userGender),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                // A fixed height so the block does not jump between a short tip
                // and a long one as the pages turn.
                SizedBox(
                  height: homeScaled(context, 96),
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (int page) {
                      setState(() => _page = page);
                      // A manual swipe should buy the full dwell time again.
                      _restartTimer();
                    },
                    itemBuilder: (BuildContext context, int page) {
                      final HomeTip tip = tips[page % tips.length];
                      return _TipPage(tip: tip, ink: ink);
                    },
                  ),
                ),
                // A short ring gets dots. A long one does not: forty dots say
                // nothing except that there are forty of something.
                if (tips.length > 1 && tips.length <= 8) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < tips.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page % tips.length ? 14 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: ink.withValues(
                              alpha: i == _page % tips.length ? 0.8 : 0.22,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ],
                if (widget.onAddTip != null) ...<Widget>[
                  const SizedBox(height: 4),
                  // Under the tip rather than beside the heading: it answers
                  // the tip that was just read, and a heading is not the place
                  // to put a thing to do.
                  Center(
                    child: TextButton.icon(
                      onPressed: widget.onAddTip,
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        visualDensity: VisualDensity.compact,
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: const Text('שליחת טיפ'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipPage extends StatelessWidget {
  const _TipPage({required this.tip, required this.ink});

  final HomeTip tip;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? author = tip.author?.trim();

    // Centred, not ragged against the reading edge: the block is one sentence
    // sitting alone on a card, and a short tip pinned to the right of a wide
    // panel reads as a stray line rather than as the thing the card is for.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Text(
            tip.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (author != null && author.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ink.withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}

const Color _tipInk = Color(0xFF5C84A3);
const Color _tipInkDm = Color(0xFF9DBED6);
const Color _tipPaper = Color(0xFFFBF5EA);
