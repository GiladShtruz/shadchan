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
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/sign_in_screen.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/utils/enums.dart';

/// The one-time sign-in invitation, and the rule that it is an invitation.
///
/// Two things are worth a test and neither is the screen's appearance: that an
/// onboarded matchmaker who has never answered lands on it, and that answering
/// "המשך בלי להתחבר" gets them all the way into the app and keeps them there.
void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    hiveDirectory = await Directory.systemTemp.createTemp('shadchan_signin_');
    Hive.init(hiveDirectory.path);

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MatchIdeaAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MatchNoteAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GenderAdapter());
    }
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

    await Hive.openBox<Person>('people');
    await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
    final Box<dynamic> settings = await Hive.openBox<dynamic>('settings');
    // Onboarded, so the welcome screen is behind us and the only thing left
    // between this matchmaker and the app is the sign-in question.
    await settings.put('userName', 'בודק');
    await settings.put('userGender', 'male');
    await settings.put('userIsSingle', false);
  });

  setUp(() async {
    await Hive.box<dynamic>('settings').delete('signIn.promptAnswered');
    // The store's write-through cache is static and outlives the box, so a
    // test that wants a fresh install has to drop it as well as the key.
    SignInPromptStore.resetForTest();
    AppRouter.router.go('/home');
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      hiveDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets('an onboarded matchmaker who has never answered lands on it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text(SignInScreen.headline), findsOneWidget);
    expect(find.text('המשך עם Google'), findsOneWidget);

    // The way past is present and reachable, not hidden behind a scroll or a
    // delay. A skip that has to be hunted for is a dark pattern.
    expect(find.text('המשך בלי להתחבר'), findsOneWidget);

    // And the app itself is not yet behind it.
    expect(find.text('המאגר שלי'), findsNothing);
  });

  testWidgets('skipping asks once more, then lets them all the way through', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('המשך בלי להתחבר'));
    await tester.pumpAndSettle();

    // The second question says what is actually at stake, and recommends
    // signing in — without making the other answer unreachable.
    expect(find.text(ContinueWithoutAccountDialog.title), findsOneWidget);
    expect(find.text('התחברות ושמירת המאגר'), findsOneWidget);

    await tester.tap(find.text('בכל זאת להמשיך בלי להתחבר'));
    await tester.pumpAndSettle();

    expect(find.text(SignInScreen.headline), findsNothing);
    expect(find.text('המאגר שלי'), findsWidgets);
  });

  testWidgets('the answer sticks: a later launch goes straight to the app', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => Hive.box<dynamic>('settings').put('signIn.promptAnswered', 'true'),
    );

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text(SignInScreen.headline), findsNothing);
    expect(find.text('המאגר שלי'), findsWidgets);
  });

  testWidgets('backing out of the second question leaves them on the screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('המשך בלי להתחבר'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('התחברות ושמירת המאגר'));
    await tester.pumpAndSettle();

    // Nothing was recorded, so the question is still open.
    expect(find.text(SignInScreen.headline), findsOneWidget);
  });
}

Widget _buildTestApp() {
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
      // `connect: () async {}` for the reason documented on AccountProvider:
      // `Firebase.initializeApp` never completes inside the fake-async zone.
      // `isSignedIn` is false, which is the state this whole file is about.
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
        create: (_) => CommunityProvider(),
      ),
    ],
    child: const App(checkForUpdates: false),
  );
}
