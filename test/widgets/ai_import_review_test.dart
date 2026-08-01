import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/screens/ai_import_review_screen.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/parsed_person.dart';

/// Which imported people the user is actually shown, and how a record leaves
/// the attention list.
///
/// The screen is the last thing standing between a model's answer and eighty
/// new contacts, and the choice it implements is a subtle one: records read in
/// full are folded away, and only what was guessed or missing is put in front
/// of the user. Getting that split wrong in either direction is invisible —
/// too eager and guesses are written unseen, too cautious and the import is
/// no faster than typing.
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );
  }

  ParsedPerson person({
    String firstName = 'יוסי',
    String lastName = 'כהן',
    int? age = 27,
    Gender? gender = Gender.male,
    Set<ParsedField> inferred = const <ParsedField>{},
  }) {
    return ParsedPerson(
      card: ParsedCard(
        firstName: firstName,
        lastName: lastName,
        age: age,
        gender: gender,
      ),
      inferredFields: inferred,
    );
  }

  testWidgets('records read in full are folded away, not put in front of the '
      'user', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        AiImportReviewScreen(
          people: <ParsedPerson>[
            person(),
            person(firstName: 'אברהם'),
          ],
        ),
      ),
    );

    expect(find.text('מוכנים להוספה (2)'), findsOneWidget);
    expect(find.text('דורשים תשומת לב'), findsNothing);
    // Folded, but reachable — the user can always see what is about to be
    // written.
    expect(find.text('הצג'), findsOneWidget);
  });

  testWidgets('a gender guessed from the name is put in front of the user', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AiImportReviewScreen(
          people: <ParsedPerson>[
            person(
              firstName: 'נועה',
              gender: Gender.female,
              inferred: <ParsedField>{ParsedField.gender},
            ),
          ],
        ),
      ),
    );

    expect(find.text('דורשים תשומת לב'), findsOneWidget);
    expect(find.text('המגדר שוער מהשם — נא לאשר'), findsOneWidget);
  });

  testWidgets('confirming the guessed gender moves the record to ready', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AiImportReviewScreen(
          people: <ParsedPerson>[
            person(
              firstName: 'נועה',
              gender: Gender.female,
              inferred: <ParsedField>{ParsedField.gender},
            ),
          ],
        ),
      ),
    );

    // Agreeing with the guess needs its own control: tapping the segment that
    // is already selected clears it instead of confirming it.
    await tester.tap(find.text('נכון'));
    await tester.pumpAndSettle();

    expect(find.text('דורשים תשומת לב'), findsNothing);
    expect(find.text('מוכנים להוספה (1)'), findsOneWidget);
  });

  testWidgets('choosing the other gender also settles the record', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AiImportReviewScreen(
          people: <ParsedPerson>[
            person(
              firstName: 'נועה',
              gender: Gender.female,
              inferred: <ParsedField>{ParsedField.gender},
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('בחור'));
    await tester.pumpAndSettle();

    expect(find.text('דורשים תשומת לב'), findsNothing);
    expect(find.text('מוכנים להוספה (1)'), findsOneWidget);
  });

  testWidgets('a missing age is called out by name', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(AiImportReviewScreen(people: <ParsedPerson>[person(age: null)])),
    );

    expect(find.text('חסר גיל'), findsOneWidget);
  });

  testWidgets('a record with no gender at all is called out differently', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AiImportReviewScreen(
          people: <ParsedPerson>[person(firstName: 'שי', gender: null)],
        ),
      ),
    );

    expect(find.text('לא ברור אם זה בחור או בחורה'), findsOneWidget);
  });

  testWidgets(
    'removing a record drops it from the count that will be written',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          AiImportReviewScreen(
            people: <ParsedPerson>[
              person(age: null),
              person(firstName: 'אברהם'),
            ],
          ),
        ),
      );

      expect(find.text('הוספת 2 אנשים למאגר'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('הוספת 1 אנשים למאגר'), findsOneWidget);
      expect(find.text('דורשים תשומת לב'), findsNothing);
    },
  );

  testWidgets('a partly unreadable file says so instead of looking complete', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AiImportReviewScreen(
          people: <ParsedPerson>[person()],
          failedBatches: 2,
        ),
      ),
    );

    expect(find.textContaining('חלק מהקובץ לא נקרא'), findsOneWidget);
  });
}
