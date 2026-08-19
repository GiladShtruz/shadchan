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

/// The proposal card is now a place to *work*, not only to read.
///
/// Two things are worth holding still: each side's availability is changeable
/// where the WhatsApp icon used to be, and the proposal's own actions are one
/// folded bar rather than three permanent buttons — the whole point being that
/// the card does not grow into a control panel.
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
    MatchStatus status = MatchStatus.idea,
    void Function(Person, ProfileStatus)? onStatus,
    ValueChanged<MatchQuickAction>? onAction,
  }) {
    return MatchIdeaCard(
      match: match(status: status),
      male: person('male', 'דוד', Gender.male, ProfileStatus.available),
      female: person('female', 'שרה', Gender.female, ProfileStatus.onBreak),
      onTap: () {},
      onOpenPersonWhatsApp: (_) {},
      onCompletePersonCard: (_) {},
      onPersonStatusPicked: onStatus,
      onQuickAction: onAction,
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
    final Offset status = tester.getCenter(find.text('עדכון סטטוס'));
    expect(chat.dy, lessThan(status.dy));

    // In RTL the first child sits on the right, and that side is the woman's.
    await tester.tap(find.byType(FaIcon).first);
    await tester.pump();
    expect(opened, <String>['female']);

    await tester.tap(find.byType(FaIcon).last);
    await tester.pump();
    expect(opened, <String>['female', 'male']);
  });

  testWidgets('an archived proposal keeps its chat button', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(card(status: MatchStatus.rejected, onAction: (_) {})),
    );
    await tester.pump();

    // There is no status left worth setting, but there is every reason still to
    // message the people in it.
    expect(find.text('עדכון סטטוס'), findsNothing);
    expect(find.byType(FaIcon), findsNWidgets(2));
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
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<MatchQuickAction> ran = <MatchQuickAction>[];
    await tester.pumpWidget(wrap(card(onAction: ran.add)));
    await tester.pump();

    // Closed: one line, no buttons.
    expect(find.text('עדכון סטטוס'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsNothing);
    final double closedHeight = tester
        .getSize(find.byType(MatchIdeaCard))
        .height;

    await tester.tap(find.text('עדכון סטטוס'));
    await tester.pumpAndSettle();

    expect(find.text('העברה להמתנה'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsOneWidget);
    expect(find.text('סגירת הצעה'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Opening costs one row, not a second card.
    expect(
      tester.getSize(find.byType(MatchIdeaCard)).height - closedHeight,
      lessThan(70),
    );

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
    await tester.tap(find.text('עדכון סטטוס'));
    await tester.pumpAndSettle();

    expect(find.text('מתחילים לצאת'), findsNothing);
    expect(find.text('סגירת הצעה'), findsOneWidget);
  });

  testWidgets('an archived proposal offers no quick actions at all', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(card(status: MatchStatus.rejected, onAction: (_) {})),
    );
    await tester.pump();

    expect(find.text('עדכון סטטוס'), findsNothing);
  });

  testWidgets('the three quick actions are drawn as peers, not a winner', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(card(onAction: (_) {})));
    await tester.pump();
    await tester.tap(find.text('עדכון סטטוס'));
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

  testWidgets('a candidate with no number is offered a pencil, not WhatsApp', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<String> completed = <String>[];
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
          onCompletePersonCard: (Person p) => completed.add(p.id),
        ),
      ),
    );
    await tester.pump();

    // One WhatsApp icon, for the side that has a number.
    expect(find.byType(FaIcon), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(completed, <String>['male']);
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
