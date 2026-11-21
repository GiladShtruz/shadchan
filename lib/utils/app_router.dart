import 'package:shadchan/widgets/personal_community_news.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/widgets/branch_gate.dart';
import 'package:shadchan/widgets/cream_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/screens/partner_space_screen.dart';
import 'package:shadchan/screens/account_gate_screens.dart';
import 'package:shadchan/screens/account_screen.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/add_contacts_screen.dart';
import 'package:shadchan/screens/add_tip_screen.dart';
import 'package:shadchan/screens/tips_admin_screen.dart';
import 'package:shadchan/screens/ai_import_screen.dart';
import 'package:shadchan/screens/onboarding_screen.dart';
import 'package:shadchan/screens/create_match_screen.dart';
import 'package:shadchan/screens/incoming_shared_profile_screen.dart';
import 'package:shadchan/screens/incoming_voice_note_screen.dart';
import 'package:shadchan/screens/matches_screen.dart';
import 'package:shadchan/screens/matchmaker_profile_screen.dart';
import 'package:shadchan/screens/known_matchmakers_screen.dart';
import 'package:shadchan/screens/people_screen.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/screens/person_form_screen.dart';
import 'package:shadchan/screens/community_activity_screen.dart';
import 'package:shadchan/screens/dashboard_screen.dart';
import 'package:shadchan/screens/board_screen.dart';
import 'package:shadchan/screens/help_center_screen.dart';
import 'package:shadchan/screens/home_screen.dart';
import 'package:shadchan/screens/privacy_overview_screen.dart';
import 'package:shadchan/screens/support_admin_screen.dart';
import 'package:shadchan/screens/support_report_screen.dart';
import 'package:shadchan/screens/deleted_ideas_screen.dart';
import 'package:shadchan/screens/married_friends_screen.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/screens/monthly_stats_screen.dart';
import 'package:shadchan/screens/new_ideas_screen.dart';
import 'package:shadchan/screens/privacy_policy_screen.dart';
import 'package:shadchan/screens/reminders_screen.dart';
import 'package:shadchan/screens/entry_route_screen.dart';
import 'package:shadchan/screens/person_extended_edit_screen.dart';
import 'package:shadchan/screens/personal_home_screen.dart';
import 'package:shadchan/screens/personal_invite_screen.dart';
import 'package:shadchan/screens/card_friend_screen.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/screens/settings_appearance_screen.dart';
import 'package:shadchan/screens/settings_notifications_screen.dart';
import 'package:shadchan/screens/settings_screen.dart';
import 'package:shadchan/screens/settings_auto_match_screen.dart';
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
import 'package:shadchan/screens/chats_screen.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/screens/sharing_settings_screen.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/utils/personal_nav.dart';
import 'package:shadchan/widgets/shell_bottom_bar.dart';
import 'package:shadchan/screens/my_matchmakers_screen.dart';

List<T> _parseEnumList<T extends Enum>(String? raw, List<T> values) {
  if (raw == null || raw.isEmpty) {
    return <T>[];
  }
  final Set<String> names = raw.split(',').map((String s) => s.trim()).toSet();
  return values.where((T v) => names.contains(v.name)).toList();
}

PeopleSortOption? _parsePeopleSort(String? raw) {
  switch (raw) {
    case null:
    case '':
      return null;
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
    '/chats',
    '/people',
    '/matches',
    '/profile',
    '/my-matchmakers',
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
    'shared-voice',
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
      GlobalKey<NavigatorState>(debugLabel: 'branch-chats'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-profile'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-people'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-matches'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-dashboard'),
      GlobalKey<NavigatorState>(debugLabel: 'branch-my-matchmakers'),
    ];

/// The shell's branches, by name.
abstract final class _Branch {
  static const int home = 0;
  static const int chats = 1;
  static const int profile = 2;
  static const int people = 3;
  static const int matches = 4;
  static const int myMatchmakers = 6;
}

/// The bottom bar's items in order, each with the shell branch it opens. In
/// RTL the first is at the right: בית | צ'אטים | פרופיל | המאגר שלי |
/// הרעיונות שלי — "פרופיל" in the middle.
///
/// A single who does not matchmake has a short bar instead — בית | צ'אטים |
/// פרופיל | השדכנים שלי — and never sees the database, the ideas or partner
/// matchmakers.
List<int> _navBranches() => WorkspaceStore.matchmakerEnabled
    ? const <int>[
        _Branch.home,
        _Branch.chats,
        _Branch.profile,
        _Branch.people,
        _Branch.matches,
      ]
    : const <int>[
        _Branch.home,
        _Branch.chats,
        _Branch.profile,
        _Branch.myMatchmakers,
      ];

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    // The account gates below are local flags that change while the app is
    // open — an address verified, a deletion found pending — and the router
    // has to ask its question again when they do.
    refreshListenable: SignInPromptStore.gate,
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

      // Signed in, and three things before anything else, in this order.
      //
      // An account waiting for deletion opens on the offer to restore it and
      // nothing else.
      final String gatePath = state.uri.path;
      if (SignInPromptStore.deletionPending) {
        return gatePath == '/account-recovery' ? null : '/account-recovery';
      }
      // An address that has not been shown to belong to whoever typed it.
      if (SignInPromptStore.mustVerifyEmail) {
        return gatePath == '/verify-email' ? null : '/verify-email';
      }
      // A phone that has never read the account it is signed in to. The
      // profile is part of the account, so asking somebody to introduce
      // themselves before it has arrived would ask a returning matchmaker to
      // start again.
      //
      // And a phone that has just been moved onto a database it has not read
      // yet — joining a couple's shared database above all. Its local copy was
      // emptied for the new database, so the home would show an empty
      // database (or a stale half of one) as if that were the shared one.
      // It waits here until the server's copy has arrived.
      if ((!isOnboarded && !AccountSyncLedger.initialPullDoneHere) ||
          AccountSyncLedger.awaitingFirstReadHere) {
        return gatePath == '/account-loading' ? null : '/account-loading';
      }
      if (gatePath == '/account-recovery' ||
          gatePath == '/verify-email' ||
          gatePath == '/account-loading') {
        return '/home';
      }

      if (!isOnboarded) {
        return atWelcome ? null : '/welcome';
      }

      // Signed in and introduced, and the screen is still reachable:
      // "התחברות" on the community areas pushes the same one. It is not bounced
      // back here, because a screen somebody asked for should open.
      final String path = state.uri.path;
      if (InviteLinkService.pending?.personalToken != null &&
          ![
            '/invite/personal',
            '/profile/account',
            '/sign-in',
          ].contains(path)) {
        return '/invite/personal';
      }

      if (atWelcome || atStart) {
        return '/home';
      }

      // **One app, no areas.** The old personal area's links (pushes and
      // notices already on phones, `/me?section=…`) land on the one home,
      // the one profile or "השדכנים שלי".
      if (path == '/me') {
        return PersonalNav.forLegacy(state.uri.queryParameters);
      }

      // A single who does not matchmake never reaches the database, the
      // ideas or the network — until they switch the matchmaker's tools on
      // from the profile, in the same account.
      if (!WorkspaceStore.matchmakerEnabled &&
          (path.startsWith('/people') ||
              path.startsWith('/matches') ||
              path.startsWith('/network') ||
              path.startsWith('/ideas') ||
              path == '/board' ||
              path == '/dashboard' ||
              path == PersonalNav.pageRoute)) {
        return path == PersonalNav.pageRoute
            ? state.uri.replace(path: PersonalNav.tabRoute).toString()
            : '/home';
      }
      // "השדכנים שלי" is a tab only in the single's short bar; everybody
      // else opens it as a page over the app.
      if (WorkspaceStore.matchmakerEnabled && path == PersonalNav.tabRoute) {
        return state.uri.replace(path: PersonalNav.pageRoute).toString();
      }

      final String location = state.uri.toString();
      if (location.startsWith('/') && !location.startsWith('//')) {
        return null;
      }
      return '/home';
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/invite/personal',
        builder: (_, _) => const PersonalInviteScreen(),
      ),
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
      // What is left of the old personal area: the card editor, one news
      // post, and "השדכנים שלי" as a page for somebody with the matchmaker's
      // tabs. `/me` itself is redirected above.
      GoRoute(path: '/me', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/me/news/:id',
        builder: (_, state) =>
            PersonalNewsDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/me/card',
        builder: (BuildContext context, GoRouterState state) {
          return const PersonExtendedEditScreen.ownerCard();
        },
      ),
      GoRoute(
        path: PersonalNav.pageRoute,
        builder: (BuildContext context, GoRouterState state) {
          return MyMatchmakersPage(
            section: state.uri.queryParameters['section'],
            friendUid: state.uri.queryParameters['friend'],
          );
        },
      ),
      GoRoute(
        path: '/sign-in',
        builder: (BuildContext context, GoRouterState state) {
          return const SignInScreen();
        },
      ),
      GoRoute(
        path: '/account-loading',
        builder: (BuildContext context, GoRouterState state) {
          return const AccountLoadingScreen();
        },
      ),
      GoRoute(
        path: '/verify-email',
        builder: (BuildContext context, GoRouterState state) {
          return const VerifyEmailScreen();
        },
      ),
      GoRoute(
        path: '/account-recovery',
        builder: (BuildContext context, GoRouterState state) {
          return const AccountRecoveryScreen();
        },
      ),
      StatefulShellRoute(
        // The four main pages side by side: a horizontal swipe on a page's
        // own root moves to the next one, the way the bar would.
        navigatorContainerBuilder:
            (
              BuildContext context,
              StatefulNavigationShell navigationShell,
              List<Widget> children,
            ) => _SwipeableBranches(
              navigationShell: navigationShell,
              children: children,
            ),
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
            navigatorKey: _branchNavigatorKeys[_Branch.home],
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                builder: (BuildContext context, GoRouterState state) {
                  final Map<String, String> q = state.uri.queryParameters;
                  // One home for everybody. A single who does not matchmake
                  // sees the card's side of it; everybody else the
                  // matchmaker's, with their own card woven in when they
                  // keep one.
                  return ValueListenableBuilder<int>(
                    valueListenable: WorkspaceStore.revision,
                    builder: (BuildContext context, _, _) =>
                        WorkspaceStore.matchmakerEnabled
                        ? HomeScreen(
                            key: ValueKey<String>('home:${state.uri}'),
                            initialSearch: q['q'] ?? '',
                            focusBoard: q['section'] == 'board',
                          )
                        : const PersonalHomeScreen(),
                  );
                },
              ),
            ],
          ),
          // "צ'אטים" — one list of every conversation, whoever it is with.
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[_Branch.chats],
            routes: <RouteBase>[
              GoRoute(
                path: ChatsScreen.route,
                builder: (BuildContext context, GoRouterState state) {
                  return const ChatsScreen();
                },
                routes: <RouteBase>[
                  // One conversation, above the tabs.
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: ':id',
                    builder: (BuildContext context, GoRouterState state) {
                      final Object? extra = state.extra;
                      return ChatScreen(
                        chatId: state.pathParameters['id'] ?? '',
                        initialRef: extra is ChatRef ? extra : null,
                        otherName: state.uri.queryParameters['name'],
                        contextIdeaId: state.uri.queryParameters['idea'],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // "פרופיל" — the middle of the bar, drawn as the user's own face.
          // Everything behind it (settings, help, tips) goes above the tabs.
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[_Branch.profile],
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
                    focusUsage: state.uri.queryParameters['section'] == 'usage',
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
                  // "החשבון שלי": the address, the ways in, the password, and
                  // the ways out.
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'account',
                    builder: (BuildContext context, GoRouterState state) {
                      return const AccountScreen();
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
                    path: 'auto-match',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsAutoMatchScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'appearance',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsAppearanceScreen();
                    },
                  ),
                  GoRoute(
                    parentNavigatorKey: _rootNavigatorKey,
                    path: 'notifications',
                    builder: (BuildContext context, GoRouterState state) {
                      return const SettingsNotificationsScreen();
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
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[_Branch.people],
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
                  final PeopleSortOption? sort = _parsePeopleSort(q['sort']);
                  final String batch = (q['batch'] ?? '').trim();
                  return CreamPage(
                    child: PeopleScreen(
                      key: ValueKey<String>('people:${state.uri}'),
                      personalCardsOnly: q['personalCards'] == '1',
                      initialShowArchived: archived,
                      initialProfileStatuses: statuses,
                      initialSort: sort,
                      // Set by the import flow, which lands here on the people
                      // it has just added. See `PeopleScreen.importBatchId`.
                      importBatchId: batch.isEmpty ? null : batch,
                    ),
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
                  // A WhatsApp voice note, filed under a friend's notes.
                  GoRoute(
                    path: 'shared-voice',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      final IncomingSharedProfileDraft? draft =
                          state.extra is IncomingSharedProfileDraft
                          ? state.extra as IncomingSharedProfileDraft
                          : null;
                      if (draft == null || !draft.hasFiles) {
                        return const PeopleScreen();
                      }
                      return IncomingVoiceNoteScreen(draft: draft);
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
                      return PersonDetailScreen(
                        personId: personId,
                        focus: state.uri.queryParameters['focus'],
                      );
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
            navigatorKey: _branchNavigatorKeys[_Branch.matches],
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
                  return CreamPage(
                    child: MatchesScreen(
                      key: ValueKey<String>('matches:${state.uri}'),
                      initialShowArchived: archived,
                      initialStatuses: statuses,
                      focusMatchId: q['focus'],
                      promptShareForMatchId: q['justCreated'] == 'true'
                          ? q['focus']
                          : null,
                    ),
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
                      return CreamPage(
                        child: MatchesScreen(
                          key: ValueKey<String>('match:$matchId'),
                          focusMatchId: matchId,
                          promptShareForMatchId: justCreated ? matchId : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[5],
            routes: <RouteBase>[
              GoRoute(
                path: '/dashboard',
                builder: (BuildContext context, GoRouterState state) {
                  return const DashboardScreen();
                },
              ),
            ],
          ),
          // "השדכנים שלי" — a tab only in the short bar of a single who does
          // not matchmake; a page (`/me/matchmakers`) for everybody else.
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[_Branch.myMatchmakers],
            routes: <RouteBase>[
              GoRoute(
                path: PersonalNav.tabRoute,
                builder: (BuildContext context, GoRouterState state) {
                  return MyMatchmakersPage(
                    asTab: true,
                    section: state.uri.queryParameters['section'],
                    friendUid: state.uri.queryParameters['friend'],
                  );
                },
              ),
            ],
          ),
        ],
      ),
      // The best page in the app: everybody who got married, with the ones the
      // matchmaker's own ideas produced at the top of it.
      // The network between connected matchmakers: the shared pool, one
      // shared card (view only), one idea offered between two of them, and
      // this matchmaker's own sharing choice.
      GoRoute(
        path: NetworkScreen.route,
        builder: (BuildContext context, GoRouterState state) {
          return NetworkScreen(
            forPersonId: state.uri.queryParameters['for'],
            ownerUid: state.uri.queryParameters['owner'],
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'card/:owner/:person',
            builder: (BuildContext context, GoRouterState state) {
              return SharedCardScreen(
                ownerUid: state.pathParameters['owner'] ?? '',
                personId: state.pathParameters['person'] ?? '',
              );
            },
          ),
          GoRoute(
            path: 'proposals/:id',
            builder: (BuildContext context, GoRouterState state) {
              return ProposalScreen(
                proposalId: state.pathParameters['id'] ?? '',
              );
            },
          ),
          GoRoute(
            path: 'sharing',
            builder: (BuildContext context, GoRouterState state) {
              return SharingSettingsScreen(
                readerUid: state.uri.queryParameters['with'],
                readerName: state.uri.queryParameters['name'],
              );
            },
          ),
        ],
      ),
      // The couple space, and the partner's database.
      GoRoute(
        path: PartnerSpaceScreen.route,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) =>
            const PartnerSpaceScreen(),
      ),
      GoRoute(
        path: PartnerDatabaseScreen.route,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) =>
            const PartnerDatabaseScreen(),
      ),
      GoRoute(
        path: '/married',
        builder: (BuildContext context, GoRouterState state) {
          return const MarriedFriendsScreen();
        },
      ),
      GoRoute(
        path: FriendsWithCardsScreen.route,
        builder: (BuildContext context, GoRouterState state) {
          return FriendsWithCardsScreen(
            requestOwnerUid: state.uri.queryParameters['request'],
            requestPhoneHash: state.uri.queryParameters['h'],
          );
        },
      ),
      GoRoute(
        path: '/ideas/deleted',
        builder: (BuildContext context, GoRouterState state) {
          return const DeletedIdeasScreen();
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
      // "שדכנים שאני מכיר": matchmakers among this phone's contacts, the
      // connections between them, and one matchmaker's basic profile (where a
      // "[שם] הצטרף לשדכן" notice and a connection request lead).
      GoRoute(
        path: KnownMatchmakersScreen.route,
        builder: (BuildContext context, GoRouterState state) {
          return const KnownMatchmakersScreen();
        },
        routes: <RouteBase>[
          GoRoute(
            path: ':uid',
            builder: (BuildContext context, GoRouterState state) {
              return KnownMatchmakerProfileScreen(
                uid: state.pathParameters['uid'] ?? '',
              );
            },
          ),
        ],
      ),
      // "הלוח שלי" in full; the home screen shows only its first rows.
      GoRoute(
        path: '/board',
        builder: (BuildContext context, GoRouterState state) {
          return const BoardScreen();
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
      // "דביר אישר גישה לכרטיס שלו" — a notice about one friend's card opens
      // that friend's profile in the database: by the card link, else by the
      // number the owner approved with. Wait for a fresh authorized local
      // copy; a revoked grant must never fall back to a cached profile.
      GoRoute(
        path: '/card-friend/:ownerUid',
        builder: (_, state) => CardFriendScreen(
          ownerUid: state.pathParameters['ownerUid']!,
          phoneHash: state.uri.queryParameters['h'],
          focus: state.uri.queryParameters['focus'] ?? 'card',
        ),
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
    return ValueListenableBuilder<int>(
      valueListenable: WorkspaceStore.revision,
      builder: (BuildContext context, _, _) {
        final List<int> branches = _navBranches();
        final int navIndex = branches.indexOf(navigationShell.currentIndex);
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: showBottomNavigationBar
              ? ShellBottomBar(
                  matchmaker: WorkspaceStore.matchmakerEnabled,
                  selected: navIndex,
                  onSelected: (int index) =>
                      _goToBranchRoot(branches[index], navigationShell),
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

/// The shell's branches, with a swipe between the four main pages.
///
/// בית ← המאגר שלי ← הרעיונות שלי ← פרופיל, in the bar's own order: in RTL
/// the next page lies to the left, so a finger moving right brings it in.
/// The page follows the finger and the neighbour slides in beside it; let go
/// past a quarter of the width (or with a flick) and the bar moves with it.
///
/// **Only on a page's own root.** On a profile pushed inside המאגר שלי, or
/// with the matchmaker area switched off, a horizontal drag is left alone.
/// Anything inside a page that scrolls sideways — a carousel, a swipeable
/// card — is deeper in the tree, claims the drag first and keeps it.
class _SwipeableBranches extends StatefulWidget {
  const _SwipeableBranches({
    required this.navigationShell,
    required this.children,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  State<_SwipeableBranches> createState() => _SwipeableBranchesState();
}

class _SwipeableBranchesState extends State<_SwipeableBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    // Create the ticker while mounted, including when no swipe ever occurs.
    // A lazy controller first accessed in dispose looks up a dead ancestor.
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  /// How far the current page is dragged, in pixels; positive is rightwards.
  double _drag = 0;
  bool _dragging = false;
  double _width = 1;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  int get _current => widget.navigationShell.currentIndex;

  /// The branch [step] places along the bar from the current one.
  int? _neighbour(int step) {
    final List<int> branches = _navBranches();
    final int at = branches.indexOf(_current);
    final int next = at + step;
    if (at < 0 || next < 0 || next >= branches.length) {
      return null;
    }
    return branches[next];
  }

  /// The page revealed by the current drag: the next one for a drag to the
  /// right, the previous one for a drag to the left.
  int? get _revealed => _drag > 0
      ? _neighbour(1)
      : _drag < 0
      ? _neighbour(-1)
      : null;

  bool _canSwipe() {
    final String path = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri.path;
    if (!shouldShowBottomNavigationBar(path)) {
      return false;
    }
    return !(_branchNavigatorKeys[_current].currentState?.canPop() ?? false);
  }

  void _onStart(DragStartDetails details) {
    if (_settle.isAnimating || !_canSwipe()) {
      return;
    }
    _dragging = true;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    setState(() {
      _drag += details.delta.dx;
      // No neighbour that way: a short, stiff give, not a slide into nothing.
      if (_revealed == null) {
        _drag = _drag.clamp(-24.0, 24.0) * 0.5;
      }
    });
  }

  void _onEnd(DragEndDetails details) {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    final double velocity = details.primaryVelocity ?? 0;
    final int? target = _revealed;
    final bool past =
        _drag.abs() > _width * 0.25 ||
        (velocity.abs() > 600 && velocity.sign == _drag.sign);
    if (target != null && past) {
      _animateTo(
        _drag.sign * _width,
        then: () {
          _AppShell._goToBranchRoot(target, widget.navigationShell);
          setState(() => _drag = 0);
        },
      );
    } else {
      _animateTo(0);
    }
  }

  void _animateTo(double end, {VoidCallback? then}) {
    final double start = _drag;
    final Animation<double> curve = CurvedAnimation(
      parent: _settle,
      curve: Curves.easeOutCubic,
    );
    void tick() => setState(() => _drag = start + (end - start) * curve.value);
    _settle
      ..reset()
      ..addListener(tick);
    _settle.forward().whenComplete(() {
      _settle.removeListener(tick);
      if (mounted) {
        then?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _width = constraints.maxWidth <= 0 ? 1 : constraints.maxWidth;
        final int? revealed = _revealed;
        return GestureDetector(
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          onHorizontalDragCancel: () {
            if (_dragging) {
              _dragging = false;
              _animateTo(0);
            }
          },
          child: Stack(
            children: <Widget>[
              for (int i = 0; i < widget.children.length; i++)
                Positioned.fill(
                  child: _branch(
                    i,
                    visible: i == _current || i == revealed,
                    dx: i == _current
                        ? _drag
                        : _drag > 0
                        ? _drag - _width
                        : _drag + _width,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _branch(int index, {required bool visible, required double dx}) {
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: Transform.translate(
          offset: Offset(dx, 0),
          // Its own layer: a swipe between tabs moves the page, it does not
          // repaint it on every frame of the drag. A hidden tab does not
          // rebuild on every change to the database; it catches up when it
          // is shown. See [BranchGate].
          child: RepaintBoundary(
            child: BranchGate(active: visible, child: widget.children[index]),
          ),
        ),
      ),
    );
  }
}
