import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/achievement_watcher.dart';
import 'package:shadchan/widgets/app_update_prompt.dart';
import 'package:shadchan/widgets/cloud_sync_scheduler.dart';
import 'package:shadchan/widgets/incoming_backup_import_listener.dart';
import 'package:shadchan/widgets/incoming_shared_profile_listener.dart';
import 'package:shadchan/utils/app_router.dart';

class App extends StatelessWidget {
  const App({super.key, this.checkForUpdates = true});

  /// Passed straight to `AppUpdatePrompt.enabled`; see the note there for why
  /// the store check has to be switchable off from a test.
  final bool checkForUpdates;

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode = context.watch<ThemeModeProvider>().themeMode;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'שדכן',
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routeInformationProvider: AppRouter.router.routeInformationProvider,
      routeInformationParser: AppRouter.router.routeInformationParser,
      routerDelegate: AppRouter.router.routerDelegate,
      backButtonDispatcher: _ExitThroughPeopleBackButtonDispatcher(),
      locale: const Locale('he'),
      supportedLocales: const <Locale>[Locale('he')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          // Above the router rather than on any one screen: every field in the
          // app is inside it, so a tap on bare paper anywhere puts the keyboard
          // away. See [DismissKeyboardOnTap].
          child: DismissKeyboardOnTap(
            child: AppUpdatePrompt(
              enabled: checkForUpdates,
              child: CloudSyncScheduler(
                // Above the router rather than on a screen: a milestone is
                // earned wherever the matchmaker happens to be working, and this
                // has to be watching from all of them.
                child: AchievementWatcher(
                  child: IncomingBackupImportListener(
                    child: IncomingSharedProfileListener(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The last thing between a back press and the app closing.
///
/// Android's back is one gesture with two very different meanings, and only
/// the router can tell them apart: on a pushed page it means "go back", and on
/// the first page of the app it means "leave". go_router answers the first,
/// and what is left over lands here.
///
/// **Nothing leaves the app except the home tab with nothing on top of it.**
/// A back press on המאגר שלי or on הרעיונות שלי goes to בית — the tabs are a
/// hierarchy, and the top of it is the home screen — and only a second press,
/// from there, closes the app.
///
/// **The location is not a reliable answer to "what is on screen".** A page
/// opened with `push` is an `ImperativeRouteMatch`, and `RouteMatchList.uri`
/// deliberately ignores those: standing on "הוספת אנשי קשר", pushed from the
/// home tab, `uri.path` still reads `/home`. So a back press that go_router
/// declined to handle while such a page was up used to satisfy the
/// `== '/home'` test and close the app from underneath a full-screen task
/// flow — which is what "back out of adding contacts and the app disappears"
/// was. Whether a pushed page is on screen is asked of the match tree instead,
/// where the answer is actually kept.
class _ExitThroughPeopleBackButtonDispatcher extends RootBackButtonDispatcher {
  @override
  Future<bool> didPopRoute() {
    final GoRouter router = AppRouter.router;
    if (router.canPop()) {
      return super.didPopRoute();
    }

    final RouteMatchList configuration =
        router.routerDelegate.currentConfiguration;
    // Something is on screen that the location does not name, and it cannot be
    // popped. Going to the home screen is the one thing left that is not
    // closing the app on top of somebody's work.
    if (_hasPushedPage(configuration.matches) ||
        configuration.uri.path != '/home') {
      router.go('/home');
      return Future<bool>.value(true);
    }

    return super.didPopRoute();
  }

  /// Whether anything in the tree got there through `push` rather than through
  /// the location. Recursive, because a page pushed onto a tab sits inside that
  /// branch's `ShellRouteMatch` rather than at the top of the list.
  static bool _hasPushedPage(List<RouteMatchBase> matches) {
    for (final RouteMatchBase match in matches) {
      if (match is ImperativeRouteMatch) {
        return true;
      }
      if (match is ShellRouteMatch && _hasPushedPage(match.matches)) {
        return true;
      }
    }
    return false;
  }
}

/// Taps on bare paper close the keyboard.
///
/// **Because on iPhone there is nothing else that does.** Android has a system
/// back key that dismisses the keyboard; iOS has nothing, so a field with no
/// "done" affordance — a search row, a multi-line note, a sheet — leaves the
/// keyboard covering half the screen with no way out but scrolling blindly or
/// leaving the page. Every phone app answers this the same way: a tap on the
/// page behind puts it away.
///
/// **Translucent, and therefore harmless.** The recognizer joins the arena at
/// the very end of the hit-test path — it is the outermost widget in the app —
/// so any button, list row or field under the finger wins the tap and behaves
/// exactly as it always did. Only a tap that nothing else claimed reaches this.
///
/// The unfocus is a closure and not `primaryFocus?.unfocus` handed over
/// directly: the latter reads the focused node *once, at build time*, which on
/// the app's own root build is null — which is how this widget spent its first
/// life doing nothing at all.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
