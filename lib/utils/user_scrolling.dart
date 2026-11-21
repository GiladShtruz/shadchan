import 'dart:async';

import 'package:flutter/widgets.dart';

/// Whether anything on screen is scrolling right now — so work that would
/// redraw the screen (a batch the account sync brought down from another
/// phone) waits until the finger lifts and the list settles, instead of
/// rebuilding the page in the middle of a fling.
///
/// [UserScrolling.listener] sits once above the router and counts the
/// scroll notifications every scrollable already sends; nothing else has to
/// opt in.
abstract final class UserScrolling {
  static final ValueNotifier<bool> scrolling = ValueNotifier<bool>(false);

  static int _active = 0;

  /// Counts scroll starts and ends; a fling's end arrives only once its
  /// ballistic motion has stopped, so "not scrolling" means the list is
  /// really still.
  static Widget listener({required Widget child}) =>
      NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n is ScrollStartNotification) {
            _active++;
            if (!scrolling.value) scrolling.value = true;
          } else if (n is ScrollEndNotification) {
            _active = _active > 0 ? _active - 1 : 0;
            if (_active == 0 && scrolling.value) scrolling.value = false;
          }
          return false;
        },
        child: child,
      );

  /// Runs [action] now when nothing is scrolling, else once the screen has
  /// settled — but never later than [maxWait], so a long browse cannot hold
  /// news back for ever.
  static void whenIdle(
    VoidCallback action, {
    Duration maxWait = const Duration(seconds: 4),
  }) {
    if (!scrolling.value) {
      action();
      return;
    }
    bool done = false;
    late final VoidCallback onChange;
    Timer? cap;
    void run() {
      if (done) return;
      done = true;
      cap?.cancel();
      scrolling.removeListener(onChange);
      action();
    }

    onChange = () {
      if (!scrolling.value) run();
    };
    scrolling.addListener(onChange);
    cap = Timer(maxWait, run);
  }

  @visibleForTesting
  static void reset() {
    _active = 0;
    scrolling.value = false;
  }
}
