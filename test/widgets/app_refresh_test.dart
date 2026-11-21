import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/app_refresh.dart';

void main() {
  tearDown(() => AppRefresh.debugSources = null);

  Widget app() => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: AppRefreshIndicator(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const <Widget>[Text('שורה')],
          ),
        ),
      ),
    ),
  );

  testWidgets('a pull asks the sources and keeps the page as it is', (
    WidgetTester tester,
  ) async {
    int pulls = 0;
    AppRefresh.debugSources = (BuildContext context, RefreshScope scope) async {
      pulls++;
    };
    await tester.pumpWidget(app());
    await tester.fling(find.text('שורה'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(pulls, 1);
    expect(find.text('שורה'), findsOneWidget);
    expect(find.text(AppRefresh.failedMessage), findsNothing);
  });

  testWidgets('a pull that fails stops and offers "נסה שוב"', (
    WidgetTester tester,
  ) async {
    int pulls = 0;
    AppRefresh.debugSources = (BuildContext context, RefreshScope scope) async {
      pulls++;
      throw StateError('no server');
    };
    await tester.pumpWidget(app());
    await tester.fling(find.text('שורה'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text(AppRefresh.failedMessage), findsOneWidget);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    await tester.tap(find.text(AppRefresh.retryLabel));
    await tester.pumpAndSettle();
    expect(pulls, 2);
    await tester.pump(const Duration(seconds: 10));
  });
}
