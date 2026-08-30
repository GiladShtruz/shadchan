import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The blocks introduced by the home-screen rework: the open ideas drawn
/// without boxes, and the community tip carousel.
///
/// "הפעולות הבאות שלך" used to live here too — a ranked, sideways-scrolling
/// queue of what the app thought was most worth doing. It is gone: the home
/// screen already carries הלוח שלי, which every open proposal now lands on by
/// itself, and two competing answers to "what should I do next" is one answer
/// too many.
///
/// They share one rule with the rest of the page — a block with nothing to say
/// is not drawn — and one visual rule: outside the board, the tip and the
/// "עוצרים רגע" banner, nothing here introduces a new card shape.

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
///
/// **The card is sized to its sentence.** It used to stand a third taller than
/// anything it ever held, which on a page of otherwise tight blocks read as an
/// empty box with a line of text floating in it. The frame is now as small as a
/// two-line tip needs, and what fills the space that is left is warmth rather
/// than air: a soft coloured wash in the corner, the paper tone, the bulb in
/// its disc.
///
/// **"לשליחת טיפ" is outside the frame**, under it, in footnote type. Inside,
/// it was the last thing the eye landed on and turned a card for reading into a
/// card asking for something.
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

    final Widget card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        // Deeper than it was, but still a hairline: a fractional border width
        // leaves the page inside a fractional number of pixels wide, and the
        // carousel's viewport then rounds its way into building a second page
        // it never shows.
        border: Border.all(color: ink.withValues(alpha: dark ? 0.38 : 0.26)),
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
            color: ink.withValues(alpha: dark ? 0.10 : 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          // The warm corner. Nothing is written on it and nothing sits inside
          // it — it is there so the card reads as a small, friendly piece of
          // paper rather than as an outlined rectangle with a sentence in it.
          PositionedDirectional(
            top: -26,
            start: -22,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(
                  alpha: dark ? 0.10 : 0.09,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The mark leads the block rather than trailing the
                // sentence. It used to be an emoji appended to the tip text,
                // which is the one place a mark cannot be relied on: a device
                // without a colour emoji font drew a blank box at the end of
                // every tip, and even where it rendered it read as a typo in
                // somebody's sentence. In its own tinted disc it is part of
                // the card's furniture — the thing that says "this box is
                // advice" before a word of it is read.
                //
                // The bulb it used to be is the app's own drawing now: a heart
                // beside a pencil, which is what a matchmaker's tip actually
                // is. Recoloured at draw time so it wears the card's ink in
                // either theme — see [HomeLineArt].
                Row(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _tipDisc(theme, ink),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: HomeLineArt(
                          asset: 'assets/shadchan-tip.png',
                          ink: ink,
                          paper: _tipDisc(theme, ink),
                        ),
                      ),
                    ),
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
                    // One small warm mark at the far edge, balancing the bulb.
                    Icon(
                      Icons.favorite_rounded,
                      size: 13,
                      color: AppColors.secondary.withValues(alpha: 0.45),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // A fixed height so the block does not jump between a short tip
                // and a long one as the pages turn. Measured from what a tip
                // actually is — two or three lines — rather than rounded up to
                // something comfortable.
                SizedBox(
                  // Tall enough for three lines at the tip's own size, which
                  // is a size larger than it used to be drawn at.
                  height: homeScaled(context, 86),
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

    if (widget.onAddTip == null) {
      return card;
    }

    // Outside the frame, under it, in footnote type: reading somebody else's
    // tip is the moment a matchmaker is most likely to think of their own, so
    // the way in has to be there — and it has to be the quietest thing on the
    // block, because the block is for reading.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        card,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: widget.onAddTip,
            icon: Icon(
              Icons.edit_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            label: const Text('לשליחת טיפ'),
          ),
        ),
      ],
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
          // The sentence carries no mark of its own any more: the bulb sits
          // in the block's heading, where it belongs to the card rather than
          // to whatever somebody happened to write.
          //
          // **The same size as "טיפ לשדכן" over it.** The advice was set two
          // steps below its own heading, which made the one block on the page
          // that exists to be *read* the smallest type on it. `titleSmall` is
          // the heading's own role; only the weight separates them now.
          child: Text(
            tip.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (author != null && author.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: ink.withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}

/// The one mark on a tip. A bulb rather than a leaf or a heart: it is the only
/// emoji in the app that has to read as "here is an idea" at 14px, in one
/// glyph, on both platforms' fonts.
const String tipMark = '💡';

/// The tinted disc the tip's drawing sits in — and the paper the drawing's own
/// white ground is recoloured to, so the two are the same tone by construction
/// rather than by two constants that have to be kept in step.
Color _tipDisc(ThemeData theme, Color ink) {
  final bool dark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    ink.withValues(alpha: dark ? 0.24 : 0.14),
    dark ? theme.colorScheme.surfaceContainerHighest : _tipPaper,
  );
}

const Color _tipInk = Color(0xFF5C84A3);
const Color _tipInkDm = Color(0xFF9DBED6);
const Color _tipPaper = Color(0xFFFBF5EA);
