import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/widgets/match_idea_card.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';

void main() {
  late Directory hiveDirectory;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    hiveDirectory = await Directory.systemTemp.createTemp('shadchan_test_');
    Hive.init(hiveDirectory.path);

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
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

    // Mark onboarding as completed so the app lands on the main shell instead
    // of the welcome screen.
    await settings.put('userName', 'בודק');
    await settings.put('userGender', 'male');
  });

  setUp(() async {
    await Hive.box<Person>('people').clear();
    await Hive.box<MatchIdea>('matches').clear();
    await Hive.box<MatchNote>('match_notes').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('App shows the bottom navigation tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());

    await tester.pumpAndSettle();

    expect(find.text('בית'), findsWidgets);
    expect(find.text('המאגר שלי'), findsWidgets);
    expect(find.text('רעיונות'), findsWidgets);
  });

  testWidgets('Match idea cards show all proposal names in a compact list', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 7, 6);
    final Person male1 = _testPerson(
      id: 'male1',
      firstName: 'דוד',
      lastName: 'כהן',
      gender: Gender.male,
      age: 25,
      now: now,
    );
    final Person female1 = _testPerson(
      id: 'female1',
      firstName: 'שרה',
      lastName: 'לוי',
      gender: Gender.female,
      age: 23,
      now: now,
    );
    final Person male2 = _testPerson(
      id: 'male2',
      firstName: 'יוסף',
      lastName: 'פרידמן',
      gender: Gender.male,
      age: 28,
      now: now,
    );
    final Person female2 = _testPerson(
      id: 'female2',
      firstName: 'רחל',
      lastName: 'מזרחי',
      gender: Gender.female,
      age: 26,
      now: now,
    );
    final ThemeData theme = ThemeData(useMaterial3: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                MatchIdeaCard(
                  match: _testMatch(
                    id: 'match1',
                    personAId: male1.id,
                    personBId: female1.id,
                    now: now,
                  ),
                  male: male1,
                  female: female1,
                  onTap: () {},
                  onOpenWhatsApp: (_) {},
                ),
                const SizedBox(height: 8),
                MatchIdeaCard(
                  match: _testMatch(
                    id: 'match2',
                    personAId: male2.id,
                    personBId: female2.id,
                    now: now,
                  ),
                  male: male2,
                  female: female2,
                  onTap: () {},
                  onOpenWhatsApp: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('דוד כהן, 25'), findsOneWidget);
    expect(find.text('שרה לוי, 23'), findsOneWidget);
    expect(find.text('יוסף פרידמן, 28'), findsOneWidget);
    expect(find.text('רחל מזרחי, 26'), findsOneWidget);
  });
}

Person _testPerson({
  required String id,
  required String firstName,
  required String lastName,
  required Gender gender,
  required int age,
  required DateTime now,
}) {
  return Person(
    id: id,
    firstName: firstName,
    lastName: lastName,
    gender: gender,
    manualAge: age,
    createdAt: now,
    updatedAt: now,
  );
}

MatchIdea _testMatch({
  required String id,
  required String personAId,
  required String personBId,
  required DateTime now,
}) {
  return MatchIdea(
    id: id,
    personAId: personAId,
    personBId: personBId,
    status: MatchStatus.idea,
    currentHandler: CurrentHandler.me,
    createdAt: now,
    updatedAt: now,
  );
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
    ],
    child: const App(),
  );
}
