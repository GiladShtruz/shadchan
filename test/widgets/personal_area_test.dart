import 'package:shadchan/widgets/notification_center.dart';
import 'package:shadchan/services/notification_feed.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/personal_home_screen.dart';
import 'package:shadchan/screens/card_friend_screen.dart';
import 'package:shadchan/screens/person_extended_edit_screen.dart';
import 'package:shadchan/screens/my_matchmakers_screen.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/widgets/private_looking.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/community_period.dart';

class _Data extends PersonalAreaProvider {
  _Data() : super(enabled: false) {
    stats = {
      'singles': 42,
      'newSinglesWeek': 3,
      'weekKey': CommunityPeriods.weekKey(),
    };
    news = [
      const PersonalNews(
        id: 'admin',
        title: 'עדכון מהקהילה',
        text: 'נפגשים לחשוב יחד על רעיונות',
      ),
    ];
  }
}

class _Access extends CardAccessProvider {
  _Access(PersonRepository people) : super(people: people, enabled: false);
  final candidates = <CardHelper>[
    const CardHelper(
      uid: 'friend123',
      name: 'אורי',
      databaseCount: 12,
      granteeUids: ['friend123'],
    ),
  ];
  final grants = <CardAccess>[];
  int grantCalls = 0;
  @override
  List<CardHelper> get helpers => candidates;
  @override
  List<CardHelper> get knownHelpers => candidates;
  @override
  List<CardAccess> get approved => grants;
  @override
  CardAccess? accessTo(String ownerUid) =>
      grants.where((g) => g.ownerUid == ownerUid).firstOrNull;
  @override
  Map<String, CardAccess> get matchmakerRows => {
    for (final g in grants) g.ownerUid: g,
  };
  @override
  bool get isConnected => true;
  @override
  bool get ownerAccessLoaded => ready;
  bool ready = true;
  @override
  bool get helpersLoaded => ready;
  @override
  List<CardHelper> get mutualFriends => const [
    CardHelper(uid: 'single123', name: 'נועה'),
  ];
  @override
  Future<bool> grant(
    CardHelper helper, {
    required String ownerName,
    String? ownerPhoneHash,
    String? ownerPhone,
    bool cardGranted = true,
    bool lookingGranted = false,
    Map<String, dynamic>? expectedRecipient,
  }) async {
    grantCalls++;
    candidates.remove(helper);
    grants.add(
      CardAccess(
        ownerUid: 'owner123',
        matchmakerUid: helper.uid,
        status: CardAccessStatus.approved,
        requestedBy: 'owner',
        matchmakerName: helper.name,
      ),
    );
    notifyListeners();
    return true;
  }
}

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<Person> peopleBox;
  late PersonRepository people;
  late PersonalCardProvider cards;
  late _Access access;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('personal_widget_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GenderAdapter());
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
    settings = await Hive.openBox<dynamic>('settings');
    peopleBox = await Hive.openBox<Person>('people');
    await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() async {
    await settings.clear();
    await peopleBox.clear();
    await settings.putAll({
      'userName': 'יעל לוי',
      'userFirstName': 'יעל',
      'userLastName': 'לוי',
      'userGender': 'female',
      'userMyPhone': '0501234567',
      'workspace.matchmakerEnabled': 'false',
    });
    people = PersonRepository(peopleBox);
    access = _Access(people);
    cards = PersonalCardProvider(settings);
    await cards.save(
      Person(
        id: 'personal-card',
        firstName: 'יעל',
        lastName: 'לוי',
        gender: Gender.female,
        description: 'טקסט הכרטיס המלא'.padRight(40, 'א'),
        city: 'מודיעין',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  /// The personal home is a long page; most checks want all of it built.
  Future<void> tall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget app({double scale = 1, Widget? home}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<PersonRepository>.value(value: people),
      ChangeNotifierProvider<MatchRepository>(
        create: (_) => MatchRepository(
          Hive.box<MatchIdea>('matches'),
          Hive.box<MatchNote>('match_notes'),
        ),
      ),
      ChangeNotifierProvider<CardAccessProvider>.value(value: access),
      ChangeNotifierProvider<PersonalCardProvider>.value(value: cards),
      ChangeNotifierProvider<UserProfileProvider>(
        create: (_) => UserProfileProvider(settings),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Builder(
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: home ?? PersonalAreaScreen(createData: _Data.new),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'home greets without an emoji and grants card access from the friends strip',
    (tester) async {
      await tall(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.textContaining('👋', findRichText: true), findsNothing);
      expect(find.textContaining('יעל', findRichText: true), findsWidgets);
      expect(find.text('עוד לא נתת גישה לחברים'), findsOneWidget);
      expect(find.text('חבר נוסף שלך משדך בשדכן'), findsOneWidget);
      expect(find.text('החברים שלי שמשדכים בשדכן'), findsOneWidget);
      expect(find.text('אפשר לתת גישה'), findsOneWidget);
      // A card-only account has no way across to the matchmaker's side.
      expect(find.text('לאזור השדכנית'), findsNothing);
      await tester.tap(find.text('אורי'));
      await tester.pumpAndSettle();
      // "מה אני מחפש/ת" is empty, so there is nothing to choose: one tap.
      await tester.tap(find.text('לתת גישה'));
      await tester.pumpAndSettle();
      expect(access.grantCalls, 1);
      expect(access.approved, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('רואה את הכרטיס'), findsOneWidget);
      expect(find.text('נתת גישה לחבר אחד שלך'), findsOneWidget);
      expect(find.text('חבר אחד יכול לחשוב עלייך'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
  testWidgets(
    'a single who also matchmakes has a way across beside the greeting',
    (tester) async {
      await tall(tester);
      await tester.runAsync(
        () => settings.put('workspace.matchmakerEnabled', 'true'),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('לאזור השדכנית'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
  testWidgets(
    'a request leads the strip, shows in "מה חדש אצלי" and tops the grant tab',
    (tester) async {
      await tall(tester);
      access.candidates.add(
        const CardHelper(uid: 'newer', name: 'בתיה', granteeUids: ['newer']),
      );
      access.grants.add(
        const CardAccess(
          ownerUid: 'owner123',
          matchmakerUid: 'asker',
          status: CardAccessStatus.pending,
          requestedBy: 'matchmaker',
          matchmakerName: 'שרה',
          matchmakerGender: 'female',
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('מה חדש אצלי'), findsOneWidget);
      expect(find.text('שרה ביקשה גישה לכרטיס שלך'), findsOneWidget);
      expect(find.text('ביקשה גישה'), findsOneWidget);
      final double asker = tester.getTopRight(find.text('שרה').first).dx;
      final double other = tester.getTopRight(find.text('אורי')).dx;
      // RTL: the first face in the strip is the right-most.
      expect(asker, greaterThan(other));
      await tester.tap(find.text('השדכנים שלי').last);
      await tester.pumpAndSettle();
      expect(find.text('אפשר לתת גישה · 3'), findsOneWidget);
      final double top = tester.getTopLeft(find.text('שרה').last).dy;
      expect(top, lessThan(tester.getTopLeft(find.text('אורי').last).dy));
      expect(find.text('לאשר'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
  testWidgets('"מה חדש אצלי" is not drawn when nothing is new', (tester) async {
    await tall(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('מה חדש אצלי'), findsNothing);
    expect(
      find.text('42 רווקים ורווקות מנהלים כרטיס אישי בשדכן'),
      findsOneWidget,
    );
    expect(find.text('3 הצטרפו השבוע'), findsOneWidget);
    expect(find.text('ניהול ופרטיות'), findsOneWidget);
    expect(find.text('מחיקת הכרטיס שלי'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets(
    'deleting the card lives under "ניהול ופרטיות", not on the home',
    (tester) async {
      await tall(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('פרופיל').last);
      await tester.pumpAndSettle();
      expect(find.text('מחיקת הכרטיס שלי'), findsNothing);
      await tester.tap(find.text('בית').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ניהול ופרטיות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ניהול ופרטיות'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('מחיקת הכרטיס שלי'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('מחיקת הכרטיס שלי'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
  testWidgets(
    'three tabs separate the full profile from home and expose persistent notifications',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items
            .map((i) => i.label),
        ['בית', 'השדכנים שלי', 'פרופיל'],
      );
      expect(find.byTooltip('התראות'), findsOneWidget);
      await tester.tap(find.text('פרופיל').last);
      await tester.pumpAndSettle();
      expect(find.text(cards.card!.description!), findsOneWidget);
      expect(
        find.text(
          'כדאי להוסיף עוד תמונה כדי לעזור לחברים להציג אותך בצורה טובה יותר.',
        ),
        findsOneWidget,
      );
      expect(find.text('עריכת הכרטיס'), findsOneWidget);
      await tester.tap(find.text('השדכנים שלי').last);
      await tester.pumpAndSettle();
      expect(find.text('אישרתי גישה · 0'), findsOneWidget);
      expect(find.text('אפשר לתת גישה · 1'), findsOneWidget);
      expect(find.textContaining('הכרטיס שלך גלוי רק לחברים'), findsOneWidget);
      expect(find.text('12 אנשים במאגר'), findsOneWidget);
    },
  );
  testWidgets(
    'own-card preview uses the shared viewer without adding an owner record or private wishes',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('צפייה בכרטיס המלא'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('צפייה בכרטיס המלא'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonCardViewer), findsOneWidget);
      expect(find.text(cards.card!.description!), findsOneWidget);
      expect(find.text('עריכת הכרטיס'), findsNothing);
      expect(find.text('מה אני מחפשת'), findsNothing);
      expect(people.count, 0);
      await tester.runAsync(
        () => cards.save(
          cards.card!.copyWith(description: 'טקסט כרטיס שעודכן בזמן התצוגה'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('טקסט כרטיס שעודכן בזמן התצוגה'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'hiding a suggestion leaves its access untouched and can be undone',
    (tester) async {
      await tall(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('אורי'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הסתר מהרשימה'));
      await tester.pumpAndSettle();
      expect(find.text('אורי'), findsNothing);
      expect(access.approved, isEmpty);
      await tester.tap(find.text('השדכנים שלי').last);
      await tester.pumpAndSettle();
      expect(find.text('מוסתרים מהרשימה · 1'), findsOneWidget);
      await tester.tap(find.byTooltip('ניהול הרשאות והזמנות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('חברים מוסתרים'));
      await tester.pumpAndSettle();
      expect(find.text('אורי'), findsOneWidget);
      await tester.tap(find.text('ביטול הסתרה'));
      await tester.pumpAndSettle();
      expect(PersonalHelperActions.hidden, isEmpty);
    },
  );
  testWidgets(
    'revoking an open card editor cannot reveal or resave its old fields',
    (tester) async {
      final friend = Person(
        id: 'linked-editor',
        firstName: 'יעל',
        lastName: 'לוי',
        gender: Gender.female,
        description: 'טקסט פרטי מהכרטיס שנשלל',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      )..cardOwnerUid = 'owner123';
      await tester.runAsync(() => peopleBox.put(friend.id, friend));
      people.requireVerifiedCardAccess();
      people.setVerifiedCardOwners({'owner123'});
      await tester.pumpWidget(
        app(home: PersonExtendedEditScreen(personId: friend.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('כרטיסייה לשליחה'));
      await tester.pumpAndSettle();
      expect(find.text('טקסט פרטי מהכרטיס שנשלל'), findsOneWidget);
      people.setVerifiedCardOwners({});
      await tester.pumpAndSettle();
      expect(find.text('טקסט פרטי מהכרטיס שנשלל'), findsNothing);
      expect(find.text('הגישה לכרטיס הזה אינה זמינה עוד.'), findsOneWidget);
      // Simulate unlink restoring a pre-card database entry while this editor
      // stays mounted. Its stale controllers must remain inaccessible.
      friend
        ..cardOwnerUid = null
        ..description = 'המידע המקורי של השדכן';
      await tester.runAsync(() => people.saveSynced(friend));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('טקסט פרטי מהכרטיס שנשלל'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(people.getById(friend.id)?.description, 'המידע המקורי של השדכן');
    },
  );
  testWidgets(
    'a direct notification link never opens a cached card after revocation',
    (tester) async {
      final stale = Person(
        id: 'stale',
        firstName: 'יעל',
        lastName: 'לוי',
        gender: Gender.female,
        description: 'מידע רגיש לא מורשה',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      )..cardOwnerUid = 'owner123';
      await tester.runAsync(() => peopleBox.put(stale.id, stale));
      people.requireVerifiedCardAccess();
      access.matchmakerAccessVerified = true;
      access.grants.add(
        const CardAccess(
          ownerUid: 'owner123',
          matchmakerUid: 'reader123',
          status: CardAccessStatus.revoked,
          requestedBy: 'owner',
        ),
      );
      await tester.pumpWidget(
        app(home: const CardFriendScreen(ownerUid: 'owner123')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('הגישה לכרטיס אינה זמינה'), findsOneWidget);
      expect(find.text('מידע רגיש לא מורשה'), findsNothing);
      expect(people.getById(stale.id), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unresolved access does not claim zero approved friends', (
    tester,
  ) async {
    await tall(tester);
    access.ready = false;
    access.candidates.clear();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('עוד לא נתת גישה לחברים'), findsNothing);
    expect(find.text('רשימת החברים תופיע לאחר החיבור לחשבון'), findsOneWidget);
    access.ready = true;
    access.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('עוד לא נתת גישה לחברים'), findsOneWidget);
    expect(
      find.text('מי עוד מכיר אותך מספיק טוב כדי לחשוב עלייך?'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'home previews six friends and the full screen contains every one',
    (tester) async {
      await tall(tester);
      access.candidates.clear();
      access.candidates.addAll(
        List.generate(
          25,
          (i) => CardHelper(
            uid: 'helper-$i',
            name: 'חבר ${i.toString().padLeft(2, '0')}',
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('לכל 25 השדכנים'), findsOneWidget);
      expect(find.text('חבר 24'), findsNothing);
      await tester.tap(find.text('השדכנים שלי').last);
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(MyMatchmakersScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .last;
      await tester.scrollUntilVisible(
        find.text('חבר 24'),
        350,
        scrollable: scroll,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(find.text('חבר 24'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a card-created update opens photos only for an authorized reader',
    (tester) async {
      final friend = cards.card!.copyWith()..cardOwnerUid = 'owner123';
      final notice = InboxItem(
        id: 'created',
        kind: 'cardCreated',
        title: 'כרטיס חדש',
        body: '',
        route: '/reminders',
        read: false,
        ownerUid: 'owner123',
      );
      final line = AppNotification(
        id: 'created',
        source: NotificationSource.inbox,
        time: DateTime.now(),
        read: false,
        groupKey: 'created',
        title: 'כרטיס חדש',
        person: friend,
        inbox: notice,
      );
      Widget route() => app(
        home: Builder(
          builder: (context) =>
              Text(NotificationCenter.routeFor(context, line) ?? 'none'),
        ),
      );
      await tester.pumpWidget(route());
      expect(find.text('/people/${friend.id}?focus=request'), findsOneWidget);
      access.grants.add(
        const CardAccess(
          ownerUid: 'owner123',
          matchmakerUid: 'reader',
          status: CardAccessStatus.approved,
          requestedBy: 'owner',
        ),
      );
      await tester.pumpWidget(route());
      expect(find.text('/people/${friend.id}?focus=card'), findsOneWidget);
      access.grants.clear();
      await tester.pumpWidget(route());
      expect(find.text('/people/${friend.id}?focus=request'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a matchmaker sees friends with a card and asks only those without access',
    (tester) async {
      access.grants.add(
        const CardAccess(
          ownerUid: 'reader-card',
          matchmakerUid: 'me',
          status: CardAccessStatus.approved,
          requestedBy: 'owner',
          ownerName: 'דנה כהן',
        ),
      );
      await tester.pumpWidget(app(home: const FriendsWithCardsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('חברים שלי שהוסיפו כרטיס אישי'), findsOneWidget);
      expect(find.text('נועה'), findsOneWidget);
      expect(find.text('אפשר לבקש גישה'), findsOneWidget);
      expect(find.text('בקשת גישה'), findsOneWidget);
      expect(find.text('דנה כהן'), findsOneWidget);
      expect(find.text('יש לך גישה לכרטיס'), findsOneWidget);
      // Those still to ask lead the list.
      expect(
        tester.getTopLeft(find.text('נועה')).dy,
        lessThan(tester.getTopLeft(find.text('דנה כהן')).dy),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('a matchmaker reads a single\'s wishes under their own gender', () {
    expect(PrivateLookingBlock.headingFor(Gender.female), 'מה היא מחפשת');
    expect(PrivateLookingBlock.headingFor(Gender.male), 'מה הוא מחפש');
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('personal home and matchmakers fit $width px at large type', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(scale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('השדכנים שלי').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
