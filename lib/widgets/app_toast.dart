import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The app's way of saying "that worked" without stopping anybody.
///
/// **This is what replaced the dialogs.** A friend added, an import finished, a
/// milestone reached — each of these used to open a window in the middle of the
/// screen with a black wash behind it, and several of them used to *queue*, so
/// a good afternoon's work was paid for with a row of boxes to dismiss. None of
/// that told the matchmaker anything a line at the bottom of the screen could
/// not.
///
/// Three rules, and they are the whole design:
///
/// 1. **It never blocks.** No barrier, no dimming, no button. The page
///    underneath stays live and scrollable while this is on screen.
/// 2. **There is only ever one.** A second call replaces the first rather than
///    waiting behind it. A queue of congratulations is the failure mode this
///    exists to end, and a queue of *toasts* would be the same failure in a
///    smaller shape.
/// 3. **It goes away by itself.** Being congratulated and then made to
///    acknowledge the congratulation is a chore.
///
/// A modal dialog is still right for the things that genuinely need reading or
/// answering — a consent question, a rating request, "מה חדש?". Everything that
/// is merely *nice* comes through here.
abstract final class AppToast {
  /// Long enough to read two short lines, short enough that somebody who
  /// looked away has not lost their place.
  static const Duration visibleFor = Duration(seconds: 3, milliseconds: 500);

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Shows [message], replacing whatever is on screen.
  ///
  /// [emoji] rides at the end of the line — in Hebrew, its left-hand side —
  /// because that is where a sentence finishes. It is optional and should stay
  /// that way: a mark on every message is a mark that means nothing.
  static void show(BuildContext context, String message, {String? emoji}) {
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    dismiss();

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) =>
          _Toast(message: message, emoji: emoji, onTap: dismiss),
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
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.emoji,
    required this.onTap,
  });

  final String message;
  final String? emoji;
  final VoidCallback onTap;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
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
    final Color lead = dark ? theme.colorScheme.primary : AppColors.primaryDark;
    final String? emoji = widget.emoji;

    return Positioned(
      // Clear of the bottom navigation bar, so it never covers the tab
      // somebody is about to press.
      bottom:
          MediaQuery.viewPaddingOf(context).bottom +
          kBottomNavigationBarHeight +
          14,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutCubic,
                ),
              ),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: lead.withValues(alpha: 0.22)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    emoji == null || emoji.isEmpty
                        ? widget.message
                        : '${widget.message} $emoji',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
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
