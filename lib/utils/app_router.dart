import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/add_contacts_screen.dart';
import 'package:shadchan/screens/onboarding_screen.dart';
import 'package:shadchan/screens/create_match_screen.dart';
import 'package:shadchan/screens/incoming_shared_profile_screen.dart';
import 'package:shadchan/screens/match_detail_screen.dart';
import 'package:shadchan/screens/matches_screen.dart';
import 'package:shadchan/screens/people_screen.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/screens/person_form_screen.dart';
import 'package:shadchan/screens/dashboard_screen.dart';
import 'package:shadchan/screens/home_screen.dart';
import 'package:shadchan/screens/monthly_stats_screen.dart';
import 'package:shadchan/screens/privacy_policy_screen.dart';
import 'package:shadchan/screens/reminders_screen.dart';
import 'package:shadchan/screens/religious_levels_settings_screen.dart';
import 'package:shadchan/screens/settings_screen.dart';
import 'package:shadchan/screens/whatsapp_message_settings_screen.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/utils/enums.dart';

List<T> _parseEnumList<T extends Enum>(String? raw, List<T> values) {
  if (raw == null || raw.isEmpty) {
    return <T>[];
  }
  final Set<String> names = raw.split(',').map((String s) => s.trim()).toSet();
  return values.where((T v) => names.contains(v.name)).toList();
}

PeopleSortOption _parsePeopleSort(String? raw) {
  switch (raw) {
    case 'age':
      return PeopleSortOption.ageAscending;
    case 'newest':
      return PeopleSortOption.newest;
    case 'updated':
      return PeopleSortOption.recentlyUpdated;
    case 'alphabetical':
    default:
      return PeopleSortOption.alphabetical;
  }
}

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/home',
    redirect: (BuildContext context, GoRouterState state) {
      final bool isOnboarded = context.read<UserProfileProvider>().isOnboarded;
      final bool atWelcome = state.uri.path == '/welcome';

      if (!isOnboarded) {
        return atWelcome ? null : '/welcome';
      }
      if (atWelcome) {
        return '/home';
      }

      final String location = state.uri.toString();
      if (location.startsWith('/') && !location.startsWith('//')) {
        return null;
      }
      return '/home';
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/welcome',
        builder: (BuildContext context, GoRouterState state) {
          return const OnboardingScreen();
        },
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) {
              return _AppShell(navigationShell: navigationShell);
            },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                builder: (BuildContext context, GoRouterState state) {
                  final Map<String, String> q = state.uri.queryParameters;
                  return HomeScreen(
                    key: ValueKey<String>('home:${state.uri}'),
                    initialSearch: q['q'] ?? '',
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/people',
                builder: (BuildContext context, GoRouterState state) {
                  final Map<String, String> q = state.uri.queryParameters;
                  final bool archived = q['archived'] == 'true';
                  final List<ProfileStatus> statuses =
                      _parseEnumList<ProfileStatus>(
                        q['statuses'],
                        ProfileStatus.values,
                      );
                  final PeopleSortOption sort = _parsePeopleSort(q['sort']);
                  return PeopleScreen(
                    key: ValueKey<String>('people:${state.uri}'),
                    initialShowArchived: archived,
                    initialProfileStatuses: statuses,
                    initialSort: sort,
                  );
                },
                routes: <RouteBase>[
                  GoRoute(
                    path: 'import',
                    builder: (BuildContext context, GoRouterState state) {
                      return const AddContactsScreen();
                    },
                  ),
                  GoRoute(
                    path: 'swipe',
                    redirect: (BuildContext context, GoRouterState state) =>
                        '/people/import',
                  ),
                  GoRoute(
                    path: 'add',
                    builder: (BuildContext context, GoRouterState state) {
                      final IncomingSharedProfileDraft? draft =
                          state.extra is IncomingSharedProfileDraft
                          ? state.extra as IncomingSharedProfileDraft
                          : null;
                      return PersonFormScreen(incomingDraft: draft);
                    },
                  ),
                  GoRoute(
                    path: 'shared-import',
                    builder: (BuildContext context, GoRouterState state) {
                      final IncomingSharedProfileDraft? draft =
                          state.extra is IncomingSharedProfileDraft
                          ? state.extra as IncomingSharedProfileDraft
                          : null;
                      if (draft == null || !draft.hasContent) {
                        return const PeopleScreen();
                      }
                      return IncomingSharedProfileScreen(draft: draft);
                    },
                  ),
                  // "בהמתנה לעדכון" no longer has its own screen — those
                  // contacts simply live in the main list.
                  GoRoute(
                    path: 'pending',
                    redirect: (BuildContext context, GoRouterState state) =>
                        '/people',
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext context, GoRouterState state) {
                      final String personId = state.pathParameters['id']!;
                      return PersonDetailScreen(personId: personId);
                    },
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'edit',
                        builder: (BuildContext context, GoRouterState state) {
                          final String personId = state.pathParameters['id']!;
                          return PersonDetailScreen(
                            personId: personId,
                            initiallyEditing: true,
                          );
                        },
                      ),
                      GoRoute(
                        path: 'shared-edit',
                        builder: (BuildContext context, GoRouterState state) {
                          final String personId = state.pathParameters['id']!;
                          final IncomingSharedProfileDraft? draft =
                              state.extra is IncomingSharedProfileDraft
                              ? state.extra as IncomingSharedProfileDraft
                              : null;
                          return PersonFormScreen(
                            personId: personId,
                            incomingDraft: draft,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/matches',
                builder: (BuildContext context, GoRouterState state) {
                  final Map<String, String> q = state.uri.queryParameters;
                  final bool archived = q['archived'] == 'true';
                  final List<MatchStatus> statuses =
                      _parseEnumList<MatchStatus>(
                        q['statuses'],
                        MatchStatus.values,
                      );
                  return MatchesScreen(
                    key: ValueKey<String>('matches:${state.uri}'),
                    initialShowArchived: archived,
                    initialStatuses: statuses,
                  );
                },
                routes: <RouteBase>[
                  GoRoute(
                    path: 'add',
                    builder: (BuildContext context, GoRouterState state) {
                      final Map<String, String> q = state.uri.queryParameters;
                      return CreateMatchScreen(
                        preSelectedPersonId: q['preSelectedPersonId'],
                        initialPick: switch (q['pick']) {
                          'database' => CreateMatchPick.database,
                          'outside' => CreateMatchPick.outsideDatabase,
                          _ => null,
                        },
                      );
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext context, GoRouterState state) {
                      final String matchId = state.pathParameters['id']!;
                      // The WhatsApp prompt only auto-opens the first time a
                      // proposal is created, not when revisiting it from a list.
                      final bool justCreated =
                          state.uri.queryParameters['justCreated'] == 'true';
                      return MatchDetailScreen(
                        matchId: matchId,
                        autoPromptWhatsApp: justCreated,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/dashboard',
                builder: (BuildContext context, GoRouterState state) {
                  return const DashboardScreen();
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) {
          return const SettingsScreen();
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'religious-levels',
            builder: (BuildContext context, GoRouterState state) {
              return const ReligiousLevelsSettingsScreen();
            },
          ),
          GoRoute(
            path: 'whatsapp-message',
            builder: (BuildContext context, GoRouterState state) {
              return const WhatsAppMessageSettingsScreen();
            },
          ),
        ],
      ),
      GoRoute(
        path: '/stats/month',
        builder: (BuildContext context, GoRouterState state) {
          return const MonthlyStatsScreen();
        },
      ),
      GoRoute(
        path: '/reminders',
        builder: (BuildContext context, GoRouterState state) {
          return const RemindersScreen();
        },
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (BuildContext context, GoRouterState state) {
          return const PrivacyPolicyScreen();
        },
      ),
    ],
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // The bar is always visible inside the shell so navigation never gets
    // "stuck" on an inner screen. The highlighted item follows the active
    // branch (which is always in sync), rather than an exact path match that
    // breaks after an imperative push/pop. The dashboard branch (index 3) has
    // no bar item, so it falls back to the home item.
    final int branchIndex = navigationShell.currentIndex;
    final int selectedIndex = branchIndex <= 2 ? branchIndex : 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: selectedIndex,
        // Always `initialLocation: true` — tapping a tab returns to that area's
        // main screen rather than to whatever inner screen was open there last.
        onTap: (int index) => navigationShell.goBranch(
          index,
          initialLocation: true,
        ),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'בית',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            activeIcon: Icon(Icons.group),
            label: 'המאגר שלי',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'רעיונות',
          ),
        ],
      ),
    );
  }
}
