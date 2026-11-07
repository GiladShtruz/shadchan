import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/widgets/area_switch_button.dart';
import 'package:shadchan/widgets/offline_banner.dart';

void main() {
  setUp(() {
    ConnectivityStatus.debugSetOffline(false);
    OfflineGuard.debugReset();
  });
  tearDown(() => ConnectivityStatus.debugSetOffline(false));

  Widget harness(Widget child) => MaterialApp(
    builder: (BuildContext context, Widget? routed) => Directionality(
      textDirection: TextDirection.rtl,
      child: OfflineBanner(child: routed!),
    ),
    home: Scaffold(appBar: AppBar(title: const Text('בית')), body: child),
  );

  testWidgets('a small line says so while offline, and only then', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(harness(const SizedBox()));
    expect(find.text(OfflineBanner.offlineText), findsNothing);

    ConnectivityStatus.debugSetOffline(true);
    await tester.pumpAndSettle();
    expect(find.text(OfflineBanner.offlineText), findsOneWidget);
    // The page is still there, under it.
    expect(find.text('בית'), findsOneWidget);

    ConnectivityStatus.debugSetOffline(false);
    await tester.pump();
    expect(find.text(OfflineBanner.offlineText), findsNothing);
    expect(find.text(OfflineBanner.backOnlineText), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(OfflineBanner.backOnlineText), findsNothing);
  });

  testWidgets('the screens underneath keep their state across the switch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(harness(const _Counter()));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    ConnectivityStatus.debugSetOffline(true);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    ConnectivityStatus.debugSetOffline(false);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an edit started offline is stopped, with the message', (
    WidgetTester tester,
  ) async {
    bool started = false;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () {
              if (OfflineGuard.allow(context)) {
                started = true;
              }
            },
            child: const Text('עריכה'),
          ),
        ),
      ),
    );

    ConnectivityStatus.debugSetOffline(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('עריכה'));
    await tester.pump();
    expect(started, isFalse);
    expect(
      find.text('שים לב, אתה במצב לא מקוון. עריכות לא יישמרו.'),
      findsOneWidget,
    );

    ConnectivityStatus.debugSetOffline(false);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עריכה'));
    expect(started, isTrue);
  });

  testWidgets('both ways across are the same button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Column(
          children: <Widget>[
            AreaSwitchButton(label: 'למעבר לאזור האישי', onTap: () {}),
            AreaSwitchButton(label: 'למעבר לאזור השדכן', onTap: () {}),
          ],
        ),
      ),
    );
    final List<Size> sizes = <Size>[
      tester.getSize(find.byType(AreaSwitchButton).first),
      tester.getSize(find.byType(AreaSwitchButton).last),
    ];
    expect(sizes.first.height, sizes.last.height);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNWidgets(2));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text('$_count'),
      TextButton(
        onPressed: () => setState(() => _count++),
        child: const Text('+'),
      ),
    ],
  );
}
