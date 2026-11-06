import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "+1 · נוסף למאגר" — a small pill that rises and fades after an action.
///
/// **The points are a footnote, not the message.** The home screen no longer
/// asks anybody to earn points; this is the one place they are mentioned, for
/// a moment, after something was actually done. No barrier, no button, no
/// sound — it is gone in under two seconds and the page underneath stays
/// live. Like [AppToast] there is only ever one: a second replaces the first.
abstract final class PointsReward {
  static const Duration visibleFor = Duration(milliseconds: 1800);

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(OverlayState overlay, {required int points, String? label}) {
    if (points <= 0) {
      return;
    }
    dismiss();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => _Reward(points: points, label: label),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(visibleFor, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  /// The word beside the figure, by what happened.
  static String labelFor({
    required int friends,
    required int ideas,
    required int couples,
    required int engagements,
  }) {
    if (engagements > 0) return 'מזל טוב!';
    if (couples > 0) return 'מעולה!';
    if (ideas > 0 && friends == 0) {
      return ideas == 1 ? 'רעיון נפתח' : 'רעיונות נפתחו';
    }
    if (friends > 0 && ideas == 0) {
      return friends == 1 ? 'נוסף למאגר' : 'נוספו למאגר';
    }
    return 'מעולה';
  }
}

class _Reward extends StatefulWidget {
  const _Reward({required this.points, this.label});

  final int points;
  final String? label;

  @override
  State<_Reward> createState() => _RewardState();
}

class _RewardState extends State<_Reward> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PointsReward.visibleFor,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool still = MediaQuery.disableAnimationsOf(context);
    final Color copper = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    // The figure is isolated left-to-right, or the bidi algorithm turns
    // "+1" into "1+" inside a Hebrew line.
    final String figure = '\u2066+${widget.points}\u2069';
    final String text = widget.label == null
        ? figure
        : '$figure · ${widget.label}';

    return Positioned(
      bottom:
          MediaQuery.viewPaddingOf(context).bottom +
          kBottomNavigationBarHeight +
          24,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double t = _controller.value;
            // In quickly, hold, out slowly — and drift up a little all the way.
            final double opacity = t < 0.15
                ? t / 0.15
                : (t > 0.7 ? (1 - t) / 0.3 : 1);
            return Opacity(
              opacity: opacity.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, still ? 0 : -28 * t),
                child: child,
              ),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: text,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: copper.withValues(alpha: 0.5)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: dark ? 0.3 : 0.08,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    textDirection: TextDirection.rtl,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: copper,
                      fontWeight: FontWeight.w900,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
