import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/utils/enums.dart';

/// What the Android back key does, and — much more importantly — what it must
/// never do.
///
/// **A back press may only close the app from the home screen with nothing on
/// top of it.** Everything else has somewhere to go back to, and the one that
/// was actually getting this wrong is a full-screen task flow opened from בית:
/// "הוספת אנשי קשר" is pushed, so the location still reads `/home` while it is
/// on screen, and a dispatcher that trusted the location closed the app from
/// underneath it. See `_ExitThroughPeopleBackButtonDispatcher`.
void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('shadchan_back_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MatchIdeaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(MatchNoteAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MatchStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(CurrentHandlerAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(RegionAdapter());
    await Hive.openBox<Person>('people');
    await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
    final Box<dynamic> settings = await Hive.openBox<dynamic>('settings');
    await settings.put('userName', 'בודק');
    await settings.put('userGender', 'male');
    await settings.put('userIsSingle', false);
    await settings.put('signIn.hasAccount', 'true');
    await settings.put('signIn.promptAnswered', 'true');
    await settings.put('community.inWhatsAppGroup', 'true');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('back out of "הוספת אנשי קשר" lands on the home screen', (
    WidgetTester tester,
  ) async {
    AppRouter.router.go('/home');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    AppRouter.router.push('/people/import');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('הוספת אנשי קשר'), findsOneWidget);

    // The location is *not* `/people/import`: an imperatively pushed page is
    // deliberately left out of `RouteMatchList.uri`. This is exactly the state
    // the dispatcher used to read as "we are on the home screen, so leave".
    expect(AppRouter.router.routeInformationProvider.value.uri.path, '/home');

    final bool handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Handled by the app — never passed on to Android as "nothing to pop".
    expect(handled, isTrue);
    expect(find.text('הוספת אנשי קשר'), findsNothing);
    expect(AppRouter.router.routeInformationProvider.value.uri.path, '/home');
  });

  testWidgets('back from another tab goes to בית before it goes anywhere', (
    WidgetTester tester,
  ) async {
    AppRouter.router.go('/people');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final bool handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(AppRouter.router.routeInformationProvider.value.uri.path, '/home');
  });
}

Widget _app() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PersonRepository>(
        create: (_) => PersonRepository(Hive.box<Person>('people')),
      ),
      ChangeNotifierProvider<MatchRepository>(
        create: (_) => MatchRepository(
          Hive.box<MatchIdea>('matches'),
          Hive.box<MatchNote>('match_notes'),
        ),
      ),
      ChangeNotifierProvider<ThemeModeProvider>(
        create: (_) => ThemeModeProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<ReligiousLevelsProvider>(
        create: (_) => ReligiousLevelsProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<UserProfileProvider>(
        create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<AccountProvider>(
        create: (_) => AccountProvider(connect: () async {}),
      ),
      ChangeNotifierProvider<SyncProvider>(
        create: (_) =>
            SyncProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      ChangeNotifierProvider<TipsProvider>(
        create: (_) =>
            TipsProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      ChangeNotifierProvider<CommunityProvider>(
        create: (_) => CommunityProvider(connect: () async {}),
      ),
      ChangeNotifierProvider<SupportInboxProvider>(
        create: (_) =>
            SupportInboxProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
    ],
    child: const App(checkForUpdates: false),
  );
}
