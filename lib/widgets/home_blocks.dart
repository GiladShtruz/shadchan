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

/// Three ranked recommendations at a time, with a control that swaps the whole
/// trio for the next three.
///
/// Every card is exactly the same box. The reason line is clamped rather than
/// allowed to set the height, because a row whose cards are three different
/// heights reads as three different kinds of thing — and they are not, they are
/// one list in priority order.
class HomeNextActionsRow extends StatefulWidget {
  const HomeNextActionsRow({
    super.key,
    required this.actions,
    required this.onOpen,
  });

  final List<HomeNextAction> actions;
  final void Function(HomeNextAction action) onOpen;

  @override
  State<HomeNextActionsRow> createState() => _HomeNextActionsRowState();
}

class _HomeNextActionsRowState extends State<HomeNextActionsRow> {
  int _page = 0;

  int get _pageCount =>
      (widget.actions.length / HomeNextActions.pageSize).ceil();

  @override
  void didUpdateWidget(covariant HomeNextActionsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Acting on something shortens the list; the page must not point past it.
    if (_page >= _pageCount) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int start = _page * HomeNextActions.pageSize;
    final List<HomeNextAction> shown = widget.actions
        .skip(start)
        .take(HomeNextActions.pageSize)
        .toList();
    final bool hasMore = _pageCount > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const HomeSectionHeader(
          title: 'הפעולות הבאות שלך',
          icon: Icons.checklist_rtl_rounded,
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: homeHorizontalInset(context),
          ),
          child: SizedBox(
            height: HomeConfig.nextActionCardHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < HomeNextActions.pageSize; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: homeCardGap(context)),
                  // The empty slots keep the three columns the same width on
                  // the last, partly filled page.
                  Expanded(
                    child: i < shown.length
                        ? _NextActionCard(
                            action: shown[i],
                            onTap: () => widget.onOpen(shown[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasMore)
          Padding(
            padding: EdgeInsets.fromLTRB(
              homeHorizontalInset(context),
              6,
              homeHorizontalInset(context),
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                // Wrapping back to the start rather than stopping: the list is
                // a ring, so the control never becomes a dead button.
                onPressed: () =>
                    setState(() => _page = (_page + 1) % _pageCount),
                style: TextButton.styleFrom(
                  foregroundColor: _leadTone(theme),
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // Material mirrors chevrons in RTL, so `chevron_right` draws
                // the left-pointing "onward" arrow this page reads with.
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('פעולות נוספות'),
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

    return Material(
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
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (action.isPerson)
                HomeCardAvatar(person: action.person, radius: 20)
              else
                HomeCardCoupleAvatars(
                  personA: action.personA,
                  personB: action.personB,
                  radius: 14,
                ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 5),
              // Two lines and no more: the card's height is fixed, so a long
              // sentence is cut rather than allowed to push the box.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(action.kind.icon, size: 12, color: accent),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        action.reason,
                        maxLines: 3,
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

/// Which window "הפעילות שלך" is showing.
enum HomeActivityRange {
  week('השבוע'),
  month('החודש'),
  allTime('כל הזמנים');

  const HomeActivityRange(this.label);

  final String label;
}

/// One total, for the window the matchmaker picked.
///
/// Deliberately a single number. The breakdown by kind of action, the chart and
/// the months all live one tap away, on a screen someone opened *to look at
/// numbers* — putting them here would turn a workspace back into a dashboard.
class HomeActivityPanel extends StatelessWidget {
  const HomeActivityPanel({
    super.key,
    required this.range,
    required this.total,
    required this.onRangeChanged,
    required this.onOpen,
  });

  final HomeActivityRange range;
  final int total;
  final ValueChanged<HomeActivityRange> onRangeChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.insights_rounded, size: 18, color: lead),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'הפעילות שלך',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // The segments are their own tap targets inside a card that is
              // itself tappable, so picking a window does not open the screen.
              Row(
                children: <Widget>[
                  for (final HomeActivityRange option
                      in HomeActivityRange.values) ...<Widget>[
                    if (option != HomeActivityRange.values.first)
                      const SizedBox(width: 6),
                    Expanded(
                      child: _RangeChip(
                        label: option.label,
                        selected: option == range,
                        onTap: () => onRangeChanged(option),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // A four-figure all-time count at 1.5× system text is wider than
              // a 320px phone; the line scales down as a unit rather than
              // wrapping the word onto its own row or clipping the number.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '$total',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: lead,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      total == 1 ? 'פעולה' : 'פעולות',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = _leadTone(theme);

    return Material(
      color: selected ? lead.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? lead.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? lead : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
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

  /// Optional route into contributing one. Null on the home screen — tips are
  /// written from the settings, not from here.
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
                Row(
                  children: <Widget>[
                    Icon(Icons.lightbulb_rounded, size: 20, color: ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'טיפ {לשדכן|לשדכנית}'.forGender(widget.userGender),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                    ),
                    if (widget.onAddTip != null)
                      IconButton(
                        tooltip: 'הוספת טיפ',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onAddTip,
                        icon: Icon(Icons.add_circle_outline, color: ink),
                      ),
                  ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Text(
            tip.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
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
