import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/dialogs/import_problem_dialog.dart';
import 'package:shadchan/utils/community_links.dart';

/// The way out of a failed import.
///
/// The whole point of this dialog is that a failure the developer cannot
/// reproduce still reaches them. Two things have to hold for that: the report
/// must actually be on the clipboard when the person leaves the screen, and the
/// address it can be sent to has to be the right one — a wrong character is a
/// feature that looks like it works and delivers nothing.
void main() {
  const String report = 'דיווח תקלה — ייבוא וואטסאפ\n---\nגודל: 180.0 MB';

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ImportProblemDialog.show(
                    context,
                    message: 'הייצוא גדול מדי לזיכרון של המכשיר הזה.',
                    hint: 'נסו לייצא שוב עם "ללא מדיה".',
                    report: report,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('it says which failure this was, and offers the way out', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('הייצוא גדול מדי לזיכרון של המכשיר הזה.'), findsOneWidget);
    expect(find.text('נסו לייצא שוב עם "ללא מדיה".'), findsOneWidget);
    expect(find.text('שליחת הבעיה למפתחי האפליקציה'), findsOneWidget);
    expect(find.text('העתקה'), findsOneWidget);
  });

  testWidgets('the report is there to be read before it is sent', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester);

    // Not shown by default — the person came to import a file. But a promise
    // about what is in the report is worth nothing without the report.
    expect(find.text(report), findsNothing);
    await tester.tap(find.text('מה יישלח למפתחים?'));
    await tester.pumpAndSettle();
    expect(find.text(report), findsOneWidget);
  });

  testWidgets('העתקה puts the whole report on the clipboard', (
    WidgetTester tester,
  ) async {
    Object? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'];
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpDialog(tester);
    await tester.tap(find.text('העתקה'));
    await tester.pumpAndSettle();

    expect(copied, report);
  });

  test('the fallback mail goes to the one support address', () {
    // Support has a single channel now — the in-app form, with e-mail behind
    // it. Nothing here opens WhatsApp any more.
    expect(CommunityLinks.supportEmail, 'shadchanapp123@gmail.com');

    final Uri uri = CommunityLinks.mailto(subject: 'נושא כלשהו', body: 'a b');
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'shadchanapp123@gmail.com');
    // A space must survive as %20 rather than as `+`, which several mail
    // clients drop straight into the subject line.
    expect(uri.query.contains('+'), isFalse);
    expect(Uri.decodeComponent(uri.queryParameters['body']!), 'a b');
  });
}
