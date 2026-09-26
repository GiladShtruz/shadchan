import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/app_navigation.dart';

/// Opens a friend's profile — or straight into its quick edit — from anywhere.
///
/// **`/people/:id` lives inside the tabs, and cannot be pushed from above
/// them.** The stats lists, the married page, the reminders page and the
/// add-friends flow are pages on the root navigator, above the tab shell.
/// Pushing a tab route from one of them asks go_router to build the shell a
/// second time on that navigator; it asserts on the duplicate navigator key,
/// and a release build draws a blank screen. From there the profile is pushed
/// as a plain page instead, and back still returns to where the tap was.
Future<void> openPersonProfile(
  BuildContext context,
  String personId, {
  bool editing = false,
}) async {
  final GoRouter router = GoRouter.of(context);
  if (!isAboveTabs(router.routerDelegate.currentConfiguration)) {
    await AppNavigation.open(
      context,
      editing ? '/people/$personId/edit' : '/people/$personId',
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) =>
          PersonDetailScreen(personId: personId, initiallyEditing: editing),
    ),
  );
}

/// Whether the page on top of [configuration] sits outside the tab shell —
/// either a top-level route, or a task flow nested under a tab but placed on
/// the root navigator with `parentNavigatorKey`.
bool isAboveTabs(RouteMatchList configuration) =>
    _topIsAboveTabs(configuration.matches, insideShell: false);

bool _topIsAboveTabs(
  List<RouteMatchBase> matches, {
  required bool insideShell,
}) {
  if (matches.isEmpty) {
    return false;
  }
  final RouteMatchBase top = matches.last;
  if (top is ImperativeRouteMatch) {
    return _topIsAboveTabs(top.matches.matches, insideShell: false);
  }
  if (top is ShellRouteMatch) {
    return _topIsAboveTabs(top.matches, insideShell: true);
  }
  final RouteBase route = top.route;
  return !insideShell || (route is GoRoute && route.parentNavigatorKey != null);
}
