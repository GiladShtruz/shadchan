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

/// "רעיון חדש" watches [MatchRepository], so the moment it creates a proposal
/// it rebuilds — and the proposal it just made answers its own duplicate check.
/// The warning used to flash for the frames before the router left the screen.
void main() {
  const String duplicateWarning = 'ההצעה הזו כבר קיימת במערכת';
  final DateTime now = DateTime(2026, 8, 18);

  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('create_match_');
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
  });

  setUp(() async {
    people = await Hive.openBox<Person>('people');
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    await people.clear();
    await matches.clear();
    await notes.clear();
    await Hive.box<dynamic>('settings').clear();

    for (final Person person in <Person>[
      _person('male', 'הלל', Gender.male, now),
      _person('female', 'כרמל', Gender.female, now),
    ]) {
      await people.put(person.id, person);
    }
  });

  tearDownAll(() async {
    // No `Hive.close()`: the repository's writes are issued inside the widget
    // tester's fake-async zone, so the box has work outstanding that closing
    // would wait on for ever. The boxes die with the test process anyway; only
    // the files on disk need clearing up.
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows keeps the open box files locked. Harmless — it is a temp dir.
    }
  });

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<PersonRepository>(
          create: (_) => PersonRepository(people),
        ),
        ChangeNotifierProvider<MatchRepository>(
          create: (_) => MatchRepository(matches, notes),
        ),
        ChangeNotifierProvider<ReligiousLevelsProvider>(
          create: (_) => ReligiousLevelsProvider(Hive.box<dynamic>('settings')),
        ),
        ChangeNotifierProvider<UserProfileProvider>(
          create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );
  }

  testWidgets('a genuinely new pair never shows the duplicate warning', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(const CreateMatchScreen(preSelectedPersonId: 'male')),
    );
    await tester.pump();

    await _pickFemale(tester);

    expect(find.text(duplicateWarning), findsNothing);

    await tester.tap(find.text('הוספת הצעה'));
    // Two bare pumps: the repository has notified and this screen has rebuilt
    // with the new proposal in the box. This is exactly the window the warning
    // used to appear in.
    await tester.pump();
    expect(find.text(duplicateWarning), findsNothing);
    await tester.pump();
    expect(find.text(duplicateWarning), findsNothing);

    expect(matches.length, 1);

    // Tear the tree down inside the test: the providers own the repositories,
    // and `Hive.close()` in `tearDownAll` will not finish while they are still
    // live.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Chooses the woman through the picker the screen actually opens.
///
/// Timed pumps rather than `pumpAndSettle`: the picker sheet keeps an
/// animation running, so settling never returns.
Future<void> _pickFemale(WidgetTester tester) async {
  // The card's title is a label; the empty slot under it is the tap target.
  await tester.tap(find.text('בחירת בחורה').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await tester.tap(find.text('כרמל לוי').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
