import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/community_activity_screen.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/community_achievements.dart';
import 'package:shadchan/utils/enums.dart';

/// "הפעילות שלי".
///
/// The two things worth pinning down are the two the redesign is *for*: the
/// page opens by naming the best real thing in the database rather than
/// congratulating somebody for installing an app, and the milestone ladders say
/// where the next rung is instead of only where the last one was.
void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('activity_screen_');
    Hive.init(directory.path);
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
    people = await Hive.openBox<Person>('people');
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await people.clear();
    await matches.clear();
    await notes.clear();
    await Hive.box<dynamic>('settings').clear();
    await Hive.box<dynamic>('settings').put('userName', 'רבקה');
    await Hive.box<dynamic>('settings').put('userGender', 'female');
  });

  tearDownAll(() async {
    // No `Hive.close()` — see `create_match_screen_test.dart` for why.
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows keeps the open box files locked. Harmless — it is a temp dir.
    }
  });

  Widget wrap() {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<PersonRepository>(
          create: (_) => PersonRepository(people),
        ),
        ChangeNotifierProvider<MatchRepository>(
          create: (_) => MatchRepository(matches, notes),
        ),
        ChangeNotifierProvider<UserProfileProvider>(
          create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
        ),
        ChangeNotifierProvider<CommunityProvider>(
          create: (_) => CommunityProvider(),
        ),
        // `connect: () async {}` keeps `Firebase.initializeApp` out of the
        // fake-async zone, where it never completes. Signed out, so the two
        // community cards are the invitation and nothing reaches the network.
        ChangeNotifierProvider<AccountProvider>(
          create: (_) => AccountProvider(connect: () async {}),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: CommunityActivityScreen(),
        ),
      ),
    );
  }

  Person person(String id, String name, Gender gender) {
    return Person(
      id: id,
      firstName: name,
      lastName: 'כהן',
      gender: gender,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );
  }

  testWidgets('an empty database is invited, not congratulated', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The header greets by first name and says the one true thing there is to
    // say about a database with nothing in it.
    expect(find.text('שלום, רבקה'), findsOneWidget);
    expect(find.text('הכול מתחיל מחבר אחד'), findsOneWidget);
    // Nothing here claims an achievement that has not happened.
    expect(find.textContaining('בזכותך'), findsNothing);
  });

  testWidgets('the header names the best real thing in the database', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await people.put('m', person('m', 'הלל', Gender.male));
    await people.put('f', person('f', 'כרמל', Gender.female));
    await matches.put(
      'married',
      MatchIdea(
        id: 'married',
        personAId: 'm',
        personBId: 'f',
        status: MatchStatus.married,
        currentHandler: CurrentHandler.me,
        createdAt: DateTime(2026, 8, 2),
        updatedAt: DateTime(2026, 8, 10),
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pump();

    // A wedding outranks every other count on the page, and it is said as a
    // sentence about a home rather than as a figure in a box.
    expect(find.text('בית אחד כבר קם בזכותך'), findsOneWidget);
    // The four counts and the ladders are still there under it.
    expect(find.text('הדרך שלך עד היום'), findsOneWidget);
    expect(find.text('אבני דרך'), findsOneWidget);
    expect(find.text('הקצב שלך'), findsOneWidget);
    // Two friends, so the friends ladder points at the first rung.
    expect(find.textContaining('עוד 8 חברים ל־10'), findsOneWidget);
  });

  group('the ladders', () {
    test('next() is the rung above, and null at the top', () {
      expect(CommunityAchievements.next(CommunityAchievements.friendMilestones, 0), 10);
      expect(CommunityAchievements.next(CommunityAchievements.friendMilestones, 10), 25);
      expect(
        CommunityAchievements.next(CommunityAchievements.friendMilestones, 1000),
        isNull,
      );
    });

    test('couples keep climbing in tens past the written ladder', () {
      // `reached` reads 74 as 70, so `next` has to answer 80 — otherwise the
      // one ladder that never ends is the one with no progress bar.
      expect(CommunityAchievements.reached(CommunityAchievements.coupleMilestones, 74), 70);
      expect(CommunityAchievements.next(CommunityAchievements.coupleMilestones, 74), 80);
    });
  });

  group('a read that never happened', () {
    test('is not the same as a community that did nothing', () {
      expect(CommunityTotals.empty.resolved, isFalse);
      expect(CommunityLeaderboard.empty.resolved, isFalse);
      // A figure that genuinely came back — including a real zero — is
      // resolved, and callers may cache it.
      const CommunityTotals real = CommunityTotals(
        points: 0,
        activeMatchmakers: 0,
        friends: 0,
        ideas: 0,
        couples: 0,
        engagements: 0,
      );
      expect(real.resolved, isTrue);
    });
  });
}
