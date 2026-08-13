import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/add_contacts_common.dart';

void main() {
  Widget wrap(int added) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AddContactsProgressHeader(
            addedToDatabase: added,
            remaining: 2,
            total: 10,
          ),
        ),
      ),
    );
  }

  testWidgets('progress follows the persistent database total', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(7));

    LinearProgressIndicator indicator = tester.widget(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.7);
    expect(find.text('כבר הוספת 7 חברים למאגר'), findsOneWidget);

    await tester.pumpWidget(wrap(8));
    indicator = tester.widget(find.byType(LinearProgressIndicator));
    expect(indicator.value, 0.8);
    expect(find.text('כבר הוספת 8 חברים למאגר'), findsOneWidget);
  });
}
