import 'package:flutter/material.dart';
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
      onOpenWhatsApp: (_) {},
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

  testWidgets('the WhatsApp shortcut moved to the card edge', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(card(onAction: (_) {})));
    await tester.pump();

    final List<Offset> chats = tester
        .widgetList<FaIcon>(find.byType(FaIcon))
        .map((FaIcon icon) => tester.getCenter(find.byWidget(icon)))
        .toList();
    expect(chats, hasLength(2));

    // Each chat sits outside its own side's name — further from the card's
    // centre than the name it belongs to.
    final double cardCentre = tester.getCenter(find.byType(MatchIdeaCard)).dx;
    for (final Offset chat in chats) {
      expect((chat.dx - cardCentre).abs(), greaterThan(120));
    }
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
    expect(find.text('פעולות מהירות'), findsOneWidget);
    expect(find.text('מתחילים לצאת'), findsNothing);
    final double closedHeight = tester
        .getSize(find.byType(MatchIdeaCard))
        .height;

    await tester.tap(find.text('פעולות מהירות'));
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
    await tester.tap(find.text('פעולות מהירות'));
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

    expect(find.text('פעולות מהירות'), findsNothing);
  });
}
