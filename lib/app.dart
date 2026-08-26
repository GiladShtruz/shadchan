import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/achievement_watcher.dart';
import 'package:shadchan/widgets/app_update_prompt.dart';
import 'package:shadchan/widgets/cloud_sync_scheduler.dart';
import 'package:shadchan/widgets/incoming_backup_import_listener.dart';
import 'package:shadchan/widgets/incoming_shared_profile_listener.dart';
import 'package:shadchan/widgets/startup_crash_notice.dart';
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
                      // Only ever speaks when the previous launch died before
                      // the app appeared; see the note there.
                      child: StartupCrashNotice(
                        child: child ?? const SizedBox.shrink(),
                      ),
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

class _ExitThroughPeopleBackButtonDispatcher extends RootBackButtonDispatcher {
  @override
  Future<bool> didPopRoute() {
    final router = AppRouter.router;
    if (router.canPop()) {
      return super.didPopRoute();
    }

    final String currentPath = router.routeInformationProvider.value.uri.path;
    if (currentPath != '/home') {
      router.go('/home');
      return Future<bool>.value(true);
    }

    return super.didPopRoute();
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
