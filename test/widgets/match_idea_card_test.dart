import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
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
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(12), child: child),
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
    VoidCallback? onPromote,
  }) {
    final MatchIdea idea = match(status: status)..lastShareLabel = shareLabel;
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
      onPromote: onPromote,
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
    expect(find.text('יומן ההצעה'), findsOneWidget);
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

  testWidgets('"יאללה לקדם!" becomes a report once a card has gone out', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int promoted = 0;
    await tester.pumpWidget(
      wrap(card(onAction: (_) {}, onPromote: () => promoted++)),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    // Nothing sent yet: the row is a prompt, and it sits above the status
    // moves because sending the card is what comes first.
    expect(find.text('יאללה לקדם!'), findsOneWidget);
    expect(
      tester.getCenter(find.text('יאללה לקדם!')).dy,
      lessThan(tester.getCenter(find.text('מתחילים לצאת')).dy),
    );

    await tester.tap(find.text('יאללה לקדם!'));
    await tester.pump();
    expect(promoted, 1);

    // Once something has gone out the same row answers the question it asked.
    // A fresh key, so the panel starts folded again rather than inheriting the
    // open state of the card above.
    await tester.pumpWidget(
      wrap(
        card(
          key: const ValueKey<String>('sent'),
          shareLabel: 'הכרטיס של שרה נשלח לדוד',
          onAction: (_) {},
          onPromote: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('פעולות'));
    await tester.pumpAndSettle();

    expect(find.text('יאללה לקדם!'), findsNothing);
    expect(find.text('רעיון בבדיקה'), findsOneWidget);
    expect(find.text('הכרטיס של שרה נשלח לדוד'), findsOneWidget);
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
    // The narrowest phone the app supports. Six tiles across two rows, with
    // "הוספת איש קשר" among them, is where the panel would overflow if a label
    // were allowed to set its own width.
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
    expect(find.text('הוספת איש קשר'), findsOneWidget);
    expect(find.text('יומן ההצעה'), findsOneWidget);
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
