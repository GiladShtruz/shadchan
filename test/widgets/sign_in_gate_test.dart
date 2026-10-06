import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/screens/account_gate_screens.dart';
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
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/sign_in_screen.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The sign-in gate, and the rule that it is a gate.
///
/// Three things are worth a test and none of them is the screen's appearance:
/// that a device with no account lands on it, that there is no way past it, and
/// that a device which has one goes straight through.
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
    await Hive.box<dynamic>('settings').deleteAll(<String>[
      'signIn.hasAccount',
      'signIn.mustVerifyEmail',
      'signIn.deletionPending',
    ]);
    AccountLoadingScreen.skipped = false;
    // The store's write-through cache is static and outlives the box, so a
    // test that wants a fresh install has to drop it as well as the key.
    SignInPromptStore.resetForTest();
    await Hive.box<dynamic>('settings').deleteAll(<String>[
      'workspace.entry',
      'workspace.matchmakerEnabled',
      'workspace.lastArea',
    ]);
    WorkspaceStore.resetForTest();
    AppRouter.router.go('/home');
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      hiveDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets('a device with no account lands on it, and cannot get past', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    // This matchmaker is already introduced — they used the app before an
    // account was compulsory — so they are asked to complete a registration,
    // and told their database comes with them.
    expect(find.text(SignInScreen.returningHeadline), findsOneWidget);
    expect(find.text(SignInScreen.returningBody), findsOneWidget);

    // All three ways in are on the one screen. Apple is drawn only on Apple's
    // own platforms, so it is deliberately not asserted here.
    expect(find.text('המשך עם Google'), findsOneWidget);
    expect(find.text('הרשמה עם מייל'), findsOneWidget);

    // And there is no way round it any more. This is the assertion that would
    // fail if somebody put the skip back.
    expect(find.text('המשך בלי להתחבר'), findsNothing);
    expect(find.text('המאגר שלי'), findsNothing);
  });

  testWidgets('a fresh install opens on the two ways in, before sign-in', (
    WidgetTester tester,
  ) async {
    final Box<dynamic> settings = Hive.box<dynamic>('settings');
    await tester.runAsync(
      () => settings.deleteAll(<String>['userName', 'userGender']),
    );
    try {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('ברוך הבא!'), findsOneWidget);
      expect(find.text('כניסה לשדכן'), findsOneWidget);
      expect(find.text('כניסה לרווק/ה'), findsOneWidget);

      await tester.tap(find.text('כניסה לרווק/ה'));
      await tester.pumpAndSettle();

      // Both routes sign in the same way.
      expect(WorkspaceStore.entryRoute, EntryRoute.cardOwner);
      expect(find.text('המשך עם Google'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await settings.put('userName', 'בודק');
        await settings.put('userGender', 'male');
      });
    }
  });

  testWidgets('Apple platforms use the guideline-compliant Apple button', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(SignInWithAppleButton), findsOneWidget);
      expect(find.text('המשך עם Apple'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android never offers Apple sign-in', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(SignInWithAppleButton), findsNothing);
      expect(find.text('המשך עם Apple'), findsNothing);
      expect(find.text('המשך עם Google'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the address form asks for a password before it will submit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    // Nothing is red before the first press: nobody is scolded for a form they
    // have not finished typing.
    expect(find.text('צריך למלא כתובת מייל'), findsNothing);

    await tester.ensureVisible(find.text('הרשמה עם מייל'));
    await tester.tap(find.text('הרשמה עם מייל'));
    await tester.pumpAndSettle();

    expect(find.text('צריך למלא כתובת מייל'), findsOneWidget);
    // Still here, because nothing was sent anywhere.
    expect(find.text(SignInScreen.returningHeadline), findsOneWidget);
  });

  testWidgets('the two questions swap, and only one of them is asked at once', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    // Registration leads: this screen is far more often on the path of
    // somebody opening the app for the first time.
    expect(find.text('הרשמה עם מייל'), findsOneWidget);
    expect(find.text('שכחתי סיסמה'), findsNothing);

    await tester.ensureVisible(find.text('כבר יש לי חשבון — התחברות'));
    await tester.tap(find.text('כבר יש לי חשבון — התחברות'));
    await tester.pumpAndSettle();

    expect(find.text('הרשמה עם מייל'), findsNothing);
    expect(find.text('התחברות'), findsOneWidget);
    // The one thing an address-and-password account needs that a provider
    // button does not.
    expect(find.text('שכחתי סיסמה'), findsOneWidget);
  });

  testWidgets('a device that already has an account goes straight through', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => Hive.box<dynamic>('settings').put('signIn.hasAccount', 'true'),
    );

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text(SignInScreen.returningHeadline), findsNothing);
    expect(find.text('המאגר שלי'), findsWidgets);
  });

  testWidgets('a brand-new install is asked to start, not to complete', (
    WidgetTester tester,
  ) async {
    final Box<dynamic> settings = Hive.box<dynamic>('settings');
    await tester.runAsync(() => settings.delete('userName'));

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    // "ברוך הבא!" first; the matchmaker's route then signs in as always.
    await tester.tap(find.text('כניסה לשדכן'));
    await tester.pumpAndSettle();

    expect(find.text(SignInScreen.headline), findsOneWidget);
    expect(find.text(SignInScreen.returningHeadline), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => settings.put('userName', 'בודק'));
  });
  testWidgets('a phone that never read its account waits for it, '
      'instead of asking a returning matchmaker to start again', (
    WidgetTester tester,
  ) async {
    final Box<dynamic> settings = Hive.box<dynamic>('settings');
    await tester.runAsync(() async {
      await settings.put('signIn.hasAccount', 'true');
      await settings.deleteAll(<String>['userName', 'userGender']);
    });
    try {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      // The sync is off in tests, so the read "fails" — which is the screen
      // that offers to try again or to go on.
      expect(find.text('לא הצלחנו לטעון את המאגר'), findsOneWidget);
      expect(find.text('ברוך הבא!'), findsNothing);

      await tester.tap(find.text('להמשיך בלי לחכות'));
      await tester.pumpAndSettle();
      expect(find.text('לא הצלחנו לטעון את המאגר'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await settings.put('userName', 'בודק');
        await settings.put('userGender', 'male');
      });
    }
  });

  testWidgets('an address not yet verified opens on the verification page', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>('settings').putAll(<String, Object?>{
        'signIn.hasAccount': 'true',
        'signIn.mustVerifyEmail': 'true',
      });
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('אימות כתובת המייל'), findsOneWidget);
    expect(find.text('המאגר שלי'), findsNothing);
  });

  testWidgets('an account waiting for deletion opens on the offer to restore', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>('settings').putAll(<String, Object?>{
        'signIn.hasAccount': 'true',
        'signIn.deletionPending': 'true',
      });
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('החשבון מתוזמן למחיקה'), findsOneWidget);
    expect(find.text('שחזור החשבון'), findsOneWidget);
    expect(find.text('המאגר שלי'), findsNothing);
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
      ChangeNotifierProvider<UserProfileProvider>(
        create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<PersonalCardProvider>(
        create: (_) => PersonalCardProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<CardAccessProvider>(
        create: (BuildContext context) => CardAccessProvider(
          people: context.read<PersonRepository>(),
          enabled: false,
        ),
      ),
      ChangeNotifierProvider<InboxProvider>(
        create: (_) => InboxProvider(enabled: false),
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
