import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opening a page the way a phone app is expected to: never on top of itself,
/// and never a second copy of a page that is already open further down.
///
/// **Why the stack used to grow without end.** A friend's profile links to
/// their ideas, an idea links back to both friends, and every one of those
/// links was a plain `push`. Profile → idea → the same profile → the same idea
/// stacked four pages where there were two places, and the back button then
/// walked the whole chain again, one copy at a time.
///
/// [open] answers the three cases differently:
/// - the page is already on top → nothing happens (a double tap, or a link to
///   the page you are on);
/// - the page is already open lower down → the stack is popped back to it, so
///   going "forward" to a page you came from is the same as going back to it;
/// - otherwise → an ordinary push.
abstract final class AppNavigation {
  /// Safety net for [open]'s pop-back: never more pops than this in one go.
  static const int _maxPops = 12;

  /// The locations on the navigation stack, oldest first: the base location,
  /// then every page pushed on top of it.
  static List<String> stackOf(RouteMatchList configuration) {
    final List<String> stack = <String>[configuration.uri.path];
    void walk(List<RouteMatchBase> matches) {
      for (final RouteMatchBase match in matches) {
        if (match is ImperativeRouteMatch) {
          stack.add(match.matches.uri.path);
        } else if (match is ShellRouteMatch) {
          walk(match.matches);
        }
      }
    }

    walk(configuration.matches);
    return stack;
  }

  /// Opens [location] — see the class comment.
  static Future<void> open(BuildContext context, String location) async {
    final GoRouter router = GoRouter.of(context);
    final String target = Uri.parse(location).path;
    final List<String> stack = stackOf(
      router.routerDelegate.currentConfiguration,
    );

    if (stack.last == target) {
      // The page is the top of the stack, but a page pushed around the router
      // (a suggestions list, a sheet) may be drawn over it: uncover it.
      final ModalRoute<Object?>? here = ModalRoute.of(context);
      if (here != null && here.settings is! Page<Object?>) {
        Navigator.of(
          context,
        ).popUntil((Route<Object?> route) => route.settings is Page<Object?>);
      }
      return;
    }
    if (stack.contains(target)) {
      for (int i = 0; i < _maxPops && router.canPop(); i++) {
        router.pop();
        if (stackOf(router.routerDelegate.currentConfiguration).last ==
            target) {
          return;
        }
      }
      return;
    }
    await router.push<void>(location);
  }
}
