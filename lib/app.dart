import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/incoming_backup_import_listener.dart';
import 'package:shadchan/widgets/incoming_shared_profile_listener.dart';
import 'package:shadchan/utils/app_router.dart';

class App extends StatelessWidget {
  const App({super.key});

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
          child: IncomingBackupImportListener(
            child: IncomingSharedProfileListener(
              child: child ?? const SizedBox.shrink(),
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
