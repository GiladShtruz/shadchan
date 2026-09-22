import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/create_match_screen.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';

/// The picker's squares are the same list in another shape: the same people,
/// still a tap from being chosen, and one icon away from the rows.
///
/// A file of its own on purpose. `create_match_screen_test.dart` creates a
/// proposal inside the widget tester's fake-async zone, and a second test there
/// hangs in `setUp` behind a Hive write that zone never finishes.
void main() {
  final DateTime now = DateTime(2026, 8, 18);
  late Directory directory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('picker_grid_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(MatchStatusAdapter());
    Hive.registerAdapter(CurrentHandlerAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    await Hive.openBox<dynamic>('settings');
    final Box<Person> people = await Hive.openBox<Person>('people');
    await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
    for (final Person person in <Person>[
      _person('male', 'הלל', Gender.male, now),
      _person('female', 'כרמל', Gender.female, now),
    ]) {
      await people.put(person.id, person);
    }
  });

  tearDownAll(() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows keeps the open box files locked. Harmless — it is a temp dir.
    }
  });

  testWidgets('the picker offers squares, and a square picks the person', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<PersonRepository>(
            create: (_) => PersonRepository(Hive.box<Person>('people')),
          ),
          ChangeNotifierProvider<MatchRepository>(
            create: (_) => MatchRepository(
              Hive.box<MatchIdea>('matches'),
              Hive.box<MatchNote>('match_notes'),
            ),
          ),
          ChangeNotifierProvider<ReligiousLevelsProvider>(
            create: (_) =>
                ReligiousLevelsProvider(Hive.box<dynamic>('settings')),
          ),
          ChangeNotifierProvider<UserProfileProvider>(
            create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CreateMatchScreen(preSelectedPersonId: 'male'),
          ),
        ),
      ),
    );
    await tester.pump();

    // Timed pumps rather than `pumpAndSettle`: the sheet keeps an animation
    // running, so settling never returns.
    await tester.tap(find.text('בחירת בחורה').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('תצוגת ריבועים'));
    await tester.pump();
    expect(find.byTooltip('תצוגת רשימה'), findsOneWidget);
    expect(find.byType(SliverGrid), findsWidgets);

    await tester.tap(find.text('כרמל לוי').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The sheet closed on the choice.
    expect(find.byTooltip('תצוגת רשימה'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Person _person(String id, String name, Gender gender, DateTime now) {
  return Person(
    id: id,
    firstName: name,
    lastName: 'לוי',
    gender: gender,
    manualAge: 26,
    phone: '0501234567',
    createdAt: now,
    updatedAt: now,
  );
}
