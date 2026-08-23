import 'dart:async';

import 'package:flutter/material.dart';

/// What the app says back after an action — and the reason there are no black
/// bars along the bottom of this app any more.
///
/// **A `SnackBar` is a black slab across the bottom of the screen.** That is
/// what Material's default is, in a Hebrew, cream-and-gold app whose every
/// other surface is pale, and there were seventy-odd of them: every failed
/// WhatsApp launch, every saved note, every finished import ended in the same
/// black bar sliding up over whatever the matchmaker was looking at — including,
/// on the screens that matter most, the buttons directly underneath it.
///
/// So messages are not snack bars. They are a small card at the *top* of the
/// screen, in the app's own surface colour, that fades in over the app bar and
/// goes away by itself. It never covers a control, it never inverts the page's
/// colours, and it can be dismissed with a tap.
///
/// **It keeps the one thing the snack bar was genuinely good for**, which is an
/// undo: [show] takes an optional action, so "הרעיון הוסר · ביטול" still works
/// exactly as it did.
///
/// Drawn in the root [Overlay], so it survives the sheet, dialog or page that
/// raised it closing underneath it — a message about something that just
/// finished must outlive the thing that finished.
abstract final class AppNotice {
  static OverlayEntry? _entry;

  /// How long a message stays up when no duration is asked for. Long enough to
  /// read a sentence in, short enough that nobody waits for it.
  static const Duration _defaultDuration = Duration(seconds: 4);

  /// Says [message] over whatever is on screen.
  ///
  /// [actionLabel] and [onAction] add a single trailing button — an undo, all
  /// but always. Pressing it dismisses the notice first, so the action lands on
  /// a screen with nothing floating over it.
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool isError = false,
  }) {
    showOn(
      capture(context),
      message,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      isError: isError,
    );
  }

  /// The overlay behind [context], held on to so a message can still be shown
  /// after an `await` that may have taken the widget off the tree.
  ///
  /// The same trick the code here used to play with `ScaffoldMessengerState`,
  /// and for the same reason: "the save failed" has to reach the screen even
  /// when the screen that started the save has since closed.
  static OverlayState? capture(BuildContext context) =>
      Overlay.maybeOf(context, rootOverlay: true);

  /// [show], against an overlay taken earlier with [capture].
  static void showOn(
    OverlayState? overlay,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool isError = false,
  }) {
    final String text = message.trim();
    if (overlay == null || text.isEmpty || !overlay.mounted) {
      return;
    }

    hide();

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext overlayContext) => _NoticeCard(
        message: text,
        actionLabel: actionLabel,
        isError: isError,
        duration: duration ?? _defaultDuration,
        onAction: onAction == null
            ? null
            : () {
                hide();
                onAction();
              },
        onDismiss: hide,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Takes the current notice away. Safe to call when there is none.
  ///
  /// The countdown that calls this lives in the card's own [State], not here:
  /// a static `Timer` outlives the tree it was started from, which in a widget
  /// test is a pending-timer failure and in the app is a callback into a
  /// disposed overlay.
  static void hide() {
    final OverlayEntry? entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }
}

class _NoticeCard extends StatefulWidget {
  const _NoticeCard({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    required this.isError,
    required this.duration,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final bool isError;
  final Duration duration;

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    _dismiss = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color ink = widget.isError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, -0.35),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutCubic,
                ),
              ),
          // The overlay sits above the app's own `Directionality`, so the
          // notice has to declare its own or a Hebrew sentence lays out
          // left-to-right inside it.
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Material(
              color: theme.colorScheme.surface,
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onDismiss,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.isError
                          ? theme.colorScheme.error.withValues(alpha: 0.45)
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ink,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null)
                        TextButton(
                          onPressed: widget.onAction,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: theme.colorScheme.primary,
                          ),
                          child: Text(widget.actionLabel!),
                        )
                      else
                        const SizedBox(width: 6),
                    ],
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
