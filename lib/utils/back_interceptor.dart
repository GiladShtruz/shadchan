import 'package:flutter/widgets.dart';

/// A back press a screen wants to answer itself before anything is popped.
///
/// **Why not a `PopScope`.** A tab's own page is the first page of its shell
/// branch, and go_router never tries to pop a navigator that cannot pop — it
/// hands the press straight to the app's back-button dispatcher, so a
/// `PopScope` on that page is never consulted (see `_rootNavigatorKey` in
/// `app_router.dart`). The dispatcher asks these first instead.
///
/// A handler returns true when it used the press. It must answer false unless
/// its screen is the one in front — see [isInFront].
class BackInterceptor {
  BackInterceptor._();

  static final List<bool Function()> _handlers = <bool Function()>[];

  static void add(bool Function() handler) => _handlers.add(handler);

  static void remove(bool Function() handler) => _handlers.remove(handler);

  /// Offers the press to the handlers, most recently added first.
  static bool handle() {
    for (final bool Function() handler in _handlers.reversed.toList()) {
      if (handler()) {
        return true;
      }
    }
    return false;
  }

  /// Whether [context] is on the page the reader is looking at: its route is
  /// the top one in its own navigator, and so is every route that navigator
  /// sits in, and it is not on a tab that is kept alive offstage.
  static bool isInFront(BuildContext context) {
    if (!TickerMode.getValuesNotifier(context).value.enabled) {
      return false;
    }
    BuildContext? current = context;
    while (current != null) {
      final ModalRoute<Object?>? route = ModalRoute.of(current);
      if (route == null) {
        return true;
      }
      if (!route.isCurrent) {
        return false;
      }
      current = route.navigator?.context;
    }
    return true;
  }
}
