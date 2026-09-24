import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// **One bar, everywhere.**
///
/// Coloured rules had been drawn by hand wherever one was wanted — down a
/// person's row, down both edges of a proposal, under a card — and they came
/// out at different thicknesses and opacities, which is what made otherwise
/// identical lists read as unrelated ones. These are the assertions that keep
/// them the same bar.
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets('a stripe is the one thickness, rounded on its inner edge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const Row(
          children: <Widget>[
            AccentStripe(color: Color(0xFF112233), height: 40),
            Spacer(),
            AccentStripe(color: Color(0xFF332211), atStart: false, height: 40),
          ],
        ),
      ),
    );

    expect(find.byType(AccentStripe), findsNWidgets(2));
    for (int index = 0; index < 2; index++) {
      expect(
        tester.getSize(find.byType(AccentStripe).at(index)).width,
        AccentBar.thickness,
      );
    }

    // The rounding faces inwards, so the two bars of a couple curve towards
    // each other rather than away.
    final List<BorderRadiusDirectional> radii = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(AccentStripe),
            matching: find.byType(Container),
          ),
        )
        .map(
          (Container c) =>
              (c.decoration! as BoxDecoration).borderRadius!
                  as BorderRadiusDirectional,
        )
        .toList();
    expect(radii.first.topEnd.x, AccentBar.radius);
    expect(radii.first.topStart.x, 0);
    expect(radii.last.topStart.x, AccentBar.radius);
    expect(radii.last.topEnd.x, 0);
  });

  testWidgets('an underline is the same rule, turned', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const Column(children: <Widget>[AccentUnderline(color: Colors.red)]),
      ),
    );

    expect(
      tester.getSize(find.byType(AccentUnderline)).height,
      AccentBar.thickness,
    );
  });

  testWidgets('a person row in המאגר שלי draws that one bar, in their own '
      'colour', (WidgetTester tester) async {
    final DateTime now = DateTime(2026, 9, 1);
    await tester.pumpWidget(
      wrap(
        PersonListCard(
          person: Person(
            id: 'p1',
            firstName: 'שירה',
            lastName: 'שמר',
            gender: Gender.female,
            manualAge: 24,
            createdAt: now,
            updatedAt: now,
          ),
          onTap: () {},
        ),
      ),
    );

    final Finder stripe = find.descendant(
      of: find.byType(PersonListCard),
      matching: find.byType(AccentStripe),
    );
    // One person, one bar — the second one belongs to a couple.
    expect(stripe, findsOneWidget);
    expect(
      tester.widget<AccentStripe>(stripe).color,
      AppColors.genderAccent(Gender.female),
    );
  });
}
