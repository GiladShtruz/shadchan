import 'dart:async';
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
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/incoming_shared_profile_listener.dart';

/// A card shared into the app must always land in the intake flow.
///
/// **The second share is the one that was broken.** The intake screen leaves by
/// `pushReplacement`, which drops the imperative route go_router was holding
/// the `push` completer for, so the listener's await never returned and its
/// "one at a time" latch stayed closed for the rest of the launch. Sharing
/// again then did nothing visible at all: the app simply came forward on
/// whatever screen it had been left on, which is exactly what was reported.
void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('shadchan_share_');
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

  testWidgets('a second shared card opens the intake flow again', (
    WidgetTester tester,
  ) async {
    final _FakeSharedProfiles shares = _FakeSharedProfiles();

    AppRouter.router.go('/home');
    await tester.pumpWidget(_app(shares));
    await tester.pumpAndSettle();

    shares.emit('שרה כהן, בת 24, ירושלים');
    await tester.pumpAndSettle();
    expect(find.text('פרטים משותפים'), findsOneWidget);

    // How the intake screen leaves, and the move that used to strand the
    // listener: `pushReplacement` drops the imperative route go_router held
    // the `push` completer for. Driven through the router rather than by
    // tapping "יצירת איש קשר חדש", only because the form that button opens
    // starts Firebase and a 30-second timer with it, which no widget test can
    // settle; the route move under test is the same one either way.
    AppRouter.router.pushReplacement('/people');
    await tester.pumpAndSettle();
    expect(find.text('פרטים משותפים'), findsNothing);

    shares.emit('דוד לוי, בן 27, בני ברק');
    await tester.pumpAndSettle();
    expect(find.text('פרטים משותפים'), findsOneWidget);

    shares.dispose();
  });
}

/// Stands in for the platform channel, so a share can be delivered on demand.
class _FakeSharedProfiles implements IncomingSharedProfileSource {
  final StreamController<IncomingSharedProfileDraft> _controller =
      StreamController<IncomingSharedProfileDraft>.broadcast();

  int _id = 0;

  void emit(String text) {
    _controller.add(
      IncomingSharedProfileDraft(
        id: 'share-${_id++}',
        text: text,
        filePaths: const <String>[],
      ),
    );
  }

  void dispose() => _controller.close();

  @override
  Stream<IncomingSharedProfileDraft> get incomingDrafts => _controller.stream;

  @override
  Future<List<IncomingSharedProfileDraft>> takePendingDrafts() async {
    return const <IncomingSharedProfileDraft>[];
  }
}

Widget _app(IncomingSharedProfileSource shares) {
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
    // Above `App` rather than inside it: the listener drives `AppRouter.router`
    // directly, so it works from either side of the `MaterialApp`, and this is
    // the only place a fake source can be handed in. `App`'s own listener sits
    // on the real channel, which answers nothing under a test binding.
    child: IncomingSharedProfileListener(
      profileService: shares,
      child: const App(checkForUpdates: false),
    ),
  );
}
