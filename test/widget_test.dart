import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    AppRouter.router.go('/home');
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

  test('Bottom navigation includes primary paths and person profiles', () {
    expect(shouldShowBottomNavigationBar('/home'), isTrue);
    expect(shouldShowBottomNavigationBar('/people'), isTrue);
    expect(shouldShowBottomNavigationBar('/matches'), isTrue);
    expect(shouldShowBottomNavigationBar('/people/person-id'), isTrue);
    expect(shouldShowBottomNavigationBar('/people/add'), isFalse);
    expect(shouldShowBottomNavigationBar('/people/import'), isFalse);
    expect(shouldShowBottomNavigationBar('/matches/add'), isFalse);
    expect(shouldShowBottomNavigationBar('/dashboard'), isFalse);
    expect(shouldShowBottomNavigationBar('/settings'), isFalse);
  });

  testWidgets(
    'Person profile keeps app navigation and expands its card inline',
    (WidgetTester tester) async {
      final DateTime now = DateTime(2026, 7, 27);
      final Person profile = Person(
        id: 'profile-person',
        firstName: 'הלל',
        lastName: 'אבולעפיה',
        gender: Gender.male,
        phone: '0501111111',
        manualAge: 27,
        description: 'שורה ראשונה\nשורה שנייה\nסוף הכרטיס המלא',
        createdAt: now,
        updatedAt: now,
      );
      final Person other = Person(
        id: 'other-person',
        firstName: 'כרמל',
        lastName: 'לוי',
        gender: Gender.female,
        phone: '0522222222',
        manualAge: 25,
        createdAt: now,
        updatedAt: now,
      );
      final MatchIdea match = _testMatch(
        id: 'profile-match',
        personAId: profile.id,
        personBId: other.id,
        now: now,
      );
      await tester.runAsync(() async {
        await Hive.box<Person>('people').put(profile.id, profile);
        await Hive.box<Person>('people').put(other.id, other);
        await Hive.box<MatchIdea>('matches').put(match.id, match);
      });

      await tester.pumpWidget(_buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      AppRouter.router.go('/people/${profile.id}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('בית'), findsOneWidget);
      expect(find.text('המאגר שלי'), findsOneWidget);
      expect(find.text('רעיונות'), findsOneWidget);
      expect(find.text('הלל'), findsOneWidget);
      expect(find.text('התאמות'), findsOneWidget);
      expect(find.text('לפתיחת הצעה'), findsOneWidget);
      expect(find.text('הכרטיס שלו'), findsNothing);

      final Finder showFullCard = find.text('הצג כרטיס מלא');
      await tester.ensureVisible(showFullCard);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(showFullCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('סוף הכרטיס המלא'), findsWidgets);
      expect(find.byTooltip('שיתוף הכרטיס המלא'), findsOneWidget);
      expect(find.text('סגירת הכרטיס המלא'), findsOneWidget);

      await tester.tap(find.byTooltip('שיתוף הכרטיס המלא'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('שיתוף הכרטיס המלא'), findsOneWidget);
      expect(find.text('שיתוף דרך WhatsApp'), findsOneWidget);
      await tester.tapAt(const Offset(12, 12));
      await tester.pump(const Duration(milliseconds: 250));

      await tester.scrollUntilVisible(
        find.text('הצעות פתוחות (1)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('כרמל לוי'), findsOneWidget);
      expect(find.byTooltip('WhatsApp עם כרמל לוי'), findsOneWidget);
    },
  );

  testWidgets('Match detail shows one derived state and compact pair actions', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 7, 27);
    final Person male = _testPerson(
      id: 'detail-male',
      firstName: 'הלל',
      lastName: 'אבולעפיה',
      gender: Gender.male,
      age: 27,
      now: now,
    );
    final Person female = _testPerson(
      id: 'detail-female',
      firstName: 'כרמל',
      lastName: 'לוי',
      gender: Gender.female,
      age: 25,
      now: now,
    );
    final MatchIdea match = _testMatch(
      id: 'detail-match',
      personAId: male.id,
      personBId: female.id,
      now: now,
    );
    await tester.runAsync(() async {
      await Hive.box<Person>('people').put(male.id, male);
      await Hive.box<Person>('people').put(female.id, female);
      await Hive.box<MatchIdea>('matches').put(match.id, match);
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/matches/${match.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('פרטי הצעה'), findsOneWidget);
    expect(find.text('הלל אבולעפיה'), findsOneWidget);
    expect(find.text('כרמל לוי'), findsOneWidget);
    expect(find.text('פתוחה'), findsOneWidget);
    expect(find.text('אפשר לקדם את ההצעה'), findsOneWidget);
    expect(find.text('התחילו לצאת'), findsOneWidget);
    expect(find.text('סטטוס הצעה'), findsNothing);
    expect(find.text('איפה זה עומד?'), findsNothing);
    expect(find.textContaining('עודכן'), findsNothing);

    await tester.tap(find.text('פנוי').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('תפוס'), findsOneWidget);
    expect(find.text('בהפסקה'), findsOneWidget);
  });

  testWidgets('Match detail keeps full names and visible proposal actions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final DateTime now = DateTime(2026, 7, 27);
    final Person male = _testPerson(
      id: 'wide-male',
      firstName: 'יצחק',
      lastName: 'ברגר מסינגר',
      gender: Gender.male,
      age: 27,
      now: now,
    );
    final Person female = _testPerson(
      id: 'wide-female',
      firstName: 'אדל',
      lastName: 'ביטון קלרמן',
      gender: Gender.female,
      age: 25,
      now: now,
    );
    final MatchIdea match = _testMatch(
      id: 'wide-match',
      personAId: male.id,
      personBId: female.id,
      now: now,
    );
    await tester.runAsync(() async {
      await Hive.box<Person>('people').put(male.id, male);
      await Hive.box<Person>('people').put(female.id, female);
      await Hive.box<MatchIdea>('matches').put(match.id, match);
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/matches/${match.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Both names render in full instead of being cut after the first line.
    for (final String name in <String>['יצחק ברגר מסינגר', 'אדל ביטון קלרמן']) {
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text(name),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: name);
    }

    // The reminder and the related-contact action are real, visible rows.
    expect(find.text('הוספת תזכורת'), findsOneWidget);
    expect(find.text('הוספת איש קשר שקשור להצעה'), findsOneWidget);

    // The journal no longer has a button that only focuses the note field.
    await tester.dragUntilVisible(
      find.text('יומן ההצעה'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await tester.pump();
    expect(find.text('יומן ההצעה'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'הוספת הערה'), findsNothing);
  });

  testWidgets('Tapping a journal note opens one edit/delete dialog', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 7, 27);
    final Person male = _testPerson(
      id: 'note-male',
      firstName: 'הלל',
      lastName: 'אבולעפיה',
      gender: Gender.male,
      age: 27,
      now: now,
    );
    final Person female = _testPerson(
      id: 'note-female',
      firstName: 'כרמל',
      lastName: 'לוי',
      gender: Gender.female,
      age: 25,
      now: now,
    );
    final MatchIdea match = _testMatch(
      id: 'note-match',
      personAId: male.id,
      personBId: female.id,
      now: now,
    );
    final MatchNote note = MatchNote(
      id: 'note-1',
      matchId: match.id,
      text: 'דיברנו בטלפון',
      createdAt: now,
      isAutomatic: false,
    );
    await tester.runAsync(() async {
      await Hive.box<Person>('people').put(male.id, male);
      await Hive.box<Person>('people').put(female.id, female);
      await Hive.box<MatchIdea>('matches').put(match.id, match);
      await Hive.box<MatchNote>('match_notes').put(note.id, note);
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/matches/${match.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.dragUntilVisible(
      find.text('דיברנו בטלפון'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await tester.pump();
    await tester.tap(find.text('דיברנו בטלפון'));
    await tester.pump(const Duration(milliseconds: 350));

    // Everything for the note lives in this one dialog.
    expect(find.text('הערה ביומן'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'מחיקה'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'ביטול'), findsOneWidget);

    // The note text itself is editable right there, and one tap closes it.
    final Finder dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(dialogField).controller?.text, note.text);
    expect(find.widgetWithText(FilledButton, 'שמירה'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'ביטול'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('הערה ביומן'), findsNothing);
    expect(Hive.box<MatchNote>('match_notes').get(note.id)?.text, note.text);
  });

  testWidgets('Journal edit mode toggles between the pencil and the X', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 7, 27);
    final Person male = _testPerson(
      id: 'edit-male',
      firstName: 'הלל',
      lastName: 'אבולעפיה',
      gender: Gender.male,
      age: 27,
      now: now,
    );
    final Person female = _testPerson(
      id: 'edit-female',
      firstName: 'כרמל',
      lastName: 'לוי',
      gender: Gender.female,
      age: 25,
      now: now,
    );
    final MatchIdea match = _testMatch(
      id: 'edit-match',
      personAId: male.id,
      personBId: female.id,
      now: now,
    );
    final MatchNote note = MatchNote(
      id: 'edit-note-1',
      matchId: match.id,
      text: 'דיברנו בטלפון',
      createdAt: now,
      isAutomatic: false,
    );
    await tester.runAsync(() async {
      await Hive.box<Person>('people').put(male.id, male);
      await Hive.box<Person>('people').put(female.id, female);
      await Hive.box<MatchIdea>('matches').put(match.id, match);
      await Hive.box<MatchNote>('match_notes').put(note.id, note);
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/matches/${match.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.dragUntilVisible(
      find.text('דיברנו בטלפון'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await tester.pump();

    // Out of edit mode: a pencil, no checkboxes.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);

    // A long press on a note enters edit mode with that note selected.
    await tester.longPress(find.text('דיברנו בטלפון'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(Checkbox), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('מחיקת הערה אחת'), findsOneWidget);

    // The pencil became an X, and it closes edit mode.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byTooltip('סיום עריכה'), findsOneWidget);

    await tester.tap(find.byTooltip('סיום עריכה'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
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
