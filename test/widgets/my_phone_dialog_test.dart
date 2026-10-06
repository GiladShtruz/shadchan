import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/utils/app_theme.dart';

void main() {
  testWidgets(
    'with the keyboard up on a small phone, the number can still be typed '
    'and saved',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      String? result = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          builder: (BuildContext context, Widget? child) => Directionality(
            textDirection: TextDirection.rtl,
            child: DismissKeyboardOnTap(child: child!),
          ),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await MyPhoneDialog.show(
                      context,
                      purpose: MyPhonePurpose.matchmakerRequest,
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.textContaining('שמורים אחד אצל השני'), findsOneWidget);
      expect(find.text('המספר ישמש לזיהוי וסנכרון מול החבר.'), findsOneWidget);

      // The keyboard comes up: half of a 640pt-high phone.
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byType(TextField));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.testTextInput.enterText('0501234567');
      await tester.pump();
      await tester.ensureVisible(find.text('שמירה'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('שמירה'));
      await tester.pumpAndSettle();
      expect(result, '0501234567');
    },
  );

  Future<void> openSignUp(
    WidgetTester tester, {
    required void Function(MyPhoneOutcome) onResult,
    Future<bool> Function(String phone)? taken,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        builder: (BuildContext context, Widget? child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  onResult(
                    await MyPhoneDialog.showForSignUp(
                      context,
                      purpose: MyPhonePurpose.matchmaker,
                      belongsToAnotherAccount: taken,
                    ),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('sign-up: "שמירה" on the right and filled, "דילוג" on the left', (
    WidgetTester tester,
  ) async {
    MyPhoneOutcome? result;
    await openSignUp(tester, onResult: (MyPhoneOutcome r) => result = r);

    expect(
      find.textContaining('אנשי קשר שלך שמנהלים כרטיס אישי'),
      findsOneWidget,
    );
    expect(find.textContaining('חברים שלך שמנהלים'), findsNothing);

    final Offset save = tester.getCenter(find.text('שמירה'));
    final Offset skip = tester.getCenter(find.text('דילוג'));
    expect(save.dx, greaterThan(skip.dx));
    expect(
      find.ancestor(
        of: find.text('שמירה'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );

    // Skipping goes on without a number.
    await tester.tap(find.text('דילוג'));
    await tester.pumpAndSettle();
    expect(result?.phone, isNull);
    expect(result?.useExistingAccount, isFalse);
  });

  testWidgets('a number already in the system asks what to do', (
    WidgetTester tester,
  ) async {
    MyPhoneOutcome? result;
    await openSignUp(
      tester,
      onResult: (MyPhoneOutcome r) => result = r,
      taken: (String phone) async => true,
    );
    await tester.enterText(find.byType(TextField), '0501234567');
    await tester.tap(find.text('שמירה'));
    await tester.pumpAndSettle();

    expect(
      find.text('מספר הטלפון הזה כבר קיים במערכת. מה תרצה לעשות?'),
      findsOneWidget,
    );
    await tester.tap(find.text('יצירת חשבון נוסף עם מספר זה'));
    await tester.pumpAndSettle();
    expect(result?.phone, '0501234567');

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0501234567');
    await tester.tap(find.text('שמירה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('התחברות לחשבון הקיים'));
    await tester.pumpAndSettle();
    expect(result?.useExistingAccount, isTrue);
    expect(result?.phone, isNull);
  });
}
