import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/dialogs/details_message_dialog.dart';
import 'package:shadchan/dialogs/hidden_contacts_dialog.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
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
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/utils/app_router.dart';

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

  test('Bottom navigation is limited to the three primary paths', () {
    expect(shouldShowBottomNavigationBar('/home'), isTrue);
    expect(shouldShowBottomNavigationBar('/people'), isTrue);
    expect(shouldShowBottomNavigationBar('/matches'), isTrue);
    expect(shouldShowBottomNavigationBar('/people/person-id'), isFalse);
    expect(shouldShowBottomNavigationBar('/people/add'), isFalse);
    expect(shouldShowBottomNavigationBar('/matches/add'), isFalse);
    expect(shouldShowBottomNavigationBar('/dashboard'), isFalse);
    expect(shouldShowBottomNavigationBar('/settings'), isFalse);
  });

  testWidgets('Closing the details-message dialog does not break the overlay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DetailsMessageDialog(
                  initialMessage: 'הודעת בדיקה',
                  showReset: false,
                ),
              ),
              child: const Text('פתיחה'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();
    expect(find.text('עריכת נוסח ההודעה'), findsOneWidget);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(find.text('עריכת נוסח ההודעה'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancelling quick contact details leaves the draft unchanged', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now();
    final Person draft = Person(
      id: 'pending-contact',
      firstName: 'רחל',
      lastName: 'כהן',
      gender: Gender.unknown,
      phone: '0542222222',
      createdAt: now,
      updatedAt: now,
      needsReview: true,
      hidden: true,
    );
    bool? result;

    await tester.pumpWidget(
      ChangeNotifierProvider<ReligiousLevelsProvider>(
        create: (_) => ReligiousLevelsProvider(Hive.box<dynamic>('settings')),
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return TextButton(
                onPressed: () async {
                  result = await QuickUpdateDialog.show(context, draft);
                },
                child: const Text('פתיחה'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();
    expect(find.text('ביטול'), findsOneWidget);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(draft.gender, Gender.unknown);
    expect(draft.religiousLevel, isNull);
    expect(draft.age, isNull);
    expect(draft.hidden, isTrue);
    expect(draft.needsReview, isTrue);
  });

  testWidgets('Hidden contacts dialog restores contacts individually', (
    WidgetTester tester,
  ) async {
    final List<String> restoredPhones = <String>[];
    final List<ContactImportCandidate> candidates = <ContactImportCandidate>[
      const ContactImportCandidate(
        deviceContactId: 'hidden-1',
        displayName: 'איש קשר מוסתר',
        phone: '050-1111111',
        normalizedPhone: '0501111111',
        alreadyExists: false,
        hasAdditionalPhones: false,
        isFilteredByName: true,
      ),
      const ContactImportCandidate(
        deviceContactId: 'hidden-2',
        displayName: 'איש קשר נוסף',
        phone: '052-2222222',
        normalizedPhone: '0522222222',
        alreadyExists: false,
        hasAdditionalPhones: false,
        isFilteredByName: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return TextButton(
              onPressed: () => HiddenContactsDialog.show(
                context,
                candidates: candidates,
                onRestore: (ContactImportCandidate candidate) async {
                  restoredPhones.add(candidate.normalizedPhone);
                },
              ),
              child: const Text('פתיחת מוסתרים'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('פתיחת מוסתרים'));
    await tester.pumpAndSettle();
    expect(find.text('איש קשר מוסתר'), findsOneWidget);
    expect(find.text('איש קשר נוסף'), findsOneWidget);

    await tester.tap(find.text('הצגה').first);
    await tester.pumpAndSettle();

    expect(restoredPhones, <String>['0501111111']);
    expect(find.text('איש קשר מוסתר'), findsNothing);
    expect(find.text('איש קשר נוסף'), findsOneWidget);
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
