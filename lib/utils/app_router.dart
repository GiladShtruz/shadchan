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
import 'package:shadchan/screens/matches_screen.dart';
import 'package:shadchan/screens/matchmaker_profile_screen.dart';
import 'package:shadchan/screens/people_screen.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/screens/person_form_screen.dart';
import 'package:shadchan/screens/community_activity_screen.dart';
import 'package:shadchan/screens/dashboard_screen.dart';
import 'package:shadchan/screens/help_center_screen.dart';
import 'package:shadchan/screens/home_screen.dart';
import 'package:shadchan/screens/privacy_overview_screen.dart';
import 'package:shadchan/screens/support_admin_screen.dart';
import 'package:shadchan/screens/support_report_screen.dart';
import 'package:shadchan/screens/married_friends_screen.dart';
import 'package:shadchan/screens/monthly_stats_screen.dart';
import 'package:shadchan/screens/new_ideas_screen.dart';
import 'package:shadchan/screens/privacy_policy_screen.dart';
import 'package:shadchan/screens/reminders_screen.dart';
import 'package:shadchan/screens/entry_route_screen.dart';
import 'package:shadchan/screens/person_extended_edit_screen.dart';
import 'package:shadchan/screens/personal_area_screen.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/screens/settings_appearance_screen.dart';
import 'package:shadchan/screens/settings_screen.dart';
import 'package:shadchan/screens/settings_data_screen.dart';
import 'package:shadchan/screens/settings_help_screen.dart';
import 'package:shadchan/screens/sign_in_screen.dart';
import 'package:shadchan/screens/stat_detail_screen.dart';
import 'package:shadchan/screens/tips_list_screen.dart';
import 'package:shadchan/screens/whatsapp_message_settings_screen.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/services/workspace_store.dart';
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
  if (const <String>{
    '/home',
    '/people',
    '/matches',
    '/profile',
  }.contains(path)) {
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

/// The navigator above the tabs.
///
/// **Named so that a task flow can be pushed onto it, and that is the whole
/// reason it exists.** Pressing back out of "הוספת אנשי קשר" used to close the
/// app. The route lives under `/people`, in the second branch; opening it from
/// בית is a push across branches, and `RouteMatchList.push` keeps only the
/// *last* match of the branch it lands in — so the branch's navigator was
/// handed one page, `AddContactsScreen`, with nothing underneath it. go_router
/// then walks down to the deepest navigator that can pop, finds that this one
/// cannot, and hands the back press to the root navigator instead, whose only
/// page is the shell. That pop fails, and a failed pop at the root is how
/// Android is told to leave the app — without the screen's own `PopScope` ever
/// being consulted, because the pop was never attempted on its route.
///
/// Pushing these flows here instead puts them above the shell, which always
/// has something to go back *to*: whichever tab was open. See the routes that
/// carry `parentNavigatorKey: _rootNavigatorKey`.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// One navigator per shell branch, so the bottom bar can reach into a branch's
/// own stack. See [_AppShell.build] for why it has to.
final List<GlobalKey<NavigatorState>> _branchNavigatorKeys =
    <GlobalKey<NavigatorState>>[
      GlobalKey<NavigatorState>(debugLabel: 'branch-home'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-people'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-matches'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-dashboard'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-profile'),
    ];

/// The bottom bar's items in order, each with the shell branch it opens.
/// "פרופיל" is last, which in RTL puts it at the left end of the bar.
const List<int> _navBranches = <int>[0, 1, 2, 4];

/// True until the first redirect has run, so "open where I was last" applies
/// to a launch and never to a later navigation.
bool _atLaunch = true;

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    redirect: (BuildContext context, GoRouterState state) {
      final bool isOnboarded = context.read<UserProfileProvider>().isOnboarded;
      final bool atWelcome = state.uri.path == '/welcome';
      final bool atSignIn = state.uri.path == '/sign-in';

      // **The account comes first, and there is no way past it.** It used to be
      // the second step and an optional one: the profile form, then a sign-in
      // screen with "המשך בלי להתחבר" on it. Both halves of that are gone. The
      // account is first because a name, a photograph and a line about yourself
      // are things that belong *to* somebody, and there was nobody to attach
      // them to until this was answered; and it is compulsory because a
      // local-only database is one lost phone away from nothing at all.
      //
      // It is gated on a **local flag**, never on the account itself: this runs
      // on the first frame, and asking Firebase who is signed in would drag
      // `initializeApp`, App Check and the auth restore onto the cold start.
      // `SignInScreen` steps aside by itself when the answer turns out to be
      // "already signed in" — see [SignInPromptStore.hasAccount].
      final bool atStart = state.uri.path == '/start';
      if (!SignInPromptStore.hasAccount) {
        // "ברוך הבא!" comes before signing in on a fresh install: the route
        // chosen there decides what follows the sign-in. An install that was
        // set up before the choice existed is a matchmaker and skips it.
        if (!isOnboarded && WorkspaceStore.entryRoute == null) {
          return atStart ? null : '/start';
        }
        if (atStart) {
          return null;
        }
        return atSignIn ? null : '/sign-in';
      }

      if (!isOnboarded) {
        return atWelcome ? null : '/welcome';
      }

      // Signed in and introduced, and the screen is still reachable:
      // "התחברות" on the community areas pushes the same one. It is not bounced
      // back here, because a screen somebody asked for should open.
      final bool launch = _atLaunch;
      _atLaunch = false;
      final String path = state.uri.path;

      if (atWelcome || atStart) {
        return WorkspaceStore.lastArea == WorkArea.personal ? '/me' : '/home';
      }

      // Somebody who signed up only to manage their own card never sees the
      // matchmaker's tabs until they switch that system on themselves.
      if (!WorkspaceStore.matchmakerEnabled &&
          (path == '/home' ||
              path.startsWith('/people') ||
              path.startsWith('/matches') ||
              path == '/dashboard')) {
        return '/me';
      }

      // A launch opens on the area the user was last in — its main page,
      // never whatever inner screen they happened to leave from.
      if (launch &&
          path == '/home' &&
          WorkspaceStore.lastArea == WorkArea.personal) {
        return '/me';
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
      GoRoute(
        path: '/start',
        builder: (BuildContext context, GoRouterState state) {
          return const EntryRouteScreen();
        },
      ),
      // The card owner's own area, outside the matchmaker's tabs.
      GoRoute(
        path: '/me',
        builder: (BuildContext context, GoRouterState state) {
          return const PersonalAreaScreen();
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'card',
            builder: (BuildContext context, GoRouterState state) {
              return const PersonExtendedEditScreen.ownerCard();
            },
          ),
        ],
      ),
      GoRoute(
        path: '/sign-in',
        builder: (BuildContext context, GoRouterState state) {
          return const SignInScreen();
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
            navigatorKey: _branchNavigatorKeys[0],
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
            navigatorKey: _branchNavigatorKeys[1],
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
                  final String batch = (q['batch'] ?? '').trim();
                  return PeopleScreen(
                    key: ValueKey<String>('people:${state.uri}'),
                    initialShowArchived: archived,
                    initialProfileStatuses: statuses,
                    initialSort: sort,
                    // Set by the import flow, which lands here on the people it
                    // has just added. See `PeopleScreen.importBatchId`.
                    importBatchId: batch.isEmpty ? null : batch,
                  );
                },
                routes: <RouteBase>[
                  // **Above the tabs, not inside them.** These four are task
                  // flows rather than destinations: they are opened from בית
                  // as often as from המאגר שלי, they cover the whole screen,
                  // and every one of them is left by going back. Pushed onto a
                  // branch navigator from another branch they end up as the
                  // only page in it, and back then leaves the app — see
                  // [_rootNavigatorKey] for exactly how.
                  GoRoute(
                    path: 'import',
                    parentNavigatorKey: _rootNavigatorKey,
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
                    parentNavigatorKey: _rootNavigatorKey,
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
                    parentNavigatorKey: _rootNavigatorKey,
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
                    parentNavigatorKey: _rootNavigatorKey,
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
            navigatorKey: _branchNavigatorKeys[2],
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
                    focusMatchId: q['focus'],
                    promptShareForMatchId: q['justCreated'] == 'true'
                        ? q['focus']
                        : null,
                  );
                },
                routes: <RouteBase>[
                  // Opened from בית's "+" and from the two add cards as
                  // often as from הרעיונות שלי, so it goes above the tabs for
                  // the same reason the people flows do — see
                  // [_rootNavigatorKey].
                  GoRoute(
                    path: 'add',
                    parentNavigatorKey: _rootNavigatorKey,
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
                  // **A proposal has no page of its own any more.**
                  //
                  // Everything that page held — the status moves, a reminder, a
                  // related contact, the journal — is on the card in the list,
                  // behind "פעולות", and the one thing left that wanted a
                  // screen (the two candidates side by side) is a sheet the
                  // card opens.
                  //
                  // The *route* stays, because twenty places point at it: a
                  // notification, a reminder row, a home card, a freshly
                  // created proposal — including notifications already sitting
                  // in an Android tray from an older build. What it renders now
                  // is the list itself, with that one proposal lifted to the
                  // top and lit up, which is the honest answer to "take me to
                  // this proposal" once the proposal lives in the list.
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext context, GoRouterState state) {
                      final String matchId = state.pathParameters['id']!;
                      // The share sheet only auto-opens the first time a
                      // proposal is created, not when revisiting it from a
                      // list.
                      final bool justCreated =
                          state.uri.queryParameters['justCreated'] == 'true';
                      return MatchesScreen(
                        key: ValueKey<String>('match:$matchId'),
                        focusMatchId: matchId,
                        promptShareForMatchId: justCreated ? matchId : null,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[3],
            routes: <RouteBase>[
              GoRoute(
                path: '/dashboard',
                builder: (BuildContext context, GoRouterState state) {
                  return const DashboardScreen();
                },
              ),
            ],
          ),
          // "פרופיל" — the fourth tab. Everything behind it (settings, help,
          // tips) goes above the tabs, like the other task flows.
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[4],
            routes: <RouteBase>[
              // The matchmaker's own page: who they are, their account, their card,
              // and one row into the settings.
              GoRoute(
                path: '/profile',
                builder: (BuildContext context, GoRouterState state) {
                  // `?section=settings` highlights the row that opens the settings
                  // rather than landing at the top of the page — see
                  // [ProfileScreen.focusSettings].
                  return ProfileScreen(
                    focusSettings:
                        state.uri.queryParameters['section'] == 'settings',
                  );
                },
                routes: <RouteBase>[
                  // Every setting the app has, on a page of its own. It used to be a
                  // group halfway down `/profile`.
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'settings',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsScreen();
                    },
                  ),
                  // The old "כרטיס השידוכים שלי" page. The full personal card replaced
                  // it; anything still pointing here lands in the personal area.
                  GoRoute(
                    path: 'card',
                    redirect: (BuildContext context, GoRouterState state) =>
                        '/me',
                  ),
                  // The settings are one short page and five screens behind it. Each of
                  // these used to be a card on `/profile` itself.
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'appearance',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsAppearanceScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'data',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsDataScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'help',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsHelpScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'tips-list',
                    builder: (BuildContext context, GoRouterState state) {
                      return const TipsListScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'whatsapp-message',
                    builder: (BuildContext context, GoRouterState state) {
                      return const WhatsAppMessageSettingsScreen();
                    },
                  ),
                  // Writing a tip for the community, and — for the one account that
                  // may — reviewing what everyone else wrote.
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'tips',
                    builder: (BuildContext context, GoRouterState state) {
                      return const AddTipScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'tips-review',
                    builder: (BuildContext context, GoRouterState state) {
                      return const TipsAdminScreen();
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // The best page in the app: everybody who got married, with the ones the
      // matchmaker's own ideas produced at the top of it.
      GoRoute(
        path: '/married',
        builder: (BuildContext context, GoRouterState state) {
          return const MarriedFriendsScreen();
        },
      ),
      GoRoute(
        path: '/ideas/new',
        builder: (BuildContext context, GoRouterState state) {
          return const NewIdeasScreen();
        },
      ),
      // One matchmaker's public page, opened by tapping a name on the
      // leaderboard. The name and the picture the board already had travel with
      // the route so the page opens with the person on it rather than with a
      // spinner — see [MatchmakerProfileScreen].
      GoRoute(
        path: '/matchmakers/:uid',
        builder: (BuildContext context, GoRouterState state) {
          return MatchmakerProfileScreen(
            uid: state.pathParameters['uid'] ?? '',
            fallbackName: state.uri.queryParameters['name'] ?? '',
            fallbackPhotoUrl: state.uri.queryParameters['photo'] ?? '',
          );
        },
      ),
      // The community and the matchmaker's own numbers, on one screen.
      GoRoute(
        path: '/activity',
        builder: (BuildContext context, GoRouterState state) {
          return const CommunityActivityScreen();
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
                // "הנתונים שלך" counts everything that ever happened and links
                // here with `?window=all`, so the list it opens is the list
                // behind the number that was pressed rather than this month's.
                allTime: state.uri.queryParameters['window'] == 'all',
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
      // Everything behind "קהילה, עזרה ומשוב": the one report form, the short
      // help centre, the plain-language privacy page, and — for the accounts on
      // the administrator list — the console the reports arrive in.
      GoRoute(
        path: '/support',
        redirect: (BuildContext context, GoRouterState state) =>
            state.uri.path == '/support' ? '/support/help' : null,
        routes: <RouteBase>[
          GoRoute(
            path: 'report',
            builder: (BuildContext context, GoRouterState state) {
              return SupportReportScreen(
                initialText: state.extra is String ? state.extra as String : '',
                initialKind: SupportReportKind.byName(
                  state.uri.queryParameters['kind'],
                ),
              );
            },
          ),
          GoRoute(
            path: 'help',
            builder: (BuildContext context, GoRouterState state) {
              return const HelpCenterScreen();
            },
          ),
          GoRoute(
            path: 'privacy',
            builder: (BuildContext context, GoRouterState state) {
              return const PrivacyOverviewScreen();
            },
          ),
          GoRoute(
            path: 'admin',
            builder: (BuildContext context, GoRouterState state) {
              return const SupportAdminScreen();
            },
          ),
        ],
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
    // Only the primary destinations own the app navigation. Nested routes
    // remain inside their branch so back navigation is preserved, but they
    // intentionally render without the bar.
    final int branchIndex = navigationShell.currentIndex;
    final int navIndex = _navBranches.indexOf(branchIndex);
    final int selectedIndex = navIndex < 0 ? 0 : navIndex;

    return ValueListenableBuilder<int>(
      valueListenable: WorkspaceStore.revision,
      builder: (BuildContext context, _, _) {
        // A card-only user reaches "פרופיל" from their personal area, and
        // sees no matchmaker tabs at all until they switch that system on.
        final bool showBar =
            showBottomNavigationBar && WorkspaceStore.matchmakerEnabled;
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: showBar
              ? BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: selectedIndex,
                  // Tapping a tab always returns to that area's primary screen.
                  onTap: (int index) =>
                      _goToBranchRoot(_navBranches[index], navigationShell),
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
                      label: 'הרעיונות שלי',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline_rounded),
                      activeIcon: Icon(Icons.person_rounded),
                      label: 'פרופיל',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }

  /// Returns a tab to its primary screen — including out of any screen that was
  /// pushed onto the branch imperatively.
  ///
  /// `goBranch(initialLocation: true)` alone is not enough, and the bug it left
  /// is worth writing down. A branch's `Navigator` holds two kinds of route:
  /// the declarative `Page`s go_router builds from the location, and anything
  /// a screen pushed itself with `Navigator.push` — which several flows do
  /// (`ThinkScreen.open`, `openSuggestionsFor`, `openExtendedPersonEditor`).
  /// Resetting the location only rewrites the first kind; an imperative route
  /// sits on top of them and stays there. The location said `/home`, the bar
  /// drew "בית" as selected, and the screen never changed — most visibly from
  /// "עוצרים רגע לחשוב על החברים", which is reached that way.
  ///
  /// So the imperative routes are popped first, down to the last declarative
  /// page — never past it, which is what would tear a branch's own pages out
  /// from under go_router.
  static void _goToBranchRoot(
    int index,
    StatefulNavigationShell navigationShell,
  ) {
    _branchNavigatorKeys[index].currentState?.popUntil(
      (Route<dynamic> route) => route.settings is Page || route.isFirst,
    );
    navigationShell.goBranch(index, initialLocation: true);
  }
}
