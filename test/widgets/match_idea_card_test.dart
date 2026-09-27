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
  // The status is one rich line: "סטטוס: " and the label.
  Finder status(String label) =>
      find.text('סטטוס: $label', findRichText: true);

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
    // Drawn exactly as המאגר שלי draws it: the dot and the word, in the
    // person's own colour.
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
    expect(status('נסגרה'), findsOneWidget);

    // The panel does not disappear with the proposal: its journal is still
    // worth reading.
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();
    expect(find.text('יומן הרעיון'), findsOneWidget);

    // The way back open is on the card's own status, and nothing that no
    // longer means anything from where it stands.
    await tester.tap(status('נסגרה'));
    await tester.pumpAndSettle();
    expect(find.text('פתיחה מחדש'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsNothing);
    expect(find.text('סגירת רעיון'), findsNothing);
  });

  testWidgets('every card says where the proposal stands', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // An open idea says its stage — what it is waiting for — and anything
    // else says its state.
    for (final (MatchStatus status, String label) expected
        in <(MatchStatus, String)>[
          (MatchStatus.idea, 'רעיון חדש'),
          (MatchStatus.checking, 'רעיון חדש'),
          (MatchStatus.unavailable, 'בהמתנה'),
          (MatchStatus.dated, 'נסגרה'),
        ]) {
      await tester.pumpWidget(wrap(card(status: expected.$1)));
      await tester.pump();
      expect(status(expected.$2), findsOneWidget, reason: expected.$1.name);
    }
  });

  testWidgets('"יאללה לקדם" is the same panel at every stage', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final (DateTime?, DateTime?) asked in <(DateTime?, DateTime?)>[
      (null, null),
      (DateTime(2026, 8, 20), null),
      (DateTime(2026, 8, 20), DateTime(2026, 8, 21)),
    ]) {
      final List<MatchNextStep> steps = <MatchNextStep>[];
      await tester.pumpWidget(
        wrap(
          card(
            key: ValueKey<String>('${asked.$1}-${asked.$2}'),
            status: asked.$1 == null ? MatchStatus.idea : MatchStatus.checking,
            askedMaleAt: asked.$1,
            askedFemaleAt: asked.$2,
            onAction: (_) {},
            onAdvance: steps.add,
            onSetStage: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('פעולות'));
      await tester.pumpAndSettle();

      // Heading, question, one WhatsApp button per side — whatever the stage
      // behind it is.
      expect(find.text('יאללה לקדם'), findsOneWidget);
      expect(find.text('את מי תרצה לשאול על הרעיון?'), findsOneWidget);
      expect(
        tester.getCenter(find.text('יאללה לקדם')).dy,
        lessThan(tester.getCenter(find.text('יומן הרעיון')).dy),
      );

      // Her button is on the right, under her face; his on the left.
      await tester.tap(find.text('שרה').last);
      await tester.pump();
      await tester.tap(find.text('דוד').last);
      await tester.pump();
      expect(steps, <MatchNextStep>[
        MatchNextStep.askFemale,
        MatchNextStep.askMale,
      ]);
    }
  });

  testWidgets('the status sits at the foot of the card, with its menu', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<MatchQuickAction> actions = <MatchQuickAction>[];
    final List<MatchStage> stages = <MatchStage>[];
    await tester.pumpWidget(
      wrap(card(onAction: actions.add, onSetStage: stages.add)),
    );
    await tester.pump();

    // The reminder date is no longer on the card — only the status.
    expect(find.text('הוספת תזכורת'), findsNothing);
    expect(status('רעיון חדש'), findsOneWidget);

    await tester.tap(status('רעיון חדש'));
    await tester.pumpAndSettle();
    // Every stage, and the two moves that leave them, last.
    expect(find.text('מחכים לתשובת הבחור'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsOneWidget);
    expect(find.text('העברה להמתנה'), findsOneWidget);
    expect(
      tester.getCenter(find.text('סגירת רעיון')).dy,
      greaterThan(tester.getCenter(find.text('מתחילים לצאת')).dy),
    );

    await tester.tap(find.text('סגירת רעיון'));
    await tester.pumpAndSettle();
    expect(actions, <MatchQuickAction>[MatchQuickAction.close]);
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
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<MatchQuickAction> ran = <MatchQuickAction>[];
    await tester.pumpWidget(wrap(card(onAction: ran.add, onAdvance: (_) {})));
    await tester.pump();

    // Closed: one line, no buttons.
    expect(find.text('פעולות'), findsOneWidget);
    expect(find.text('יאללה לקדם'), findsNothing);

    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // One box: the push, the reminder, the go-between — and no status in it,
    // because the status is on the card.
    expect(find.text('יאללה לקדם'), findsOneWidget);
    expect(find.text('אין תזכורת'), findsOneWidget);
    expect(find.text('הוספת איש קשר שקשור להצעה'), findsOneWidget);
    expect(find.text('העברה להמתנה'), findsNothing);
    expect(find.text('יומן הרעיון'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('הוספה'));
    await tester.pump();
    // The contact line is its own quiet row under the box, tapped as a whole.
    await tester.tap(find.text('הוספת איש קשר שקשור להצעה'));
    await tester.pump();
    expect(ran, <MatchQuickAction>[
      MatchQuickAction.reminder,
      MatchQuickAction.contact,
    ]);
  });

  testWidgets('a couple already out are offered the wedding or the parting', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(card(status: MatchStatus.dating, onAction: (_) {})),
    );
    await tester.pump();
    await tester.tap(status('יוצאים'));
    await tester.pumpAndSettle();

    expect(find.text('מתחילים לצאת'), findsNothing);
    expect(find.text('חתונה'), findsOneWidget);
    // A couple who stop are "נפרדו", not a proposal being closed.
    expect(find.text('נפרדו'), findsOneWidget);
    expect(find.text('סגירת רעיון'), findsNothing);
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
