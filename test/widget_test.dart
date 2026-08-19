import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/dialogs/details_message_dialog.dart';
import 'package:shadchan/dialogs/hidden_contacts_dialog.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/widgets/match_idea_card.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_photo_editor.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/home_board_store.dart';
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

    // Mark onboarding as completed so the app lands on the main shell instead
    // of the welcome screen.
    await settings.put('userName', 'בודק');
    await settings.put('userGender', 'male');
    await settings.put('userIsSingle', false);
    // And the one-time sign-in invitation as answered, for the same reason:
    // it sits between onboarding and the app, so without this every test here
    // would open on it. The gate itself is covered by `sign_in_gate_test.dart`.
    await settings.put('signIn.promptAnswered', 'true');
  });

  setUp(() async {
    await Hive.box<Person>('people').clear();
    await Hive.box<MatchIdea>('matches').clear();
    await Hive.box<MatchNote>('match_notes').clear();
    final Box<dynamic> settings = Hive.box<dynamic>('settings');
    await settings.put('userIsSingle', false);
    await settings.delete('userPersonalCard');
    await settings.delete('userPersonalCardPhotos');
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

  testWidgets('Onboarding requires an explicit single or married choice', (
    WidgetTester tester,
  ) async {
    final Box<dynamic> settings = Hive.box<dynamic>('settings');
    await tester.runAsync(() => settings.delete('userIsSingle'));
    // The first-launch welcome sits in front of the profile form; this test is
    // about the form, so it starts from an install that has already read it.
    await tester.runAsync(() => settings.put('userSeenIntro', true));
    AppRouter.router.go('/onboarding');

    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    // Registration asks for the two names apart, so the greeting can use the
    // first one alone without guessing where it ends.
    expect(find.widgetWithText(TextField, 'שם פרטי'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'שם משפחה'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'שם פרטי'), 'רבקה');
    await tester.enterText(find.widgetWithText(TextField, 'שם משפחה'), 'כהן');
    await tester.pump();

    expect(find.text('מה המצב האישי שלך?'), findsOneWidget);
    expect(find.text('רווק'), findsOneWidget);
    expect(find.text('נשוי'), findsOneWidget);
    expect(
      find.text('למשתמשים רווקים תופיע בפרופיל אפשרות לשמור ולשתף כרטיס אישי.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'יאללה, מתחילים!'),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('רווק'));
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('רווק')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'יאללה, מתחילים!'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('The account section explains itself when Firebase is down', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildProfileTestApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('חשבון'), 200);
    await tester.pumpAndSettle();

    // Without Firebase there is no sign-in button to offer — a tap could only
    // fail — so the row says why instead of pretending to work.
    expect(find.text('החיבור לחשבון אינו זמין כרגע'), findsOneWidget);
    expect(find.text('התחברות לחשבון'), findsNothing);
    expect(find.text('יציאה מהחשבון'), findsNothing);
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'החיבור לחשבון אינו זמין כרגע'),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('Only a single user sees and edits a personal card', (
    WidgetTester tester,
  ) async {
    final Box<dynamic> settings = Hive.box<dynamic>('settings');

    await tester.pumpWidget(_buildProfileTestApp());
    await tester.pumpAndSettle();

    // The personal status is a quiet line under the name, not a titled section.
    expect(find.text('מצב אישי'), findsNothing);
    expect(find.textContaining('· שינוי'), findsOneWidget);
    expect(find.text('הכרטיס שלך'), findsNothing);
    expect(find.text('יצירת הכרטיס'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => settings.put('userIsSingle', true));
    await tester.pumpWidget(_buildProfileTestApp());
    await tester.pumpAndSettle();
    expect(find.text('הכרטיס שלך'), findsOneWidget);
    expect(
      find.text(
        'כאן אפשר לשמור את הכרטיס שלך, כדי לשתף אותו בקלות בכל פעם שצריך.',
      ),
      findsOneWidget,
    );
    expect(find.text('יצירת הכרטיס'), findsOneWidget);

    await tester.tap(find.text('יצירת הכרטיס'));
    await tester.pumpAndSettle();
    expect(find.text('עריכת הכרטיס האישי'), findsOneWidget);
    expect(find.text('הוספת תמונות'), findsOneWidget);
    expect(find.text('שמירת הכרטיס'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'זה הכרטיס האישי שלי לשיתוף מהיר',
    );
    expect(find.text('זה הכרטיס האישי שלי לשיתוף מהיר'), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
  });

  test('Personal card photo order is stored exactly as arranged', () async {
    final UserProfileProvider profile = UserProfileProvider(
      Hive.box<dynamic>('settings'),
    );
    await profile.setPersonalCardContent(
      text: 'כרטיס עם גלריה',
      photoPaths: const <String>['second.jpg', 'primary.jpg', 'third.jpg'],
    );

    expect(profile.personalCard, 'כרטיס עם גלריה');
    expect(profile.personalCardPhotos, const <String>[
      'second.jpg',
      'primary.jpg',
      'third.jpg',
    ]);
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
    expect(shouldShowBottomNavigationBar('/profile'), isFalse);
  });

  testWidgets('Manual add uses the current card design without Mazel Tov', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/people/add');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('הוספת כרטיס'), findsOneWidget);
    expect(find.text('כרטיס חדש למאגר'), findsOneWidget);
    expect(find.text('הכרטיס והתמונות'), findsOneWidget);
    expect(find.text('פרטים אישיים'), findsOneWidget);
    expect(find.text('פנוי'), findsOneWidget);
    expect(find.text('תפוס'), findsOneWidget);
    expect(find.text('בהפסקה'), findsOneWidget);
    expect(find.text('מזל טוב'), findsNothing);
    expect(find.textContaining('🟢'), findsNothing);
    expect(find.textContaining('🔴'), findsNothing);
    expect(find.textContaining('🟡'), findsNothing);
    expect(tester.takeException(), isNull);
    // Let the form's non-fatal Firebase warm-up timeout finish in fake time.
    await tester.pump(const Duration(seconds: 31));
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
      expect(find.byTooltip('עריכת פרטי המועמד'), findsOneWidget);
      expect(find.byTooltip('עריכת טקסט הכרטיס המלא'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('עריכת כרטיס'), findsNothing);
      expect(find.text('עריכה מורחבת'), findsOneWidget);
      await tester.tap(find.text('עריכה מורחבת'));
      await tester.pumpAndSettle();
      expect(find.text('עריכת כרטיס'), findsOneWidget);
      expect(find.text('שם פרטי'), findsOneWidget);
      expect(find.text('עיר או יישוב'), findsOneWidget);
      // The page is a stack of collapsible areas; the basics start open and
      // the rest are one tap away.
      expect(find.text('כרטיסייה לשליחה'), findsOneWidget);
      expect(find.text('תמונות'), findsWidgets);
      for (final String area in <String>[
        'מה המועמד מחפש',
        'הערות אישיות – לעיניי בלבד',
        'איש קשר להעברת הצעות',
      ]) {
        for (int i = 0; i < 12 && find.text(area).evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -260));
          await tester.pump();
        }
        expect(find.text(area), findsOneWidget);
      }
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('עריכת כרטיס'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ModalBarrier).last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('לפתיחת הצעה'));
      await tester.tap(find.text('לפתיחת הצעה'));
      await tester.pumpAndSettle();
      expect(find.text('הוספת הצעה עם מועמד מתוך המאגר שלי'), findsOneWidget);
      expect(find.text('הוספת הצעה עם מועמד מחוץ למאגר שלי'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      await tester.tap(find.byTooltip('עריכת פרטי המועמד'));
      await tester.pumpAndSettle();
      expect(find.text('עריכת כרטיס'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('quick-name-profile-person')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('quick-age-profile-person')),
        findsOneWidget,
      );
      expect(find.byTooltip('בחירת סגנון דתי'), findsOneWidget);
      expect(find.byTooltip('הוספת תמונות'), findsOneWidget);
      expect(find.byType(PersonPhotoEditor), findsNothing);
      await tester.tap(find.byTooltip('בחירת סגנון דתי'));
      await tester.pumpAndSettle();
      expect(find.text('חרדי'), findsOneWidget);
      expect(find.text('דתי לאומי'), findsOneWidget);
      await tester.tap(find.byType(ModalBarrier).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ביטול עריכה מהירה'));
      await tester.pumpAndSettle();

      final Finder editFullCard = find.byTooltip('עריכת טקסט הכרטיס המלא');
      await tester.ensureVisible(editFullCard);
      await tester.pump(const Duration(milliseconds: 200));
      final double cardBodyTop = tester
          .getTopLeft(
            find.byKey(
              const ValueKey<String>('candidate-full-card-body-profile-person'),
            ),
          )
          .dy;
      final double cardTextTop = tester
          .getTopLeft(
            find.byKey(
              const ValueKey<String>('candidate-full-card-text-profile-person'),
            ),
          )
          .dy;
      expect(cardTextTop, closeTo(cardBodyTop, 0.5));
      expect(tester.getTopLeft(editFullCard).dy, lessThan(cardBodyTop + 4));
      await tester.tap(editFullCard);
      await tester.pumpAndSettle();
      expect(find.text('עריכת הכרטיס המלא'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('quick-card-profile-person')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('quick-card-profile-person')),
        'שורה ראשונה\nשורה שנייה\nסוף הכרטיס המלא\n'
        'טקסט כרטיס מעודכן מתוך המשבצת',
      );
      await tester.tap(find.byTooltip('ביטול עריכת הכרטיס'));
      await tester.pumpAndSettle();
      expect(
        Hive.box<Person>('people').get(profile.id)?.description,
        'שורה ראשונה\nשורה שנייה\nסוף הכרטיס המלא',
      );

      // Sharing sits in the profile app bar and goes straight to the share
      // sheet with the card text and every photo — no preview step in between.
      expect(find.byTooltip('שיתוף כרטיס'), findsOneWidget);
      expect(find.byType(PersonCardViewer), findsNothing);

      final Finder showFullCard = find.text('הצגת הכרטיס המלא');
      await tester.ensureVisible(showFullCard);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(showFullCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('סוף הכרטיס המלא'), findsWidgets);
      expect(find.text('סגירת הכרטיס המלא'), findsOneWidget);
      // The expanded card no longer carries a share button of its own.
      expect(find.byTooltip('שיתוף הכרטיס המלא'), findsNothing);

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

  testWidgets('Tapping the profile photo opens the full card full screen', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final DateTime now = DateTime(2026, 7, 27);
    // The number matters: the viewer's messaging action follows it. A mobile
    // number keeps the WhatsApp button this test looks for; without one the
    // bar would (correctly) show no chat action at all.
    final Person profile = Person(
      id: 'card-viewer-person',
      phone: '0501111111',
      firstName: 'הלל',
      lastName: 'אבולעפיה',
      gender: Gender.male,
      manualAge: 27,
      description: 'שורה ראשונה\nסוף הכרטיס המלא',
      createdAt: now,
      updatedAt: now,
    );
    await tester.runAsync(() async {
      await Hive.box<Person>('people').put(profile.id, profile);
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    AppRouter.router.go('/people/${profile.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byType(PersonAvatar).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The viewer carries both app-bar actions alongside the card itself. Both
    // are icons: over a photograph the share label was the one piece of chrome
    // wide enough to compete with the picture under it.
    expect(find.byType(PersonCardViewer), findsOneWidget);
    expect(find.textContaining('סוף הכרטיס המלא'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(PersonCardViewer),
        matching: find.text('שיתוף כרטיס'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(PersonCardViewer),
        matching: find.byTooltip('שיתוף כרטיס'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('פתיחת שיחה ב-WhatsApp'), findsOneWidget);

    await tester.tap(find.text('הכרטיס המלא'));
    await tester.pumpAndSettle();
    expect(find.text('הצג פחות'), findsOneWidget);

    await tester.tap(find.byTooltip('סגירה'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PersonCardViewer), findsNothing);
  });

  testWidgets('The board can be filled from the home screen itself', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final DateTime now = DateTime(2026, 8, 15);
    final Person friend = Person(
      id: 'board-add-person',
      firstName: 'נעמי',
      lastName: 'שגב',
      gender: Gender.female,
      manualAge: 24,
      createdAt: now,
      updatedAt: now,
    );
    await tester.runAsync(
      () => Hive.box<Person>('people').put(friend.id, friend),
    );

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The board is named even with nothing on it, unlike every other block on
    // this page — it is the one area filled by hand, and a surface that never
    // appears until something is on it can never be where the first thing
    // goes. But an *empty* board is one folded line rather than a corkboard
    // taking a third of the screen to say it is empty.
    expect(find.text('הלוח שלי'), findsOneWidget);
    expect(find.text('הלוח ריק — אפשר להצמיד אליו חבר או רעיון'), findsNothing);

    await tester.ensureVisible(find.text('הלוח שלי'));
    await tester.pump();
    await tester.tap(find.text('הלוח שלי'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('הלוח ריק — אפשר להצמיד אליו חבר או רעיון'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('הוספה ללוח'));
    await tester.pump();
    await tester.tap(find.text('הוספה ללוח'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Two lists, because a friend and a proposal are not comparable things to
    // put in front of somebody in one combined list. Scoped to the sheet's own
    // rows — "הוספת רעיון" is also one of the page's two entry tiles behind it.
    expect(find.widgetWithText(ListTile, 'הוספת חבר'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'הוספת רעיון'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'הוספת חבר'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('הוספת חבר ללוח'), findsOneWidget);

    await tester.tap(find.text('נעמי שגב').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      HomeBoardStore.instance.contains(HomeItemKind.person, friend.id),
      isTrue,
    );
    addTearDown(
      () => HomeBoardStore.instance.remove(HomeItemKind.person, friend.id),
    );
  });

  testWidgets('Pinning a person opens home directly at the board', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final DateTime now = DateTime(2026, 8, 2);
    final Person profile = Person(
      id: 'board-navigation-person',
      firstName: 'אבישי',
      lastName: 'הלוי',
      gender: Gender.male,
      manualAge: 29,
      createdAt: now,
      updatedAt: now,
    );
    HomeBoardStore.instance.remove(HomeItemKind.person, profile.id);
    addTearDown(
      () => HomeBoardStore.instance.remove(HomeItemKind.person, profile.id),
    );
    await tester.runAsync(
      () => Hive.box<Person>('people').put(profile.id, profile),
    );

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    AppRouter.router.go('/people/${profile.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('הוספה ללוח שלי'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 500));

    expect(AppRouter.router.routeInformationProvider.value.uri.path, '/home');
    expect(
      AppRouter.router.routeInformationProvider.value.uri.queryParameters,
      containsPair('section', 'board'),
    );
    expect(find.text('הלוח שלי'), findsOneWidget);
    expect(find.text('אבישי הלוי'), findsWidgets);
    expect(tester.getTopLeft(find.text('הלוח שלי')).dy, lessThan(260));
  });

  testWidgets('The edit route opens quick editing inside the profile card', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 8, 2);
    final Person profile = Person(
      id: 'quick-edit-route-person',
      firstName: 'אבישי',
      lastName: 'כהן',
      gender: Gender.male,
      manualAge: 29,
      religiousLevel: ReligiousLevel.datiLeumi,
      createdAt: now,
      updatedAt: now,
    );
    await tester.runAsync(
      () => Hive.box<Person>('people').put(profile.id, profile),
    );

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/people/${profile.id}/edit');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('עריכת כרטיס'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('quick-name-quick-edit-route-person')),
      findsOneWidget,
    );
    expect(find.byTooltip('הוספת תמונות'), findsOneWidget);
    expect(find.byTooltip('בחירת סגנון דתי'), findsOneWidget);
    expect(find.byTooltip('שמירת עריכה מהירה'), findsOneWidget);
  });

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
      city: 'ירושלים',
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

    expect(find.text('פרטי רעיון'), findsOneWidget);
    expect(find.text('הלל אבולעפיה'), findsOneWidget);
    expect(find.text('כרמל לוי'), findsOneWidget);
    // One derived line, and the three ways on in a single area.
    expect(find.text('פתוחה · יאללה לקדם'), findsOneWidget);
    expect(find.text('עדכון הצעה'), findsOneWidget);
    // Named for the act rather than the state, so the tile cannot be read as a
    // label saying where the proposal already is.
    expect(find.text('מתחילים לצאת'), findsOneWidget);
    expect(find.text('יוצאים'), findsNothing);
    expect(find.text('העברה להמתנה'), findsOneWidget);
    expect(find.text('סגירת הצעה'), findsOneWidget);
    expect(find.text('סטטוס הצעה'), findsNothing);
    expect(find.text('איפה זה עומד?'), findsNothing);
    expect(find.textContaining('עודכן'), findsNothing);
    // The action tiles carry their label and nothing else.
    expect(find.text('נחזור אליה בהמשך'), findsNothing);
    expect(find.text('הם התחילו לצאת'), findsNothing);
    expect(find.text('הצעה לא מתאימה'), findsNothing);
    // A candidate's city is not part of the proposal card.
    expect(find.textContaining('ירושלים'), findsNothing);

    await tester.tap(find.text('פנוי').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('תפוס'), findsOneWidget);
    expect(find.text('בהפסקה'), findsOneWidget);
  });

  testWidgets('Ideas default to all live states and celebrate dating couples', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 8, 2);
    final List<Person> people = <Person>[
      _testPerson(
        id: 'all-open-a',
        firstName: 'פתוח',
        lastName: 'אחד',
        gender: Gender.male,
        age: 27,
        now: now,
      ),
      _testPerson(
        id: 'all-open-b',
        firstName: 'פתוחה',
        lastName: 'אחת',
        gender: Gender.female,
        age: 25,
        now: now,
      ),
      _testPerson(
        id: 'all-wait-a',
        firstName: 'ממתין',
        lastName: 'אחד',
        gender: Gender.male,
        age: 28,
        now: now,
      ),
      _testPerson(
        id: 'all-wait-b',
        firstName: 'ממתינה',
        lastName: 'אחת',
        gender: Gender.female,
        age: 26,
        now: now,
      ),
      _testPerson(
        id: 'all-date-a',
        firstName: 'שמח',
        lastName: 'חתן',
        gender: Gender.male,
        age: 29,
        now: now,
      ),
      _testPerson(
        id: 'all-date-b',
        firstName: 'שמחה',
        lastName: 'כלה',
        gender: Gender.female,
        age: 27,
        now: now,
      ),
      _testPerson(
        id: 'all-archive-a',
        firstName: 'ארכיון',
        lastName: 'אחד',
        gender: Gender.male,
        age: 30,
        now: now,
      ),
      _testPerson(
        id: 'all-archive-b',
        firstName: 'ארכיון',
        lastName: 'שתיים',
        gender: Gender.female,
        age: 28,
        now: now,
      ),
    ];
    final List<MatchIdea> matches = <MatchIdea>[
      _testMatch(
        id: 'all-open',
        personAId: 'all-open-a',
        personBId: 'all-open-b',
        now: now,
      ),
      _testMatch(
        id: 'all-wait',
        personAId: 'all-wait-a',
        personBId: 'all-wait-b',
        now: now,
      )..status = MatchStatus.unavailable,
      _testMatch(
        id: 'all-dating',
        personAId: 'all-date-a',
        personBId: 'all-date-b',
        now: now,
      )..status = MatchStatus.dating,
      _testMatch(
        id: 'all-archive',
        personAId: 'all-archive-a',
        personBId: 'all-archive-b',
        now: now,
      )..status = MatchStatus.rejected,
    ];
    await tester.runAsync(() async {
      await Hive.box<Person>('people').putAll(<String, Person>{
        for (final Person person in people) person.id: person,
      });
      await Hive.box<MatchIdea>('matches').putAll(<String, MatchIdea>{
        for (final MatchIdea match in matches) match.id: match,
      });
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/matches');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('הכול'), findsOneWidget);
    expect(find.text('פתוחים'), findsOneWidget);
    expect(find.text('בהמתנה'), findsOneWidget);
    expect(find.text('יוצאים'), findsOneWidget);
    // The name and the age are two spans now, so the age can hold its ground
    // while a long name gives way — see match_idea_card_test.dart.
    expect(find.text('פתוח אחד'), findsOneWidget);
    expect(find.text('ממתין אחד'), findsOneWidget);
    expect(find.text('✨ יוצאים יחד ✨'), findsOneWidget);
    expect(find.text('ארכיון אחד'), findsNothing);

    await tester.tap(find.text('✨ יוצאים יחד ✨'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('איזה כיף — הם יוצאים!'), findsOneWidget);
  });

  testWidgets('New ideas uses the matching explanation and rejection wording', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 8, 2);
    final Person male = _testPerson(
      id: 'new-idea-man',
      firstName: 'אורי',
      lastName: 'כהן',
      gender: Gender.male,
      age: 27,
      now: now,
    )..religiousLevel = ReligiousLevel.datiLeumi;
    final Person female = _testPerson(
      id: 'new-idea-woman',
      firstName: 'נועה',
      lastName: 'לוי',
      gender: Gender.female,
      age: 25,
      now: now,
    )..religiousLevel = ReligiousLevel.datiLeumi;
    await tester.runAsync(() async {
      await Hive.box<Person>(
        'people',
      ).putAll(<String, Person>{male.id: male, female.id: female});
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/ideas/new');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text(
        'המאגר שלך מציע רעיונות לזוגות שיכולים להתאים לפי גיל וסגנון דתי',
      ),
      findsOneWidget,
    );
    expect(find.text('לא מתאים'), findsOneWidget);
    expect(find.text('לא עכשיו'), findsNothing);
  });

  testWidgets('Profile-canvas app bars keep a dark title, not cream on cream', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 7, 27);
    final Person person = _testPerson(
      id: 'title-person',
      firstName: 'הלל',
      lastName: 'אבולעפיה',
      gender: Gender.male,
      age: 27,
      now: now,
    );
    await tester.runAsync(() async {
      await Hive.box<Person>('people').put(person.id, person);
    });

    await tester.pumpWidget(_buildTestApp());
    await tester.pump();
    AppRouter.router.go('/people/${person.id}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('התאמות'));
    await tester.pumpAndSettle();

    final RenderParagraph title = tester.renderObject<RenderParagraph>(
      find.text('התאמות · הלל אבולעפיה'),
    );
    final Color? color = title.text.style?.color;
    expect(color, isNotNull);
    // Dark ink on the cream bar — the banner's cream text would be invisible.
    expect(color!.computeLuminance(), lessThan(0.3));
  });

  testWidgets('The pair card WhatsApp button offers chat or the other card', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 7, 27);
    final Person male = _testPerson(
      id: 'wa-male',
      firstName: 'נדיב',
      lastName: 'אלמליח',
      gender: Gender.male,
      age: 25,
      now: now,
      phone: '0501234567',
      description: 'הכרטיס של נדיב',
    );
    final Person female = _testPerson(
      id: 'wa-female',
      firstName: 'נהרה',
      lastName: 'בלטמן',
      gender: Gender.female,
      age: 23,
      now: now,
      phone: '0507654321',
      description: 'הכרטיס של נהרה',
    );
    final MatchIdea match = _testMatch(
      id: 'wa-match',
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

    // The first WhatsApp button in RTL belongs to the woman's side.
    expect(find.byType(FaIcon), findsNWidgets(2));
    await tester.tap(find.byType(FaIcon).first);
    await tester.pumpAndSettle();

    expect(find.text('פתיחת שיחה עם נהרה'), findsOneWidget);
    expect(find.text('שליחת הכרטיס של נדיב אל נהרה'), findsOneWidget);
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

    // The reminder is its own clear area; the related contact stays a quiet
    // line until one is actually added.
    expect(find.text('הוספת תזכורת'), findsOneWidget);
    expect(find.text('נזכיר לך לחזור אליה בזמן הנכון'), findsOneWidget);
    expect(find.text('איש קשר שקשור להצעה'), findsOneWidget);

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
    // Both sides carry a number, so the pair card draws WhatsApp discs. A
    // candidate with no number now gets a pencil there instead — a second
    // `Icons.edit_outlined` on the page, which is the icon this test is
    // counting to find the journal's own.
    final Person male = _testPerson(
      id: 'edit-male',
      firstName: 'הלל',
      lastName: 'אבולעפיה',
      gender: Gender.male,
      age: 27,
      phone: '0501111111',
      now: now,
    );
    final Person female = _testPerson(
      id: 'edit-female',
      firstName: 'כרמל',
      lastName: 'לוי',
      gender: Gender.female,
      age: 25,
      phone: '0522222222',
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
    QuickUpdateOutcome? result;

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

    expect(result, QuickUpdateOutcome.cancelled);
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
                  onOpenPersonWhatsApp: (_) {},
                  onCompletePersonCard: (_) {},
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
                  onOpenPersonWhatsApp: (_) {},
                  onCompletePersonCard: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    for (final (String name, String age) entry in <(String, String)>[
      ('דוד כהן', ', 25'),
      ('שרה לוי', ', 23'),
      ('יוסף פרידמן', ', 28'),
      ('רחל מזרחי', ', 26'),
    ]) {
      expect(find.text(entry.$1), findsOneWidget, reason: entry.$1);
      expect(find.text(entry.$2), findsOneWidget, reason: entry.$2);
    }
  });
}

Person _testPerson({
  required String id,
  required String firstName,
  required String lastName,
  required Gender gender,
  required int age,
  required DateTime now,
  String? phone,
  String? description,
  String? city,
}) {
  return Person(
    id: id,
    firstName: firstName,
    lastName: lastName,
    gender: gender,
    manualAge: age,
    phone: phone,
    description: description,
    city: city,
    createdAt: now,
    updatedAt: now,
  );
}

MatchIdea _testMatch({
  required String id,
  required String personAId,
  required String personBId,
  required DateTime now,
  DateTime? reminderDate,
}) {
  return MatchIdea(
    id: id,
    personAId: personAId,
    personBId: personBId,
    status: MatchStatus.idea,
    currentHandler: CurrentHandler.me,
    createdAt: now,
    updatedAt: now,
    reminderDate: reminderDate,
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
      // Lazy, so this only costs anything if a test actually routes to the
      // profile. See `_buildProfileTestApp` for why Firebase is kept out.
      ChangeNotifierProvider<AccountProvider>(
        create: (_) => AccountProvider(connect: () async {}),
      ),
      ChangeNotifierProvider<SyncProvider>(
        create: (_) =>
            SyncProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      // Same seam, same reason: disabled, the tips provider serves whatever is
      // in the local cache and never reaches Firebase.
      ChangeNotifierProvider<TipsProvider>(
        create: (_) =>
            TipsProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      // The community layer reads the local ledgers and nothing else until
      // Firebase is up, which it never is in a test — so it needs no stub, only
      // to exist.
      ChangeNotifierProvider<CommunityProvider>(
        create: (_) => CommunityProvider(),
      ),
    ],
    // Same seam once more: the store check reaches SharedPreferences and an
    // http client through `Upgrader.initialize()`, neither of which exists
    // under `flutter test`.
    child: const App(checkForUpdates: false),
  );
}

Widget _buildProfileTestApp() {
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
      // Firebase is never reached under `flutter test`: `initializeApp` would
      // hang inside the fake-async zone and leave its deadline timer pending.
      // The provider settles on "not ready", which is exactly the state the
      // account section has to be able to draw.
      ChangeNotifierProvider<AccountProvider>(
        create: (_) => AccountProvider(connect: () async {}),
      ),
      ChangeNotifierProvider<SyncProvider>(
        create: (_) =>
            SyncProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      // Same seam, same reason: disabled, the tips provider serves whatever is
      // in the local cache and never reaches Firebase.
      ChangeNotifierProvider<TipsProvider>(
        create: (_) =>
            TipsProvider(Hive.box<dynamic>('settings'), enabled: false),
      ),
      // The community layer reads the local ledgers and nothing else until
      // Firebase is up, which it never is in a test — so it needs no stub, only
      // to exist.
      ChangeNotifierProvider<CommunityProvider>(
        create: (_) => CommunityProvider(),
      ),
    ],
    child: const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ProfileScreen(),
      ),
    ),
  );
}
