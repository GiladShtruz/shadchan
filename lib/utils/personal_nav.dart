import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/workspace_store.dart';

/// Where the personal card's own pages live, now that there is no separate
/// personal area.
///
/// "השדכנים שלי" is a tab of its own for a single who does not matchmake
/// (`/my-matchmakers`), and a page pushed over the app for somebody who has
/// the matchmaker's tabs (`/me/matchmakers`) — the same screen either way.
abstract final class PersonalNav {
  static const String tabRoute = '/my-matchmakers';
  static const String pageRoute = '/me/matchmakers';

  /// The route of "השדכנים שלי" for this account, with [section]
  /// (`approved`, `requests`, `helpers`) and the friend to bring forward.
  static String matchmakersRoute({String? section, String? friend}) {
    final String path = WorkspaceStore.matchmakerEnabled ? pageRoute : tabRoute;
    return Uri(
      path: path,
      queryParameters: <String, String>{
        if (section != null && section.isNotEmpty) 'section': section,
        if (friend != null && friend.isNotEmpty) 'friend': friend,
      },
    ).toString();
  }

  static void openMatchmakers(
    BuildContext context, {
    String? section,
    String? friend,
  }) {
    final String route = matchmakersRoute(section: section, friend: friend);
    if (WorkspaceStore.matchmakerEnabled) {
      context.push(route);
    } else {
      context.go(route);
    }
  }

  /// The one profile, where the card lives in full.
  static void openCard(BuildContext context) => context.go('/profile');

  /// What an old `/me?section=…` link means now.
  static String forLegacy(Map<String, String> query) {
    switch (query['section']) {
      case 'profile':
        return '/profile';
      case 'helpers':
      case 'approved':
      case 'requests':
        return matchmakersRoute(
          section: query['section'],
          friend: query['friend'],
        );
      default:
        return '/home';
    }
  }
}
