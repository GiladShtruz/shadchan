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
  bool get isConnected => true;
  @override
  bool get helpersLoaded => true;
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

  testWidgets('home is compact, gendered and grants card access in one tap', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('תני לחברים שלך לחשוב עלייך'), findsOneWidget);
    expect(find.text('טקסט הכרטיס המלא', findRichText: true), findsNothing);
    expect(find.text('לתת גישה'), findsOneWidget);
    await tester.tap(find.text('לתת גישה'));
    await tester.pumpAndSettle();
    expect(access.grantCalls, 1);
    expect(access.approved, hasLength(1));
    expect(find.text('אורי'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
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
      expect(find.text('חברים שאפשר לאשר'), findsOneWidget);
      expect(find.text('חברים שאישרתי'), findsOneWidget);
      expect(find.textContaining('הכרטיס שלך גלוי רק לחברים'), findsOneWidget);
      expect(find.text('12 חברים במאגר'), findsOneWidget);
    },
  );
  testWidgets(
    'own-card preview uses the shared viewer without adding an owner record or private wishes',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('צפייה בכרטיס'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('צפייה בכרטיס'));
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
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('הסתרה'));
      await tester.pumpAndSettle();
      expect(find.text('אורי'), findsNothing);
      expect(access.approved, isEmpty);
      await tester.tap(find.text('השדכנים שלי').last);
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

  for (final width in [320.0, 390.0]) {
    testWidgets('personal home and matchmakers fit $width px at large type', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
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
