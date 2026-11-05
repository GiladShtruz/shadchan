import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/widgets/personal_community_news.dart';

void main() {
  Widget app({bool reducedMotion = false}) => ChangeNotifierProvider(
    create: (_) => PersonalAreaProvider(enabled: false)
      ..news = const [
        PersonalNews(id: 'one', title: 'עדכון ראשון', text: 'נפגשים לחשוב יחד'),
        PersonalNews(id: 'two', title: 'עדכון שני', text: 'עוד חברים הצטרפו'),
      ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: PersonalCommunityNews()),
        ),
      ),
    ),
  );

  testWidgets('manual reading pauses rotation until explicitly resumed', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('העדכון הבא'));
    await tester.pumpAndSettle();
    expect(find.text('עדכון שני'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('עדכון שני'), findsOneWidget);
    await tester.tap(find.byTooltip('המשך מעבר אוטומטי'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('עדכון ראשון'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background lifecycle suspends the timer', (tester) async {
    await tester.pumpWidget(app());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('עדכון ראשון'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('עדכון שני'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion keeps manual navigation available', (
    tester,
  ) async {
    await tester.pumpWidget(app(reducedMotion: true));
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('עדכון ראשון'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    await tester.tap(find.byTooltip('העדכון הבא'));
    await tester.pumpAndSettle();
    expect(find.text('עדכון שני'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
