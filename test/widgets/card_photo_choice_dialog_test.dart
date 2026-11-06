import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/dialogs/card_photo_choice_dialog.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  testWidgets('asks which four of six photos to keep, and keeps only those', (
    WidgetTester tester,
  ) async {
    final List<String> six = <String>[
      for (int i = 0; i < 6; i++) '/no/p$i.jpg',
    ];
    List<String>? kept;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                kept = await CardPhotoChoiceDialog.show(
                  context,
                  six,
                  gender: Gender.female,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('אפשר לשמור עד 4 תמונות בכרטיס. בחרי אילו תמונות תרצי להשאיר.'),
      findsOneWidget,
    );
    expect(find.text('נבחרו 4 מתוך 4'), findsOneWidget);

    final Finder tiles = find.bySemanticsLabel(RegExp('תמונה'));
    // Full: a fifth cannot be ticked.
    await tester.tap(tiles.at(4));
    await tester.pump();
    expect(find.text('נבחרו 4 מתוך 4'), findsOneWidget);
    // Untick the first, tick the sixth.
    await tester.tap(tiles.at(0));
    await tester.pump();
    await tester.tap(tiles.at(5));
    await tester.pump();

    await tester.tap(find.text('שמירה'));
    await tester.pumpAndSettle();
    expect(kept, <String>[six[1], six[2], six[3], six[5]]);
  });

  test('only a card with more than four photos needs the question', () {
    expect(
      CardPhotoChoiceDialog.needed(const <String>['a', 'b', 'c', 'd']),
      isFalse,
    );
    expect(
      CardPhotoChoiceDialog.needed(const <String>['a', 'b', 'c', 'd', 'e']),
      isTrue,
    );
    expect(
      CardPhotoChoiceDialog.message(null),
      'אפשר לשמור עד 4 תמונות בכרטיס. בחר/בחרי אילו תמונות תרצה/תרצי להשאיר.',
    );
  });
}
