import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Leaving a search for a page, and coming back to the page instead of to the
/// search.
///
/// **Two things go wrong when a row in a live-results panel is tapped.**
///
/// *The keyboard comes back.* Popping a route hands focus back to whatever held
/// it when the route was pushed — which is the search field — so returning from
/// a friend's profile re-opened the keyboard and the results panel over a
/// screen the reader had deliberately walked back to. Clearing the query on the
/// way out is not enough: the focus is restored after the pop, not before it.
///
/// *And the photograph arrives smeared.* The avatar flies to the profile as a
/// `Hero`, and a hero measures its destination once. Pushed while the keyboard
/// is still up, it measures a viewport that is a keyboard shorter than the one
/// the profile ends up laid out in, so the circle lands stretched.
///
/// Both are the same fix: put the keyboard away, let the viewport settle, and
/// only then push — then take the focus away again on the way back.
Future<void> pushLeavingSearch(BuildContext context, String location) async {
  final GoRouter router = GoRouter.of(context);
  // The keyboard itself, not "is anything focused": with nothing focused the
  // primary focus is still the route's own scope node, which reports having
  // focus, and every tap in the app would pay the delay below for nothing.
  final bool keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

  if (keyboardUp) {
    FocusManager.instance.primaryFocus?.unfocus();
    // Long enough for the platform to report the smaller view insets, short
    // enough that the tap still feels immediate. Without it the push happens
    // in the same frame as the unfocus and the hero measures the old viewport.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!context.mounted) {
      return;
    }
  }

  await router.push<void>(location);

  if (!context.mounted) {
    return;
  }
  // The pop has already restored focus to the field by the time this runs, so
  // this is what actually keeps the keyboard down on the way back.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FocusManager.instance.primaryFocus?.unfocus();
  });
}
