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
}
