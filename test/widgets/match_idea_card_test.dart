import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/widgets/match_idea_card.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// The proposal card is now the *only* place to work — there is no proposal
/// screen behind it any more.
///
/// Three things are worth holding still. Each side's availability is
/// changeable where the WhatsApp icon used to be. Everything the proposal
/// screen offered is one folded bar rather than a wall of buttons, so the card
/// does not grow into a control panel. And the proposal's own status is on
/// every card, always, because a list you cannot read the state of is a list
/// you have to open forty times.
void main() {
  final DateTime now = DateTime(2026, 8, 14);

  // The card carries the proposal's journal inside its actions panel, so it
  // needs the repository the journal reads — the same one it has in the app,
  // where every screen drawing this card sits under the root providers.
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDirectory = await Directory.systemTemp.createTemp('shadchan_card_test');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MatchIdeaAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MatchNoteAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MatchStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(CurrentHandlerAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(MatchProgressAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MatchContactAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(MatchStatusEventAdapter());
    }
    await Hive.openBox<MatchIdea>('matches');
    await Hive.openBox<MatchNote>('match_notes');
    await Hive.openBox<MatchStatusEvent>('match_status_events');
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      hiveDirectory.deleteSync(recursive: true);
    }
  });

  Person person(String id, String name, Gender gender, ProfileStatus status) {
    return Person(
      id: id,
      firstName: name,
      lastName: 'לוי',
      gender: gender,
      manualAge: 26,
      profileStatus: status,
      phone: '0501234567',
      createdAt: now,
      updatedAt: now,
    );
  }

  MatchIdea match({MatchStatus status = MatchStatus.idea}) {
    return MatchIdea(
      id: 'm',
      personAId: 'male',
      personBId: 'female',
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<MatchRepository>(
      create: (_) => MatchRepository(
        Hive.box<MatchIdea>('matches'),
        Hive.box<MatchNote>('match_notes'),
        Hive.box<MatchStatusEvent>('match_status_events'),
      ),
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        ),
      ),
    );
  }

  Widget card({
    Key? key,
    MatchStatus status = MatchStatus.idea,
    String? shareLabel,
    void Function(Person, ProfileStatus)? onStatus,
    ValueChanged<MatchQuickAction>? onAction,
    void Function(MatchNextStep step)? onAdvance,
    void Function(MatchStage stage)? onSetStage,
    DateTime? askedMaleAt,
    DateTime? askedFemaleAt,
    DateTime? datingSince,
  }) {
    final MatchIdea idea = match(status: status)
      ..lastShareLabel = shareLabel
      ..askedMaleAt = askedMaleAt
      ..askedFemaleAt = askedFemaleAt;
    return MatchIdeaCard(
      key: key,
      match: idea,
      male: person('male', 'דוד', Gender.male, ProfileStatus.available),
      female: person('female', 'שרה', Gender.female, ProfileStatus.onBreak),
      onTap: () {},
      onOpenPersonWhatsApp: (_) {},
      onCompletePersonCard: (_) {},
      onPersonStatusPicked: onStatus,
      onQuickAction: onAction,
      onAdvance: onAdvance,
      onSetStage: onSetStage,
      datingSince: datingSince,
    );
  }

  testWidgets('each side carries its own availability, changeable in place', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<(String, ProfileStatus)> picked = <(String, ProfileStatus)>[];
    await tester.pumpWidget(
      wrap(
        card(
          onStatus: (Person p, ProfileStatus s) => picked.add((p.id, s)),
          onAction: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // One chip per side, showing that side's own status.
    expect(find.byType(ProfileStatusTag), findsNWidgets(2));
    expect(find.text('פנוי'), findsOneWidget);
    expect(find.text('בהפסקה'), findsOneWidget);

    await tester.tap(find.text('פנוי'));
    await tester.pumpAndSettle();
    // "מזל טוב" is written by the app when a proposal ends in a wedding; it is
    // not something to pick by hand.
    expect(find.text('תפוס'), findsOneWidget);
    expect(find.text('מזל טוב'), findsNothing);

    await tester.tap(find.text('תפוס').last);
    await tester.pumpAndSettle();
    expect(picked, <(String, ProfileStatus)>[('male', ProfileStatus.busy)]);
  });

  testWidgets('each side carries its own WhatsApp button, on its own face', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<String> opened = <String>[];
    await tester.pumpWidget(
      wrap(
        MatchIdeaCard(
          match: match(),
          male: person('male', 'דוד', Gender.male, ProfileStatus.available),
          female: person('female', 'שרה', Gender.female, ProfileStatus.busy),
          onTap: () {},
          onOpenPersonWhatsApp: (Person person) => opened.add(person.id),
          onCompletePersonCard: (_) {},
          onQuickAction: (_) {},
        ),
      ),
    );
    await tester.pump();

    // Two, one per side. A single icon under two faces cannot say whose chat
    // it opens, which is the whole reason this changed.
    expect(find.byType(FaIcon), findsNWidgets(2));

    // Up beside the photos rather than down on the status bar — a button that
    // belongs to a person has to be next to that person.
    final Offset chat = tester.getCenter(find.byType(FaIcon).first);
    final Offset status = tester.getCenter(find.text('פעולות'));
    expect(chat.dy, lessThan(status.dy));

    // In RTL the first child sits on the right, and that side is the woman's.
    await tester.tap(find.byType(FaIcon).first);
    await tester.pump();
    expect(opened, <String>['female']);

    await tester.tap(find.byType(FaIcon).last);
    await tester.pump();
    expect(opened, <String>['female', 'male']);
  });

  testWidgets('a closed proposal keeps its chat buttons and its journal', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(card(status: MatchStatus.rejected, onAction: (_) {})),
    );
    await tester.pump();

    expect(find.byType(FaIcon), findsNWidgets(2));
    expect(find.text('נסגרה'), findsOneWidget);

    // The panel does not disappear with the proposal. A closed proposal still
    // has a journal worth reading and a way back open; what it loses is the
    // moves that no longer mean anything from where it stands.
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    expect(find.text('פתיחה מחדש'), findsOneWidget);
    expect(find.text('יומן הרעיון'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsNothing);
    expect(find.text('סגירת הצעה'), findsNothing);
  });

  testWidgets('every card says where the proposal stands', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // One coarse word, not the stored status: "רעיון" and "בבדיקה" are both a
    // proposal that is open, and a matchmaker scanning the list reads the
    // state, not the database value.
    for (final (MatchStatus status, String label) expected
        in <(MatchStatus, String)>[
          (MatchStatus.idea, 'פתוח'),
          (MatchStatus.checking, 'פתוח'),
          (MatchStatus.unavailable, 'בהמתנה'),
          (MatchStatus.dated, 'נסגרה'),
        ]) {
      await tester.pumpWidget(wrap(card(status: expected.$1)));
      await tester.pump();
      expect(find.text(expected.$2), findsOneWidget, reason: expected.$1.name);
    }
  });

  testWidgets('"יאללה לקדם" names the next step and leads the panel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<MatchNextStep> steps = <MatchNextStep>[];
    await tester.pumpWidget(
      wrap(card(onAction: (_) {}, onAdvance: steps.add, onSetStage: (_) {})),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // Nobody has been asked yet, so the step is the boy — by name, because the
    // card knows who he is. And it is the *first* thing under the fold: the
    // three status tiles are the three ways a proposal ends, and offering them
    // above the one thing it is waiting for was the wrong way round.
    expect(find.text('יאללה לקדם — לשאול את דוד'), findsOneWidget);
    expect(
      tester.getCenter(find.text('יאללה לקדם — לשאול את דוד')).dy,
      lessThan(tester.getCenter(find.text('מתחילים לצאת')).dy),
    );
    // The stage, beside it and editable — most matchmaking happens on a call
    // the app never sees.
    expect(find.text('רעיון חדש'), findsOneWidget);
    // And the way to start with her instead, offered only while it is still a
    // choice.
    expect(find.text('לפנות קודם לבחורה'), findsOneWidget);

    await tester.tap(find.text('יאללה לקדם — לשאול את דוד'));
    await tester.pump();
    expect(steps, <MatchNextStep>[MatchNextStep.askMale]);

    // With him already asked, the same button offers the other side. A fresh
    // key, so the panel starts folded again rather than inheriting the open
    // state of the card above.
    await tester.pumpWidget(
      wrap(
        card(
          key: const ValueKey<String>('asked-him'),
          status: MatchStatus.checking,
          askedMaleAt: DateTime(2026, 8, 20),
          shareLabel: 'הכרטיס של שרה נשלח לדוד',
          onAction: (_) {},
          onAdvance: (_) {},
          onSetStage: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    expect(find.text('יאללה לקדם — לשאול את שרה'), findsOneWidget);
    expect(find.text('שאלתי את הבחור'), findsOneWidget);
    expect(find.text('לפנות קודם לבחורה'), findsNothing);
    // What already went out is context under the button, not the button.
    expect(find.text('הכרטיס של שרה נשלח לדוד'), findsOneWidget);

    // Both asked: the only thing left is the two of them meeting.
    await tester.pumpWidget(
      wrap(
        card(
          key: const ValueKey<String>('asked-both'),
          status: MatchStatus.checking,
          askedMaleAt: DateTime(2026, 8, 20),
          askedFemaleAt: DateTime(2026, 8, 21),
          onAction: (_) {},
          onAdvance: (_) {},
          onSetStage: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    expect(find.text('יאללה לקדם — מתחילים לצאת'), findsOneWidget);
    expect(find.text('שאלתי את שניהם'), findsOneWidget);
  });

  testWidgets('a week with nothing happening says so, without reordering', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MatchIdea stale = match()
      ..updatedAt = DateTime.now().subtract(const Duration(days: 9));
    await tester.pumpWidget(
      wrap(
        MatchIdeaCard(
          match: stale,
          male: person('male', 'דוד', Gender.male, ProfileStatus.available),
          female: person(
            'female',
            'שרה',
            Gender.female,
            ProfileStatus.available,
          ),
          onTap: () {},
          onOpenPersonWhatsApp: (_) {},
          onCompletePersonCard: (_) {},
          onQuickAction: (_) {},
          onAdvance: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // In the promote area, where somebody is already deciding what to do — and
    // nowhere else. The list stays in its own order.
    expect(
      find.text('עבר שבוע בלי עדכון – שווה לקדם את הרעיון'),
      findsOneWidget,
    );
  });

  testWidgets('a couple who are out are asked about, not promoted', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        card(
          status: MatchStatus.dating,
          datingSince: DateTime.now().subtract(const Duration(days: 7)),
          onAction: (_) {},
          onAdvance: (_) {},
          onSetStage: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // Asking him, asking her and sending the card are finished business.
    expect(find.textContaining('יאללה לקדם'), findsNothing);
    expect(find.text('הם יוצאים כבר 7 ימים 😊 בדקת איך הולך?'), findsOneWidget);
    // One tap to each of them, and the cadence spelled out underneath.
    expect(find.text('דוד'), findsWidgets);
    expect(find.textContaining('פעם בחודש'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long name gives up its surname before it wraps', (
    WidgetTester tester,
  ) async {
    // A narrow card and two long names: the pair of them cannot fit beside each
    // other in full, and a card that grew a line for it would make every card
    // in the list a different height.
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        MatchIdeaCard(
          match: match(),
          male: Person(
            id: 'male',
            firstName: 'יהונתן-יוסף',
            lastName: 'אברמוביץ-שטרנבוך',
            gender: Gender.male,
            manualAge: 27,
            createdAt: now,
            updatedAt: now,
          ),
          female: Person(
            id: 'female',
            firstName: 'אלישבע-מרים',
            lastName: 'רוזנבלט-הירשפלד',
            gender: Gender.female,
            manualAge: 24,
            createdAt: now,
            updatedAt: now,
          ),
          onTap: () {},
          onOpenPersonWhatsApp: (_) {},
          onCompletePersonCard: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The surname is dropped whole rather than ellipsized mid-word, and the age
    // survives either way — it is what the list is scanned for.
    expect(find.text('יהונתן-יוסף'), findsOneWidget);
    expect(find.text('אלישבע-מרים'), findsOneWidget);
    expect(find.text(', 27'), findsOneWidget);
    expect(find.text(', 24'), findsOneWidget);

    // Whatever it took, both names stayed on one line.
    for (final String name in <String>['יהונתן-יוסף', 'אלישבע-מרים']) {
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text(name),
      );
      expect(paragraph.size.height, lessThan(30), reason: name);
    }
  });

  testWidgets('a short name keeps its surname', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(card()));
    await tester.pump();

    // Nothing is given up when nothing has to be.
    expect(find.text('דוד לוי'), findsOneWidget);
    expect(find.text('שרה לוי'), findsOneWidget);
    expect(find.text(', 26'), findsNWidgets(2));
  });

  testWidgets('the proposal actions stay folded until asked for', (
    WidgetTester tester,
  ) async {
    // The narrowest phone the app supports. Three status tiles across one row
    // is where the panel would overflow if a label were allowed to set its own
    // width.
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<MatchQuickAction> ran = <MatchQuickAction>[];
    await tester.pumpWidget(wrap(card(onAction: ran.add)));
    await tester.pump();

    // Closed: one line, no buttons. "פעולות" rather than "עדכון סטטוס",
    // because what is behind it is no longer only the status.
    expect(find.text('פעולות'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsNothing);

    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // The three status moves are unchanged, and the rest of what the proposal
    // screen used to hold is beside them.
    expect(find.text('העברה להמתנה'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsOneWidget);
    expect(find.text('סגירת הצעה'), findsOneWidget);
    expect(find.text('הוספת תזכורת'), findsOneWidget);
    expect(find.text('הוספת איש קשר שקשור להצעה'), findsOneWidget);
    // Not a button: the journal is simply open at the bottom of the panel.
    expect(find.text('יומן הרעיון'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('מתחילים לצאת'));
    await tester.pump();
    expect(ran, <MatchQuickAction>[MatchQuickAction.dating]);
  });

  testWidgets('a couple already out are not offered "מתחילים לצאת" again', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(card(status: MatchStatus.dating, onAction: (_) {})),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    expect(find.text('מתחילים לצאת'), findsNothing);
    expect(find.text('חתונה'), findsOneWidget);
    expect(find.text('סגירת הצעה'), findsOneWidget);
  });

  testWidgets('the status actions are drawn as peers, not a winner', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(card(onAction: (_) {})));
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // "מתחילים לצאת" used to be filled and raised, which read as the status
    // the proposal was already in rather than one of three things to do.
    final List<Material> tiles = <Material>[
      for (final String label in <String>[
        'העברה להמתנה',
        'מתחילים לצאת',
        'סגירת הצעה',
      ])
        tester.widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        ),
    ];

    expect(tiles.map((Material m) => m.elevation), everyElement(0.0));
    // Same shape and the same weight of tint on all three; only the hue moves.
    expect(
      tiles.map((Material m) => m.color!.a).toSet(),
      hasLength(1),
      reason: 'all three tiles should carry the same tint strength',
    );
  });

  testWidgets('a candidate with no number is offered nothing at all', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        MatchIdeaCard(
          match: match(),
          // Exactly what "הוספת שם מחוץ למאגר" produces on one side.
          male: Person(
            id: 'male',
            firstName: 'דוד',
            lastName: '',
            gender: Gender.male,
            createdAt: now,
            updatedAt: now,
          ),
          female: person(
            'female',
            'שרה',
            Gender.female,
            ProfileStatus.available,
          ),
          onTap: () {},
          onOpenPersonWhatsApp: (_) {},
          onCompletePersonCard: (_) {},
        ),
      ),
    );
    await tester.pump();

    // One WhatsApp icon, for the side that has a number.
    expect(find.byType(FaIcon), findsOneWidget);
    // And nothing on the other corner. The pencil that used to sit there was a
    // different action wearing the messaging button's place — somebody
    // reaching for the corner of a face means to message that person, and an
    // empty corner says "no number" more plainly than an editor does.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('a landline is offered SMS rather than WhatsApp', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        MatchIdeaCard(
          match: match(),
          male: Person(
            id: 'male',
            firstName: 'דוד',
            lastName: '',
            gender: Gender.male,
            phone: '03-1234567',
            createdAt: now,
            updatedAt: now,
          ),
          female: person(
            'female',
            'שרה',
            Gender.female,
            ProfileStatus.available,
          ),
          onTap: () {},
          onOpenPersonWhatsApp: (_) {},
          onCompletePersonCard: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FaIcon), findsOneWidget);
    expect(find.byIcon(Icons.sms_outlined), findsOneWidget);
  });
}
