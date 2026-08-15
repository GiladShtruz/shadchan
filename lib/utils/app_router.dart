import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/add_contacts_screen.dart';
import 'package:shadchan/screens/add_tip_screen.dart';
import 'package:shadchan/screens/tips_admin_screen.dart';
import 'package:shadchan/screens/ai_import_screen.dart';
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
import 'package:shadchan/screens/new_ideas_screen.dart';
import 'package:shadchan/screens/privacy_policy_screen.dart';
import 'package:shadchan/screens/reminders_screen.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/screens/religious_levels_settings_screen.dart';
import 'package:shadchan/screens/stat_detail_screen.dart';
import 'package:shadchan/screens/whatsapp_message_settings_screen.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/monthly_stats.dart';

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

bool shouldShowBottomNavigationBar(String path) {
  if (const <String>{'/home', '/people', '/matches'}.contains(path)) {
    return true;
  }

  final List<String> segments = Uri(path: path).pathSegments;
  if (segments.length != 2 || segments.first != 'people') {
    return false;
  }

  // A person's profile keeps the app-level navigation visible. The other
  // two-segment people routes are task flows, not profile destinations.
  return !const <String>{
    'add',
    'import',
    'swipe',
    'pending',
    'shared-import',
  }.contains(segments.last);
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
              return _AppShell(
                navigationShell: navigationShell,
                showBottomNavigationBar: shouldShowBottomNavigationBar(
                  state.uri.path,
                ),
              );
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
                    focusBoard: q['section'] == 'board',
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
                    path: 'ai',
                    builder: (BuildContext context, GoRouterState state) {
                      // A path arrives here when the file was shared to the app
                      // or opened with it, rather than picked inside it.
                      return AiImportScreen(
                        incomingFilePath: state.extra is String
                            ? state.extra as String
                            : null,
                      );
                    },
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
      // The matchmaker's own page. It carries every setting the app has —
      // there is no separate settings screen and no gear on the home page.
      GoRoute(
        path: '/profile',
        builder: (BuildContext context, GoRouterState state) {
          return const ProfileScreen();
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
          // Writing a tip for the community, and — for the one account that
          // may — reviewing what everyone else wrote.
          GoRoute(
            path: 'tips',
            builder: (BuildContext context, GoRouterState state) {
              return const AddTipScreen();
            },
          ),
          GoRoute(
            path: 'tips-review',
            builder: (BuildContext context, GoRouterState state) {
              return const TipsAdminScreen();
            },
          ),
        ],
      ),
      GoRoute(
        path: '/ideas/new',
        builder: (BuildContext context, GoRouterState state) {
          return const NewIdeasScreen();
        },
      ),
      GoRoute(
        path: '/stats/month',
        builder: (BuildContext context, GoRouterState state) {
          return const MonthlyStatsScreen();
        },
        routes: <RouteBase>[
          // One number's own records. An unknown metric falls back to the
          // month itself rather than to an error page.
          GoRoute(
            path: ':metric',
            redirect: (BuildContext context, GoRouterState state) {
              final MonthlyStatMetric? metric = MonthlyStatMetric.byName(
                state.pathParameters['metric'],
              );
              return metric == null ? '/stats/month' : null;
            },
            builder: (BuildContext context, GoRouterState state) {
              return StatDetailScreen(
                metric: MonthlyStatMetric.byName(
                  state.pathParameters['metric'],
                )!,
              );
            },
          ),
        ],
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
  const _AppShell({
    required this.navigationShell,
    required this.showBottomNavigationBar,
  });

  final StatefulNavigationShell navigationShell;
  final bool showBottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    // Only the three primary destinations own the app navigation. Nested
    // routes remain inside their branch so back navigation is preserved, but
    // they intentionally render without the bar.
    final int branchIndex = navigationShell.currentIndex;
    final int selectedIndex = branchIndex <= 2 ? branchIndex : 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: showBottomNavigationBar
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: selectedIndex,
              // Tapping a tab always returns to that area's primary screen.
              onTap: (int index) =>
                  navigationShell.goBranch(index, initialLocation: true),
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
            )
          : null,
    );
  }
}
